"""Deterministic preparation and lifecycle for pr-sanity and fable-review."""

import argparse
import hashlib
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

SKILLS = Path(__file__).resolve().parent.parent / "skills"
CHUNK_BYTES = 16000
CHECKS = {
    "internal_consistency",
    "conversational_residue",
    "context_leak",
    "verbose_comment",
    "scaffolding",
    "body_diff_mismatch",
    "naming_residue",
    "unverifiable_claim",
    "issue_ref_in_code",
    "body_register",
}
KINDS = {
    "could_not_follow",
    "unanchored_reference",
    "talks_past_me",
    "seems_out_of_place",
    "other",
}
ARTIFACTS = {"code", "pr_body", "doc", "issue"}


class ReviewError(Exception):
    pass


def command(args, cwd, check=True, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, check=False, capture_output=True)
    if check and result.returncode:
        raise ReviewError(
            result.stderr.decode(errors="replace").strip()
            or "command failed: " + shlex.join(map(str, args))
        )
    return result


def git(repo, *args, check=True, env=None):
    return command(["git", *args], repo, check, env)


def git_text(repo, *args):
    return git(repo, *args).stdout.decode().strip()


def write_json(path, value):
    path = Path(path)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, encoding="utf-8", delete=False
    ) as handle:
        temporary = Path(handle.name)
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temporary, path)


def load_state(repo, skill):
    path = repo / ".worktrees" / skill / ".review" / "state.json"
    try:
        state = json.loads(path.read_text())
    except (FileNotFoundError, ValueError) as error:
        raise ReviewError("no valid prepared run: " + str(path)) from error
    if state["repo_path"] != str(repo) or state["skill"] != skill:
        raise ReviewError("run state does not belong to this checkout and skill")
    return path, state


def chunks(patch, directory):
    """Split without dropping bytes; prefer line boundaries and preserve UTF-8."""
    data = patch.read_bytes()
    directory.mkdir()
    entries = []
    start = 0
    while start < len(data):
        end = min(start + CHUNK_BYTES, len(data))
        if end < len(data):
            newline = data.rfind(b"\n", start, end)
            if newline >= start:
                end = newline + 1
            else:
                while end > start and data[end] & 0xC0 == 0x80:
                    end -= 1
        part = directory / f"{len(entries) + 1:04d}.patch"
        part.write_bytes(data[start:end])
        entries.append(
            {
                "path": str(part.relative_to(patch.parent)),
                "byte_start": start,
                "byte_end": end,
                "bytes": end - start,
                "lines": len(data[start:end].splitlines()),
                "sha256": hashlib.sha256(data[start:end]).hexdigest(),
            }
        )
        start = end
    index = {
        "patch": patch.name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "chunks": entries,
    }
    write_json(patch.parent / "diff-index.json", index)
    return index


def changed_files(repo, base, head):
    stats = {}
    raw = git(repo, "diff", "--numstat", "-z", "-M", "-C", base, head).stdout
    fields = iter(raw.split(b"\0")[:-1])
    for field in fields:
        added, removed, path = field.split(b"\t", 2)
        if not path:
            next(fields)  # source of a rename/copy
            path = next(fields)
        stats[os.fsdecode(path)] = (
            {"binary": True}
            if added == b"-"
            else {"additions": int(added), "deletions": int(removed)}
        )
    raw = git(repo, "diff", "--name-status", "-z", "-M", "-C", base, head).stdout
    fields = iter(raw.split(b"\0")[:-1])
    files = []
    for status in fields:
        entry = {"status": status.decode()[0]}
        if entry["status"] in {"R", "C"}:
            entry["from"] = os.fsdecode(next(fields))
        entry["path"] = os.fsdecode(next(fields))
        entry.update(stats[entry["path"]])
        files.append(entry)
    return files


def closing_issues(body, repo_name):
    pattern = (
        r"\b(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+"
        r"(?:\[)?(https?://[^\s)\]>]+/issues/\d+|"
        r"[\w.-]+/[\w.-]+#\d+|#\d+)\b"
    )
    refs = []
    for match in re.finditer(pattern, body, re.IGNORECASE):
        ref = match.group(1)
        if ref.startswith("#"):
            ref = repo_name + ref
        if ref not in refs:
            refs.append(ref)
    return refs


