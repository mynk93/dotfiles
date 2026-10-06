import argparse
import copy
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = (
    Path(__file__).resolve().parents[1] / "home/dot_claude/scripts/review_workflow.py"
)
SPEC = importlib.util.spec_from_file_location("review_workflow", SCRIPT)
workflow = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(workflow)

NARRATION = "The change adds a reader and updates its editor configuration."
COLD_REPORT = {
    "narration": NARRATION,
    "stumbles": [
        {
            "artifact": "code",
            "location": {"file": "reader.txt", "line_start": 1, "line_end": 1},
            "quote": "reader",
            "kind": "unanchored_reference",
            "note": "The name has no anchor.",
        }
    ],
}
LINT_REPORT = {
    "findings": [
        {
            "artifact": "code",
            "location": {"file": "reader.txt", "line_start": 1, "line_end": 1},
            "quote": "reader",
            "check": "context_leak",
            "evidence": "The name has no anchor.",
            "confidence": "high",
        }
    ],
    "clean_checks": ["naming_residue"],
    "coverage_notes": "",
}


class GitRepositoryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="review workflow ")
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "checkout with spaces"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Review fixture")
        self.git("config", "user.email", "review@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.autocrlf", "false")
        (self.repo / ".gitignore").write_text(".worktrees/\n.venv/\n.env*\n")
        (self.repo / "reader.txt").write_text("original\n" * 20)
        (self.repo / "obsolete.txt").write_text("obsolete\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "chore: Initialize fixture")
        self.base = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.remote = self.root / "remote.git"
        subprocess.run(
            ["git", "clone", "--bare", str(self.repo), str(self.remote)],
            check=True,
            capture_output=True,
        )
        self.git("remote", "add", "origin", str(self.remote))
        self.git("fetch", "origin")
        self.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        self.git("checkout", "-qb", "feature")
        (self.repo / "reader.txt").write_text("changed\n" + "original\n" * 19)
        self.git("add", "-A")
        self.git("commit", "-qm", "feat: Change reader")
        self.head = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.body = self.root / "body.md"
        self.body.write_text("The change updates the reader.\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.environment = patch.dict(
            os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ["PATH"]}
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.addCleanup(self.temporary.cleanup)
        self.fake_claude()

    def git(self, *args, cwd=None, check=True):
        return subprocess.run(
            ["git", *args],
            cwd=cwd or self.repo,
            check=check,
            capture_output=True,
        )

    def prepare(self, skill="fable-review", **options):
        defaults = {
            "pre_pr": True,
            "allow_dirty": False,
            "body": str(self.body),
            "plan": None,
            "target": None,
        }
        defaults.update(options)
        return workflow.prepare(self.repo, skill, argparse.Namespace(**defaults))

    def cli(self, skill, action, *args, check=True):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--skill",
                skill,
                "--repo",
                str(self.repo),
                action,
                *args,
            ],
            capture_output=True,
            check=False,
        )
        if check and result.returncode:
            self.fail(result.stderr.decode() + result.stdout.decode())
        return result

    def fake_claude(self):
        executable = self.bin / "claude"
        executable.write_text(
            "#!"
            + sys.executable
            + "\n"
            + """
import json, os, pathlib, sys, time
prompt = sys.stdin.read()
pathlib.Path('.review/out/invocation.json').write_text(json.dumps({'args': sys.argv[1:], 'prompt': prompt}))
if os.environ.get('FAKE_SLEEP'):
    time.sleep(float(os.environ['FAKE_SLEEP']))
reader = 'cold' if 'arriving completely cold' in prompt else 'lint'
if '--model' in sys.argv and sys.argv[sys.argv.index('--model')+1] == 'sonnet':
    report = json.loads(os.environ['FAKE_COLD' if reader == 'cold' else 'FAKE_LINT'])
    pathlib.Path('.review/out/' + reader + '.json').write_text(json.dumps(report))
result = {'type': 'result', 'is_error': False, 'result': '## Verdict\\nship\\n', 'usage': {'output_tokens': 7}}
if os.environ.get('FAKE_ERROR'):
    result['is_error'] = True
print('non-json diagnostic', flush=True)
print('null', flush=True)
print('42', flush=True)
print('{"type":"assistant","message":null}', flush=True)
print('{"type":"assistant","message":{"content":[null]}}', flush=True)
print(json.dumps({'type':'assistant','message':{'content':[{'type':'text','text':'Review complete'}]}}), flush=True)
if not os.environ.get('FAKE_NO_RESULT'):
    print(json.dumps(result), flush=True)
"""
        )
        executable.chmod(0o755)
        os.environ["FAKE_COLD"] = json.dumps(COLD_REPORT)
        os.environ["FAKE_LINT"] = json.dumps(LINT_REPORT)
        self.addCleanup(os.environ.pop, "FAKE_COLD", None)
        self.addCleanup(os.environ.pop, "FAKE_LINT", None)


