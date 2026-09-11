# Agent tasks

`tasks/` contains handoff documents from the architect to the local Codex runner.

## Create a task

1. Copy `_template.md` to a committed task file, for example `tasks/001-smoke.md`.
2. Keep the seven headings in the exact order shown in the template.
3. State the allowed and forbidden scope explicitly.
4. List the exact tests required for acceptance.

## Run a task

Run from a clean non-`main` branch:

```powershell
.\scripts\run-agent-task.ps1 -Task tasks\001-smoke.md
```

The runner embeds both `AGENTS.md` and the selected task into the mandatory Codex prompt, invokes the documented non-interactive `codex exec` mode with explicit `gpt-5.6-luna` model selection and `workspace-write` sandboxing, then runs the two configured test scopes: `scripts/test.ps1 -BslOnly` and `scripts/test.ps1 -EpfBuildOnly`.

The full `scripts/test.ps1` mode remains unchanged and continues to report unconfigured 1C, unit, and UI/integration checks as `not_run`/`blocked`. The task runner does not convert those checks into PASS; it aggregates only the BSL and EPF scopes that are currently configured for this MVP.

The runner does not commit, push, merge, create a PR, or configure a GitHub/Notion trigger. It blocks on a dirty working tree, `main`, missing Codex, unsupported CLI flags, or an unavailable Luna model. It reports `passed` only when the agent and both configured scopes succeed.

## Results and safety

Generated logs and summaries are written under `reports/agent-task/`, which is ignored by Git. The existing generated `reports/test-summary.json` is restored after both scoped test runs so a local runner execution does not turn the baseline report into an accidental commit.