def repository_name(remote):
    match = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?/?$", remote)
    if not match:
        raise ReviewError("cannot resolve owner/repo from origin: " + remote)
    return match.group(1)


def prepare(repo, skill, args):
    branch = git_text(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    remote = git_text(repo, "remote", "get-url", "origin")
    repo_name = repository_name(remote)
    default_ref = git(
        repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD", check=False
    )
    default = default_ref.stdout.decode().strip().removeprefix("origin/")
    if not default:
        default = next(
            (
                name
                for name in ("main", "master")
                if not git(
                    repo,
                    "show-ref",
                    "--verify",
                    "--quiet",
                    "refs/remotes/origin/" + name,
                    check=False,
                ).returncode
            ),
            "main",
        )
    if branch == default:
        raise ReviewError("review requires a feature branch")
    if git(repo, "status", "--porcelain").stdout and not args.allow_dirty:
        raise ReviewError(
            "uncommitted changes are excluded; commit first or use "
            "--allow-dirty after deciding to review committed state"
        )
    wt = repo / ".worktrees" / skill
    if wt.exists():
        raise ReviewError(
            "existing run; collect or cleanup it before preparing another"
        )
    if git(repo, "check-ignore", "--quiet", ".worktrees/", check=False).returncode:
        ignore = repo / ".gitignore"
        previous = ignore.read_text() if ignore.exists() else ""
        ignore.write_text(
            previous
            + ("\n" if previous and not previous.endswith("\n") else "")
            + ".worktrees/\n"
        )

    pr = None
    if not args.pre_pr:
        result = command(
            ["gh", "pr", "view", "--json", "body,baseRefName,number"], repo, check=False
        )
        if not result.returncode:
            pr = json.loads(result.stdout)
        elif "no pull requests found" not in result.stderr.decode().lower():
            raise ReviewError(
                result.stderr.decode().strip()
                + "; use --pre-pr only when reviewing without a PR"
            )
    target = args.target or (pr["baseRefName"] if pr else default)
    notes = []
    setup_script = repo / "scripts/setup-worktree.sh"
    if setup_script.is_file():
        notes.append(
            "Run the repo's scripts/setup-worktree.sh with its documented arguments "
            "for this worktree before launch"
        )
    if git(repo, "fetch", "origin", target, check=False).returncode:
        notes.append("fetch failed; using the existing origin/" + target)
    base = git_text(repo, "merge-base", "origin/" + target, "HEAD")
    head = git_text(repo, "rev-parse", "HEAD")
    body = pr["body"] if pr else None
    if not pr:
        candidates = (
            [Path(args.body)]
            if args.body
            else [repo / ".github/PR_BODY.md", repo / "PR_BODY.md"]
        )
        for candidate in candidates:
            candidate = candidate if candidate.is_absolute() else repo / candidate
            if candidate.is_file():
                body = candidate.read_text()
                break
        if args.body and body is None:
            raise ReviewError("body file does not exist: " + args.body)
    if body is None and skill == "pr-sanity":
        raise ReviewError("pr-sanity needs a PR body; draft one before preparing")
    if body is None:
        notes.append("PR body missing; reviewing the diff alone")
    issues = []
    for ref in closing_issues(body or "", repo_name):
        if ref.startswith("http"):
            gh_args = ["gh", "issue", "view", ref]
        else:
            owner_repo, number = ref.rsplit("#", 1)
            gh_args = ["gh", "issue", "view", number, "--repo", owner_repo]
        issues.append(
            json.loads(
                command(gh_args + ["--json", "title,body,url,number"], repo).stdout
            )
        )
    problem = {
        "type": "issue" if issues else "none",
        "refs": [issue["url"] for issue in issues],
    }
    if not issues and args.plan:
        plan = (repo / args.plan).resolve()
        if not plan.is_relative_to(repo) or not plan.is_file():
            raise ReviewError("plan must be a file inside this checkout")
        relative = str(plan.relative_to(repo))
        git(repo, "cat-file", "-e", head + ":" + relative)
        problem = {"type": "plan_doc", "refs": [relative]}
    if problem["type"] == "none":
        notes.append("no linked issue or committed problem-source plan")
    diff_args = ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "--binary"]
    if skill == "pr-sanity":
        diff_args.append("-W")
    patch = git(repo, *diff_args, base, head).stdout
    if not patch and skill == "fable-review":
        raise ReviewError("empty diff; nothing to attack")
    git(repo, "worktree", "add", "--detach", str(wt), head)
    try:
        runtime_names = (
            []
            if setup_script.is_file()
            else [".venv"] + [p.name for p in repo.glob(".env*")]
        )
        for name in runtime_names:
            source = repo / name
            if (
                source.exists()
                and not (wt / name).exists()
                and not git(
                    repo, "check-ignore", "--quiet", name, check=False
                ).returncode
            ):
                (wt / name).symlink_to(source, target_is_directory=source.is_dir())
        review = wt / ".review"
        (review / "out").mkdir(parents=True)
        (review / "diff.patch").write_bytes(patch)
        chunks(review / "diff.patch", review / "diff-parts")
        if body is not None:
            (review / "body.md").write_text(body)
        if issues:
            (review / "issue.md").write_text(
                "\n\n".join(
                    f"# #{issue['number']} — {issue['title']}\n{issue['url']}\n\n{issue['body']}"
                    for issue in issues
                )
            )
        manifest = {
            "mode": "post_ready" if pr else "pre_pr",
            "repo": repo_name,
            "pr_number": pr["number"] if pr else 0,
            "branch": branch,
            "target": target,
            "merge_base": base,
            "head": head,
            "problem_source": problem,
            "files": changed_files(repo, base, head),
            "notes": notes,
        }
        write_json(review / "manifest.json", manifest)
        if skill == "fable-review":
            (review / "prompt.md").write_bytes(
                (SKILLS / skill / "prompts/review.md").read_bytes()
            )
        state = {
            "skill": skill,
            "repo_path": str(repo),
            "worktree": str(wt),
            "head": head,
            "sid": str(uuid.uuid4()),
            "jobs": {},
            "workspace": os.environ.get("CMUX_WORKSPACE_ID"),
            "surface": os.environ.get("CMUX_SURFACE_ID"),
        }
        write_json(review / "state.json", state)
    except Exception:
        git(repo, "worktree", "remove", "--force", str(wt))
        raise
    return {
        "state": str(review / "state.json"),
        "manifest": str(review / "manifest.json"),
        "diff_index": str(review / "diff-index.json"),
        "notes": notes,
    }