class PrepareTests(GitRepositoryTest):
    def test_manifest_and_chunks_cover_the_complete_diff_with_renames_binary_and_spaces(
        self,
    ):
        self.git("mv", "obsolete.txt", "renamed file.txt")
        binary = b"binary\x00fixture"
        (self.repo / "binary.dat").write_bytes(binary)
        odd_name = "new\tfile\nname.txt"
        (self.repo / odd_name).write_text("added\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "feat: Add fixture boundaries")
        result = self.prepare("pr-sanity")
        review = Path(result["manifest"]).parent
        manifest = json.loads(Path(result["manifest"]).read_text())
        self.assertEqual(manifest["merge_base"], self.base)
        self.assertEqual(manifest["target"], "main")
        files = {entry["path"]: entry for entry in manifest["files"]}
        self.assertEqual(
            files["renamed file.txt"],
            {
                "status": "R",
                "from": "obsolete.txt",
                "path": "renamed file.txt",
                "additions": 0,
                "deletions": 0,
            },
        )
        self.assertEqual(
            files["binary.dat"], {"status": "A", "path": "binary.dat", "binary": True}
        )
        self.assertEqual(files[odd_name]["additions"], 1)
        index = json.loads(Path(result["diff_index"]).read_text())
        recombined = b"".join(
            (review / entry["path"]).read_bytes() for entry in index["chunks"]
        )
        self.assertEqual(recombined, (review / "diff.patch").read_bytes())
        self.assertEqual((review / "body.md").read_text(), self.body.read_text())
        self.assertFalse((review / "prompt.md").exists())

    def test_empty_diff_and_missing_body_keep_each_skills_existing_rules(self):
        self.git("reset", "--hard", self.base)
        with self.assertRaisesRegex(workflow.ReviewError, "empty diff"):
            self.prepare()
        result = self.prepare("pr-sanity")
        self.assertEqual(json.loads(Path(result["manifest"]).read_text())["files"], [])
        workflow.cleanup(
            self.repo, "pr-sanity", argparse.Namespace(abort=False, archive=None)
        )
        self.git("reset", "--hard", self.head)
        self.body.unlink()
        with self.assertRaisesRegex(workflow.ReviewError, "needs a PR body"):
            self.prepare("pr-sanity", body=None)
        result = self.prepare(body=None)
        self.assertFalse((Path(result["manifest"]).parent / "body.md").exists())

    def test_missing_merge_base_and_dirty_checkout_fail_before_worktree_creation(self):
        (self.repo / "reader.txt").write_text("uncommitted\n")
        with self.assertRaisesRegex(workflow.ReviewError, "uncommitted"):
            self.prepare()
        with self.assertRaises(workflow.ReviewError):
            self.prepare(allow_dirty=True, target="missing-base")
        self.assertFalse((self.repo / ".worktrees/fable-review").exists())

    def test_runtime_links_are_available_without_copying_environment_contents(self):
        (self.repo / ".venv").mkdir()
        (self.repo / ".env.local").write_text("fixture-only\n")
        result = self.prepare()
        wt = Path(result["manifest"]).parents[1]
        for name in (".venv", ".env.local"):
            with self.subTest(name=name):
                self.assertTrue((wt / name).is_symlink())
                self.assertEqual((wt / name).resolve(), self.repo / name)

    def test_post_pr_uses_its_stack_base_and_fetches_cross_repo_issue_verbatim(self):
        (self.repo / "stack.txt").write_text("stack base\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "feat: Add stack base")
        stack_base = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.git("push", "origin", "HEAD:stack-base")
        (self.repo / "reader.txt").write_text("top layer\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "feat: Add stack top")
        issue_url = "https://github.com/another/project/issues/19"
        gh = self.bin / "gh"
        gh.write_text(
            "#!"
            + sys.executable
            + "\n"
            + """
import json, pathlib, sys
with pathlib.Path('gh-calls.jsonl').open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1:3] == ['pr','view']:
    print(json.dumps({'body':'Fixes https://github.com/another/project/issues/19', 'baseRefName':'stack-base', 'number':29}))
else:
    print(json.dumps({'title':'Fixture issue','body':'Problem statement','url':'https://github.com/another/project/issues/19','number':19}))
"""
        )
        gh.chmod(0o755)
        result = self.prepare(pre_pr=False)
        manifest = json.loads(Path(result["manifest"]).read_text())
        self.assertEqual(manifest["merge_base"], stack_base)
        self.assertEqual([entry["path"] for entry in manifest["files"]], ["reader.txt"])
        self.assertEqual(
            manifest["problem_source"], {"type": "issue", "refs": [issue_url]}
        )
        calls = [
            json.loads(line)
            for line in (self.repo / "gh-calls.jsonl").read_text().splitlines()
        ]
        self.assertEqual(calls[1][2], issue_url)
        self.assertIn(
            "Problem statement",
            (Path(result["manifest"]).parent / "issue.md").read_text(),
        )

    def test_api_failure_does_not_silently_turn_into_a_pre_pr_review(self):
        gh = self.bin / "gh"
        gh.write_text(
            "#!"
            + sys.executable
            + "\nimport sys\nprint('authentication failed',file=sys.stderr)\nsys.exit(1)\n"
        )
        gh.chmod(0o755)
        with self.assertRaisesRegex(workflow.ReviewError, "authentication failed"):
            self.prepare(pre_pr=False)
        self.assertFalse((self.repo / ".worktrees/fable-review").exists())

    def test_shallow_clone_without_a_merge_base_cannot_produce_an_empty_review(self):
        self.git("push", "origin", "HEAD:feature")
        shallow = self.root / "shallow"
        subprocess.run(
            [
                "git",
                "clone",
                "--depth=1",
                "--branch=feature",
                self.remote.as_uri(),
                str(shallow),
            ],
            check=True,
            capture_output=True,
        )
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--skill",
                "pr-sanity",
                "--repo",
                str(shallow),
                "prepare",
                "--pre-pr",
                "--target",
                "main",
                "--body",
                str(self.body),
            ],
            check=False,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertFalse((shallow / ".worktrees/pr-sanity").exists())


class ChunksTests(unittest.TestCase):
    def test_chunks_round_trip_utf8_long_lines_and_unterminated_lines_with_bounded_size(
        self,
    ):
        cases = [
            b"",
            b"short\n",
            ("λ" * workflow.CHUNK_BYTES + "\nlast").encode(),
            b"line\n" * workflow.CHUNK_BYTES,
            b"x" * (workflow.CHUNK_BYTES * 2 + 1),
        ]
        for data in cases:
            with (
                self.subTest(bytes=len(data)),
                tempfile.TemporaryDirectory() as temporary,
            ):
                directory = Path(temporary)
                patch_file = directory / "diff.patch"
                patch_file.write_bytes(data)
                index = workflow.chunks(patch_file, directory / "parts")
                parts = [
                    (directory / entry["path"]).read_bytes()
                    for entry in index["chunks"]
                ]
                self.assertEqual(b"".join(parts), data)
                for part in parts:
                    self.assertLessEqual(len(part), workflow.CHUNK_BYTES)
                    part.decode("utf-8")


class ReadArtifactTests(unittest.TestCase):
    def test_character_pages_preserve_complete_unicode_reports_without_clipping_quotes(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "report.json"
            content = json.dumps(
                {"narration": "λ" * 9000, "quote": "full quote"}, ensure_ascii=False
            )
            artifact.write_text(content)
            offset = 0
            pages = []
            while offset < len(content):
                page = workflow.read_artifact(
                    argparse.Namespace(path=str(artifact), offset=offset, limit=4000)
                )
                pages.append(page["text"])
                self.assertEqual(page["character_start"], offset)
                offset = page["character_end"]
            self.assertEqual("".join(pages), content)
            self.assertEqual(offset, page["total_characters"])


class ClosingIssuesTests(unittest.TestCase):
    def test_keyword_forms_resolve_local_and_cross_repo_references(self):
        keywords = [
            "close",
            "closes",
            "closed",
            "fix",
            "fixes",
            "fixed",
            "resolve",
            "resolves",
            "resolved",
        ]
        repo_name = "owner/project"
        for keyword in keywords:
            with self.subTest(keyword=keyword):
                body = keyword.upper() + " #12; " + keyword + " other/repo#34"
                self.assertEqual(
                    workflow.closing_issues(body, repo_name),
                    ["owner/project#12", "other/repo#34"],
                )
        self.assertEqual(
            workflow.closing_issues("Fixes [#12](url). Closes #12", repo_name),
            ["owner/project#12"],
        )


class ValidateReportTests(unittest.TestCase):
    def test_validator_accepts_every_enum_in_the_reader_output_contracts(self):
        prompts = SCRIPT.parent.parent / "skills/pr-sanity/prompts"
        cold = (prompts / "cold.md").read_text()
        lint = (prompts / "lint.md").read_text()
        kinds = re.search(r'"kind": "([^"]+)"', cold).group(1).split(" | ")
        checks = re.findall(r"^\d+\. `([^`]+)`", lint, re.MULTILINE)
        for kind in kinds:
            report = copy.deepcopy(COLD_REPORT)
            report["stumbles"][0]["kind"] = kind
            with self.subTest(kind=kind):
                self.assertEqual(workflow.validate_report("cold", report), 1)
        for check in checks:
            report = copy.deepcopy(LINT_REPORT)
            report["findings"][0]["check"] = check
            with self.subTest(check=check):
                self.assertEqual(workflow.validate_report("lint", report), 1)

    def test_validation_preserves_reports_and_accepts_the_documented_empty_defaults(
        self,
    ):
        cases = [
            ("cold", COLD_REPORT),
            ("lint", LINT_REPORT),
            ("cold", {"narration": NARRATION}),
            ("lint", {}),
        ]
        for reader, report in cases:
            with self.subTest(reader=reader, keys=list(report)):
                original = copy.deepcopy(report)
                expected = 1 if report in (COLD_REPORT, LINT_REPORT) else 0
                self.assertEqual(workflow.validate_report(reader, report), expected)
                self.assertEqual(report, original)

    def test_invalid_shapes_enums_and_empty_evidence_are_rejected(self):
        mutations = [
            lambda r: r.update(findings="wrong shape"),
            lambda r: r["findings"][0].update(check="unknown"),
            lambda r: r["findings"][0].update(quote=""),
            lambda r: r["findings"][0]["location"].update(line_end=0),
            lambda r: r["findings"][0]["location"].update(line_start=True),
            lambda r: r.update(clean_checks=["unknown"]),
            lambda r: r.update(clean_checks=[{}]),
            lambda r: r["findings"][0].update(artifact=[]),
            lambda r: r["findings"][0].update(check=[]),
            lambda r: r["findings"][0].update(confidence={}),
        ]
        for mutate in mutations:
            report = copy.deepcopy(LINT_REPORT)
            mutate(report)
            with self.subTest(report=report), self.assertRaises(workflow.ReviewError):
                workflow.validate_report("lint", report)


class LifecycleTests(GitRepositoryTest):
    def test_corrective_retry_preserves_the_reader_prompt_and_is_limited_to_one(self):
        self.prepare("pr-sanity")
        os.environ["FAKE_COLD"] = json.dumps({"narration": ""})
        self.cli("pr-sanity", "launch", "--headless")
        self.assertEqual(self.cli("pr-sanity", "collect", check=False).returncode, 1)
        os.environ["FAKE_COLD"] = json.dumps(COLD_REPORT)
        correction = self.root / "correction.txt"
        correction.write_text(
            "Provide a real narration using your existing observations."
        )
        self.cli(
            "pr-sanity",
            "retry",
            "--reader",
            "cold",
            "--prompt",
            str(correction),
            "--headless",
        )
        collected = json.loads(self.cli("pr-sanity", "collect").stdout)
        self.assertEqual(
            [entry["findings"] for entry in collected["artifacts"]], [1, 1]
        )
        result = self.cli(
            "pr-sanity",
            "retry",
            "--reader",
            "cold",
            "--prompt",
            str(correction),
            "--headless",
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("only one corrective retry", result.stderr.decode())

    def test_sonnet_collection_validates_without_rewriting_or_printing_large_reports(
        self,
    ):
        large_report = copy.deepcopy(COLD_REPORT)
        large_report["narration"] = NARRATION * 1000
        os.environ["FAKE_COLD"] = json.dumps(large_report)
        prepared = self.prepare("pr-sanity")
        self.cli("pr-sanity", "launch", "--headless")
        self.cli("pr-sanity", "wait", "--timeout", "0")
        out = Path(prepared["manifest"]).parent / "out"
        before = (out / "cold.json").read_bytes()
        result = self.cli("pr-sanity", "collect")
        collected = json.loads(result.stdout)
        self.assertEqual((out / "cold.json").read_bytes(), before)
        self.assertNotIn(NARRATION, result.stdout.decode())
        self.assertEqual(
            [entry["findings"] for entry in collected["artifacts"]], [1, 1]
        )
        self.assertEqual(json.loads((out / "cold.json").read_text()), large_report)
        self.assertTrue((out / "usage.json").exists())

    def test_fable_completion_survives_non_json_lines_and_extracts_the_full_original_result(
        self,
    ):
        prepared = self.prepare()
        self.cli("fable-review", "launch", "--headless")
        collected = json.loads(self.cli("fable-review", "collect").stdout)
        artifact = Path(collected["artifacts"][0]["path"])
        self.assertEqual(artifact.read_text(), "## Verdict\nship\n")
        args = json.loads(
            (Path(prepared["manifest"]).parent / "out/invocation.json").read_text()
        )["args"]
        self.assertIn("claude-fable-5-1", args)
        self.assertIn("high", args)
        self.assertIn("--session-id", args)

    def test_error_or_missing_envelope_is_not_collected_as_a_successful_review(self):
        for variable in ("FAKE_ERROR", "FAKE_NO_RESULT"):
            with (
                self.subTest(variable=variable),
                patch.dict(os.environ, {variable: "1"}),
            ):
                self.prepare()
                self.cli("fable-review", "launch", "--headless")
                result = self.cli("fable-review", "collect", check=False)
                self.assertEqual(result.returncode, 1)
                self.assertIn("result envelope", result.stderr.decode())
                self.cli("fable-review", "cleanup")

    def test_timeout_preserves_the_run_and_explicit_abort_stops_the_reviewer(self):
        prepared = self.prepare()
        with patch.dict(os.environ, {"FAKE_SLEEP": "20"}):
            launcher = subprocess.Popen(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--skill",
                    "fable-review",
                    "--repo",
                    str(self.repo),
                    "launch",
                    "--headless",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        self.addCleanup(lambda: launcher.poll() is None and launcher.kill())
        out = Path(prepared["manifest"]).parent / "out"
        deadline = time.monotonic() + 5
        while not (out / "review.pid.json").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((out / "review.pid.json").exists())
        result = self.cli("fable-review", "wait", "--timeout", "0", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(Path(prepared["state"]).exists())
        self.cli("fable-review", "cleanup", "--abort")
        launcher.communicate(timeout=5)
        self.assertFalse((self.repo / ".worktrees/fable-review").exists())

    def test_cmux_launch_and_followup_reuse_the_same_uuid_surface_and_quote_shell_paths(
        self,
    ):
        cmux = self.bin / "cmux"
        cmux.write_text(
            "#!"
            + sys.executable
            + "\n"
            + """
import json, os, pathlib, subprocess, sys
with pathlib.Path(os.environ['CMUX_CALL_LOG']).open('a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if 'new-split' in sys.argv: print('OK 11111111-1111-1111-1111-111111111111')
elif 'send' in sys.argv:
    argv=sys.argv[1:]
    # A shell only evaluates the helper invocation; the prompt is never shell text.
    position=argv.index('--surface')+2
    subprocess.run(argv[position].strip(), shell=True, check=True)
    print('OK')
else: print('OK')
"""
        )
        cmux.chmod(0o755)
        call_log = self.root / "cmux-calls.jsonl"
        with patch.dict(os.environ, {"CMUX_CALL_LOG": str(call_log)}):
            prepared = self.prepare()
            self.cli("fable-review", "launch")
            prompt = self.root / "followup.txt"
            literal = "Explain `literal` and $(literal) without executing them."
            prompt.write_text(literal)
            self.cli("fable-review", "followup", "--prompt", str(prompt))
            invocation = json.loads(
                (Path(prepared["manifest"]).parent / "out/invocation.json").read_text()
            )
            self.assertEqual(invocation["prompt"], literal)
            self.assertIn("--resume", invocation["args"])
            self.cli("fable-review", "cleanup")
        calls = [json.loads(line) for line in call_log.read_text().splitlines()]
        self.assertEqual(sum("new-split" in call for call in calls), 1)
        self.assertEqual(sum("close-surface" in call for call in calls), 1)


class SignoffTests(GitRepositoryTest):
    def test_repeated_signoff_materializes_complete_fixes_and_preserves_primary_index_and_head(
        self,
    ):
        prepared = self.prepare()
        self.cli("fable-review", "launch", "--headless")
        wt = Path(prepared["manifest"]).parents[1]
        self.git("mv", "obsolete.txt", "renamed fix.txt")
        (self.repo / "reader.txt").write_text("staged fix\n")
        self.git("add", "reader.txt")
        (self.repo / "reader.txt").write_text("current unstaged fix\n")
        new_file = "added fix.txt"
        (self.repo / new_file).write_text("untracked fix\n")
        (wt / new_file).write_text("reviewer scratch collision\n")
        (wt / "scratch.txt").write_text("noncolliding scratch\n")
        findings = self.root / "findings.txt"
        findings.write_text("F1: Verify the reader fix.\n")
        index = Path(
            self.git("rev-parse", "--path-format=absolute", "--git-path", "index")
            .stdout.decode()
            .strip()
        )
        before = index.read_bytes()
        self.cli("fable-review", "signoff", "--findings", str(findings), "--headless")
        self.assertEqual((wt / "reader.txt").read_text(), "current unstaged fix\n")
        self.assertEqual((wt / new_file).read_text(), "untracked fix\n")
        self.assertFalse((wt / "obsolete.txt").exists())
        self.assertEqual((wt / "renamed fix.txt").read_text(), "obsolete\n")
        self.assertEqual((wt / "scratch.txt").read_text(), "noncolliding scratch\n")
        self.assertEqual(index.read_bytes(), before)
        self.assertEqual(
            self.git("rev-parse", "HEAD").stdout.decode().strip(), self.head
        )
        self.assertEqual(
            self.git("rev-parse", "HEAD", cwd=wt).stdout.decode().strip(), self.head
        )
        self.cli("fable-review", "collect")
        (self.repo / "reader.txt").write_text("second-round fix\n")
        (self.repo / new_file).unlink()
        self.cli("fable-review", "signoff", "--findings", str(findings), "--headless")
        self.assertEqual((wt / "reader.txt").read_text(), "second-round fix\n")
        self.assertFalse((wt / new_file).exists())
        self.assertEqual(index.read_bytes(), before)
        review = Path(prepared["manifest"]).parent
        self.assertTrue((review / "out/verdict-1.rc").exists())
        self.assertTrue((review / "out/verdict-2.rc").exists())
        self.assertIn("second-round fix", (review / "fixes-2.patch").read_text())
        self.cli("fable-review", "collect")
        self.assertEqual(
            [u["job"] for u in json.loads((review / "out/usage.json").read_text())],
            ["verdict-1", "verdict-2"],
        )

    def test_file_directory_and_symlink_transitions_do_not_write_through_external_links(
        self,
    ):
        outside = self.root / "external"
        outside.mkdir()
        (outside / "preserve.txt").write_text("external content\n")
        link = self.repo / "link"
        link.symlink_to(outside, target_is_directory=True)
        self.git("add", "link")
        self.git("commit", "-qm", "feat: Add link fixture")
        prepared = self.prepare()
        self.cli("fable-review", "launch", "--headless")
        link.unlink()
        link.mkdir()
        (link / "preserve.txt").write_text("fixed content\n")
        findings = self.root / "findings.txt"
        findings.write_text("F1: Verify the link replacement.")
        self.cli("fable-review", "signoff", "--findings", str(findings), "--headless")
        wt = Path(prepared["manifest"]).parents[1]
        self.assertFalse((wt / "link").is_symlink())
        self.assertEqual((wt / "link/preserve.txt").read_text(), "fixed content\n")
        self.assertEqual((outside / "preserve.txt").read_text(), "external content\n")

    def test_moved_primary_head_stops_signoff_before_refreshing_the_review_checkout(
        self,
    ):
        prepared = self.prepare()
        self.cli("fable-review", "launch", "--headless")
        self.git("commit", "--allow-empty", "-qm", "chore: Move head")
        findings = self.root / "findings.txt"
        findings.write_text("F1: Verify the reader fix.")
        result = self.cli(
            "fable-review",
            "signoff",
            "--findings",
            str(findings),
            "--headless",
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("HEAD moved", result.stderr.decode())
        self.assertFalse((Path(prepared["manifest"]).parent / "fixes-1.patch").exists())


if __name__ == "__main__":
    unittest.main()
