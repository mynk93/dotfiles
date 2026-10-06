# Reading review files

Run the helper to validate reports and get their paths. Then use the Read tool on the original files before judging the findings.

1. Read each returned artifact path directly. For JSON, retain narration, observations, quotes, classifications, and coverage fields. For Markdown, retain the full verdict and every finding.
2. If the file exceeds the tool's response limit, read line ranges with `offset` and `limit`, advancing to the next unread line until the reported file length is covered. Reduce the range when a response is truncated. A preview, omitted range, or truncated line is incomplete evidence.
3. If a command response says its output was persisted, use that returned file path instead of rerunning the command. If it identifies an original artifact path, prefer that original file. Neither requires another transformation.
4. Preserve original reports. Parsing, compact reserialization, quote clipping, and generated summary scripts are not collection steps. Semantic merging happens after the main agent has read the evidence.

For an unusually long single line that even a one-line read truncates, use the helper's bounded character reader, advancing `--offset` to each response's `character_end` until it equals `total_characters`:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity read --path /absolute/path/to/report.json --offset 0
```

It returns consecutive original text, not a parsed or summarized replacement. Choose the current skill; normal multiline artifacts should use Read ranges.

The helper emits artifact sizes and line counts to make completeness observable. It records token/cost counters separately in `.review/out/usage.json`; these are diagnostics, not subscription-limit calculations. Reader prompts and their output contracts remain the source of truth for review content.

## Lifecycle diagnostics

Each run stores `.review/state.json` with repo/worktree paths, the pinned session ID, job names, prompt paths, and UUID pane handles. Commands recover those handles from disk; shell variables need not persist between calls. Helper CLI details are available through `python3 ~/.claude/scripts/review_workflow.py --help` and each subcommand's `--help`.

For job `<name>`, `.review/out/` contains `<name>.jsonl`, `<name>.err.log`, `<name>.pid.json`, and `<name>.rc`. The helper records raw output before printing text in the pane and skips malformed display records. `<name>.rc` means the process exited, including an error. Collection checks for a zero exit and a successful final CLI result before validating or extracting reports.

On a timeout, check raw log growth and stderr before restarting the waiter or aborting. The timeout does not kill a reviewer. Read relevant log ranges rather than bringing the full raw transcript into the main context. With cmux, refresh surfaces before reading a screen and use the persisted workspace and surface UUIDs. Authentication or trust prompts require the user to resolve them; do not approve them through automation.

For explicit aborts, `cleanup --abort` terminates reviewer process groups and waits for completion before removing files. Stop the separate background waiter as well. If a failed launch never started a process, inspect its persisted state before recovery; do not launch another initial reviewer over an uncertain live run. Preparation preserves existing worktrees to avoid destroying unfinished evidence.