def cmux(state, *args):
    flags = ["--workspace", state["workspace"]] if state["workspace"] else []
    return command(["cmux", *args, *flags], state["repo_path"]).stdout.decode().strip()


def dispatch(path, state, jobs, headless=False):
    processes = []
    previous = state.get("surface")
    try:
        for tag in jobs:
            job = state["jobs"][tag]
            if job.get("launched"):
                raise ReviewError("job was already launched: " + tag)
            worker_args = [
                sys.executable,
                str(Path(__file__).resolve()),
                "--skill",
                state["skill"],
                "--repo",
                state["repo_path"],
                "worker",
                "--job",
                tag,
            ]
            if headless:
                job["transport"] = "headless"
                job["launched"] = True
                write_json(path, state)
                log = Path(state["worktree"]) / ".review/out" / (tag + "-pane.log")
                with log.open("wb") as handle:
                    processes.append(
                        subprocess.Popen(
                            worker_args, stdout=handle, stderr=subprocess.STDOUT
                        )
                    )
            else:
                original = state["jobs"].get(job["reader"], {})
                if original.get("surface"):
                    job["surface"] = original["surface"]
                else:
                    split_args = [
                        "--id-format",
                        "uuids",
                        "new-split",
                        "down" if tag == "lint" else "right",
                    ]
                    if previous:
                        split_args += ["--surface", previous]
                    response = cmux(state, *split_args)
                    match = re.search(r"^OK\s+(\S+)", response, re.MULTILINE)
                    if not match:
                        raise ReviewError("could not parse cmux surface: " + response)
                    job["surface"] = match.group(1)
                previous = job["surface"]
                job["transport"] = "cmux"
                job["launched"] = True
                write_json(path, state)
                cmux(
                    state,
                    "rename-tab",
                    "--surface",
                    job["surface"],
                    state["skill"] + ": " + tag,
                )
                cmux(
                    state,
                    "send",
                    "--surface",
                    job["surface"],
                    shlex.join(worker_args) + "\n",
                )
        for process in processes:
            if process.wait():
                raise ReviewError("reviewer failed; collect the recorded outcome")
    except BaseException:
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            process.wait(timeout=5)
        raise
    return {"state": str(path), "jobs": jobs}


def launch(repo, skill, args):
    path, state = load_state(repo, skill)
    if state["jobs"]:
        raise ReviewError("run already launched; use followup or retry as appropriate")
    for tag in ["cold", "lint"] if skill == "pr-sanity" else ["review"]:
        prompt = (
            SKILLS / skill / "prompts" / (tag + ".md")
            if skill == "pr-sanity"
            else Path(state["worktree"]) / ".review/prompt.md"
        )
        state["jobs"][tag] = {"prompt": str(prompt), "reader": tag}
    write_json(path, state)
    return dispatch(path, state, list(state["jobs"]), args.headless)


def worker(repo, skill, tag):
    _, state = load_state(repo, skill)
    job = state["jobs"][tag]
    out = Path(state["worktree"]) / ".review/out"
    if (out / (tag + ".rc")).exists():
        raise ReviewError("completed job cannot run again: " + tag)
    argv = [
        "claude",
        "--model",
        "sonnet" if skill == "pr-sanity" else "claude-fable-5-1",
        "--effort",
        "high",
        "--permission-mode",
        "auto" if skill == "pr-sanity" else "bypassPermissions",
        "--output-format",
        "stream-json",
        "--verbose",
        "-p",
    ]
    if skill == "pr-sanity":
        argv.append("--strict-mcp-config")
    else:
        argv += ["--resume" if job.get("resume") else "--session-id", state["sid"]]
    prompt = Path(job["prompt"]).read_bytes()
    if job.get("correction"):
        prompt += b"\n\n" + Path(job["correction"]).read_bytes()
    process = None
    rc = 1

    def interrupted(_signum, _frame):
        raise KeyboardInterrupt()

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        with (
            (out / (tag + ".err.log")).open("ab") as errors,
            (out / (tag + ".jsonl")).open("wb") as raw,
            tempfile.TemporaryFile() as stdin,
        ):
            stdin.write(prompt)
            stdin.seek(0)
            process = subprocess.Popen(
                argv,
                cwd=state["worktree"],
                stdin=stdin,
                stdout=subprocess.PIPE,
                stderr=errors,
                start_new_session=True,
            )
            write_json(out / (tag + ".pid.json"), {"pid": process.pid})
            for line in process.stdout:
                raw.write(line)
                raw.flush()
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(event, dict):
                    continue
                if event.get("type") == "assistant":
                    message = event.get("message")
                    if not isinstance(message, dict) or not isinstance(
                        message.get("content"), list
                    ):
                        continue
                    for block in message["content"]:
                        if not isinstance(block, dict):
                            continue
                        if block.get("type") == "text":
                            print(block.get("text", ""), flush=True)
                        elif block.get("type") == "tool_use":
                            print("→ " + str(block.get("name", "tool")), flush=True)
            rc = process.wait()
    except (KeyboardInterrupt, OSError) as error:
        if process and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        with (out / (tag + ".err.log")).open("a") as errors:
            errors.write(str(error) + "\n")
    finally:
        if process and process.stdout:
            process.stdout.close()
        (out / (tag + ".rc")).write_text(str(rc) + "\n")
    return rc


def selected_jobs(state, tag):
    if tag:
        if tag not in state["jobs"]:
            raise ReviewError("unknown job: " + tag)
        return [tag]
    if state["skill"] == "pr-sanity":
        return [
            reader + "-retry" if reader + "-retry" in state["jobs"] else reader
            for reader in ("cold", "lint")
        ]
    return [next(reversed(state["jobs"]))] if state["jobs"] else []


def wait(repo, skill, args):
    path, state = load_state(repo, skill)
    tags = selected_jobs(state, args.job)
    if not tags:
        raise ReviewError("no reviewer launched")
    out = Path(state["worktree"]) / ".review/out"
    deadline = time.monotonic() + args.timeout
    while not all((out / (tag + ".rc")).exists() for tag in tags):
        if time.monotonic() >= deadline:
            raise ReviewError(
                "wait timed out; inspect log growth and errors before aborting"
            )
        time.sleep(min(1, max(0, deadline - time.monotonic())))
    return {"state": str(path), "completed": tags}


def validate_report(reader, report):
    """Validate structure without interpreting findings or altering the report."""
    if not isinstance(report, dict):
        raise ReviewError(reader + " report must be a JSON object")
    key = "stumbles" if reader == "cold" else "findings"
    entries = report.get(key, [])
    if not isinstance(entries, list):
        raise ReviewError(key + " must be a list")
    if reader == "cold" and not isinstance(report.get("narration"), str):
        raise ReviewError("cold report needs a narration string")
    if reader == "cold" and not report["narration"].strip():
        raise ReviewError("cold narration is empty")
    if reader == "lint":
        clean = report.get("clean_checks", [])
        if not isinstance(clean, list) or any(
            not isinstance(check, str) or check not in CHECKS for check in clean
        ):
            raise ReviewError("invalid clean_checks")
        if not isinstance(report.get("coverage_notes", ""), str):
            raise ReviewError("coverage_notes must be a string")
    for entry in entries:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("artifact"), str)
            or entry["artifact"] not in ARTIFACTS
        ):
            raise ReviewError("invalid finding artifact")
        location = entry.get("location", {})
        if not isinstance(location, dict) or not isinstance(location.get("file"), str):
            raise ReviewError("finding needs a file location")
        start, end = location.get("line_start"), location.get("line_end")
        if (
            type(start) is not int
            or type(end) is not int
            or start < 1
            or end < start
            or not location["file"]
        ):
            raise ReviewError("invalid finding line range")
        text_keys = ("quote", "note") if reader == "cold" else ("quote", "evidence")
        if any(
            not isinstance(entry.get(key), str) or not entry[key].strip()
            for key in text_keys
        ):
            raise ReviewError("finding has empty quote or explanation")
        label, allowed = ("kind", KINDS) if reader == "cold" else ("check", CHECKS)
        if not isinstance(entry.get(label), str) or entry[label] not in allowed:
            raise ReviewError("invalid finding " + label)
        if reader == "lint" and (
            not isinstance(entry.get("confidence"), str)
            or entry["confidence"] not in {"high", "medium", "low"}
        ):
            raise ReviewError("invalid confidence")
    return len(entries)


def collect(repo, skill, args):
    _, state = load_state(repo, skill)
    out = Path(state["worktree"]) / ".review/out"
    artifacts = []
    usage = []
    tags = selected_jobs(state, args.job)
    if not tags:
        raise ReviewError("no reviewer launched")
    for tag in tags:
        sentinel = out / (tag + ".rc")
        if not sentinel.exists():
            raise ReviewError("job still running: " + tag)
        if sentinel.read_text().strip() != "0":
            raise ReviewError(
                "job failed: " + tag + "; inspect " + str(out / (tag + ".err.log"))
            )
        result = None
        with (out / (tag + ".jsonl")).open() as raw:
            for line in raw:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if isinstance(event, dict) and event.get("type") == "result":
                    result = event
        if result is None or result.get("is_error"):
            raise ReviewError("missing or error result envelope: " + tag)
        usage.append(
            {
                "job": tag,
                "usage": result.get("usage"),
                "modelUsage": result.get("modelUsage"),
                "cost_usd": result.get("total_cost_usd"),
            }
        )
        if skill == "pr-sanity":
            reader = state["jobs"][tag]["reader"]
            artifact = out / (reader + ".json")
            try:
                report = json.loads(artifact.read_text())
            except (ValueError, FileNotFoundError) as error:
                raise ReviewError("invalid/missing report: " + str(artifact)) from error
            count = validate_report(reader, report)
        else:
            if (
                not isinstance(result.get("result"), str)
                or not result["result"].strip()
            ):
                raise ReviewError("review result is empty: " + tag)
            artifact = out / (tag + ".md")
            artifact.write_text(result["result"])
            count = None
        artifacts.append(
            {
                "path": str(artifact),
                "bytes": artifact.stat().st_size,
                "lines": len(artifact.read_text().splitlines()),
                "findings": count,
            }
        )
    usage_path = out / "usage.json"
    recorded = json.loads(usage_path.read_text()) if usage_path.exists() else []
    by_job = {entry["job"]: entry for entry in recorded + usage}
    write_json(usage_path, list(by_job.values()))
    return {"artifacts": artifacts, "usage": str(out / "usage.json")}


def ensure_idle(state):
    out = Path(state["worktree"]) / ".review/out"
    for tag, job in state["jobs"].items():
        if job.get("launched") and not (out / (tag + ".rc")).exists():
            raise ReviewError("job has not completed: " + tag)


def followup(repo, skill, args):
    path, state = load_state(repo, skill)
    ensure_idle(state)
    if skill != "fable-review" or "review" not in state["jobs"]:
        raise ReviewError("followup requires an existing Fable review session")
    number = sum(tag.startswith("followup-") for tag in state["jobs"]) + 1
    tag = "followup-" + str(number)
    prompt = Path(state["worktree"]) / ".review" / (tag + ".txt")
    prompt.write_bytes(Path(args.prompt).resolve().read_bytes())
    state["jobs"][tag] = {"prompt": str(prompt), "reader": "review", "resume": True}
    write_json(path, state)
    return dispatch(path, state, [tag], args.headless)


def retry(repo, skill, args):
    path, state = load_state(repo, skill)
    ensure_idle(state)
    tag = args.reader + "-retry"
    if skill != "pr-sanity" or args.reader not in state["jobs"] or tag in state["jobs"]:
        raise ReviewError("only one corrective retry per existing Sonnet reader")
    correction = Path(state["worktree"]) / ".review" / (tag + ".txt")
    correction.write_bytes(Path(args.prompt).resolve().read_bytes())
    state["jobs"][tag] = {
        "prompt": state["jobs"][args.reader]["prompt"],
        "reader": args.reader,
        "correction": str(correction),
    }
    report = Path(state["worktree"]) / ".review/out" / (args.reader + ".json")
    if report.exists():
        report.rename(report.with_suffix(".invalid.json"))
    write_json(path, state)
    return dispatch(path, state, [tag], args.headless)


def signoff(repo, skill, args):
    path, state = load_state(repo, skill)
    ensure_idle(state)
    if skill != "fable-review" or "review" not in state["jobs"]:
        raise ReviewError("signoff requires an existing Fable review session")
    if git_text(repo, "rev-parse", "HEAD") != state["head"]:
        raise ReviewError("HEAD moved; review committed fixes in a fresh run")
    wt = Path(state["worktree"])
    review = wt / ".review"
    round_number = sum(tag.startswith("verdict-") for tag in state["jobs"]) + 1
    tag = "verdict-" + str(round_number)
    patch = review / f"fixes-{round_number}.patch"
    # Read the tree into a fresh index, so this also works before any real index exists.
    with tempfile.TemporaryDirectory(prefix="review-index-") as temporary:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        git(repo, "read-tree", state["head"], env=env)
        git(repo, "add", "-A", env=env)
        snapshot = git(repo, "write-tree", env=env).stdout.decode().strip()
        patch.write_bytes(
            git(
                repo,
                "diff",
                "--binary",
                "--no-color",
                "--no-ext-diff",
                "--no-textconv",
                state["head"],
                snapshot,
            ).stdout
        )
    # .review is an untracked directory reserved for lifecycle state and logs.
    if git(repo, "ls-tree", snapshot, "--", ".review").stdout:
        raise ReviewError("fix snapshot contains reserved .review tooling")
    # Git handles file/directory/symlink transitions without traversing symlink
    # ancestors in Python. .review and noncolliding scratch/runtime files survive.
    git(wt, "read-tree", "--reset", "-u", snapshot)
    write_json(
        review / f"snapshot-{round_number}.json",
        {"tree": snapshot, "patch": str(patch)},
    )
    findings = Path(args.findings).resolve().read_text()
    prompt = review / (tag + ".txt")
    prompt.write_text(
        "The checkout now contains the complete current fix snapshot. "
        "Your original review HEAD is unchanged; the index and files hold the fixes.\n"
        f"Read .review/fixes-{round_number}.patch and verify these accepted findings against "
        "the files and their affected interactions. For each F<n>, return "
        "addressed / not addressed / new concern, with one line of evidence. "
        "Investigate new concerns exposed by the fixes to the same evidence "
        f"standard as your review.\n\n{findings}\n"
    )
    state["jobs"][tag] = {"prompt": str(prompt), "reader": "review", "resume": True}
    write_json(path, state)
    return dispatch(path, state, [tag], args.headless)


def read_artifact(args):
    if args.offset < 0 or not 1 <= args.limit <= 4000:
        raise ReviewError(
            "read requires a nonnegative character offset and limit 1..4000"
        )
    path = Path(args.path).resolve()
    content = path.read_text()
    if args.offset > len(content):
        raise ReviewError("character offset exceeds artifact length")
    end = min(args.offset + args.limit, len(content))
    return {
        "path": str(path),
        "character_start": args.offset,
        "character_end": end,
        "total_characters": len(content),
        "text": content[args.offset : end],
    }


def cleanup(repo, skill, args):
    _, state = load_state(repo, skill)
    out = Path(state["worktree"]) / ".review/out"
    if not args.abort:
        ensure_idle(state)
    else:
        for tag in state["jobs"]:
            pid_file = out / (tag + ".pid.json")
            if pid_file.exists() and not (out / (tag + ".rc")).exists():
                pid = json.loads(pid_file.read_text())["pid"]
                try:
                    os.killpg(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            running = [
                tag
                for tag, job in state["jobs"].items()
                if job.get("launched") and not (out / (tag + ".rc")).exists()
            ]
            if not running:
                break
            time.sleep(0.1)
        ensure_idle(state)
    if args.archive:
        destination = Path(args.archive).resolve()
        destination.mkdir(parents=True, exist_ok=False)
        for file in out.iterdir():
            if file.is_file() and file.suffix in {".json", ".md"}:
                (destination / file.name).write_bytes(file.read_bytes())
    for surface in {
        job["surface"] for job in state["jobs"].values() if job.get("surface")
    }:
        cmux(state, "close-surface", "--surface", surface)
    git(repo, "worktree", "remove", "--force", state["worktree"])
    return {"removed": state["worktree"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skill", required=True, choices=["pr-sanity", "fable-review"])
    parser.add_argument("--repo", default=".")
    commands = parser.add_subparsers(dest="action", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--allow-dirty", action="store_true")
    prepare_parser.add_argument("--pre-pr", action="store_true")
    prepare_parser.add_argument("--body")
    prepare_parser.add_argument("--plan")
    prepare_parser.add_argument("--target")
    commands.add_parser("launch").add_argument("--headless", action="store_true")
    commands.add_parser("worker").add_argument("--job", required=True)
    wait_parser = commands.add_parser("wait")
    wait_parser.add_argument("--job")
    wait_parser.add_argument("--timeout", type=float, default=1800)
    commands.add_parser("collect").add_argument("--job")
    read_parser = commands.add_parser("read")
    read_parser.add_argument("--path", required=True)
    read_parser.add_argument("--offset", type=int, default=0)
    read_parser.add_argument("--limit", type=int, default=4000)
    for action in ("followup", "retry", "signoff"):
        subparser = commands.add_parser(action)
        subparser.add_argument("--headless", action="store_true")
        subparser.add_argument(
            "--findings" if action == "signoff" else "--prompt", required=True
        )
        if action == "retry":
            subparser.add_argument("--reader", required=True, choices=["cold", "lint"])
    cleanup_parser = commands.add_parser("cleanup")
    cleanup_parser.add_argument("--abort", action="store_true")
    cleanup_parser.add_argument("--archive")
    args = parser.parse_args()
    try:
        if args.action == "read":
            print(json.dumps(read_artifact(args), ensure_ascii=False, indent=2))
            return 0
        repo = Path(git_text(Path(args.repo).resolve(), "rev-parse", "--show-toplevel"))
        if args.action == "worker":
            return worker(repo, args.skill, args.job)
        function = {
            "prepare": prepare,
            "launch": launch,
            "wait": wait,
            "collect": collect,
            "followup": followup,
            "retry": retry,
            "signoff": signoff,
            "cleanup": cleanup,
        }[args.action]
        print(
            json.dumps(function(repo, args.skill, args), ensure_ascii=False, indent=2)
        )
        return 0
    except (ReviewError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
