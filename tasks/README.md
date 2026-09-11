# Agent tasks

`tasks/` contains handoff documents from the architect to the local Codex runner.

## Create a task

1. Copy `_template.md` to a committed task file, for example `tasks/001-smoke.md`.
2. Keep the seven headings in the exact order shown in the template.
3. State the allowed and forbidden scope explicitly. These sections control the agent's change scope; the runner does not impose a global ban on 1C business logic.
4. In `# Required tests`, list one or more supported scopes as exact Markdown list items:
   - `- BslOnly`
   - `- EpfBuildOnly`
5. List the expected result for each required test.

## Run a task

Run from a clean non-`main` branch:

```powershell
.\scripts\run-agent-task.ps1 -Task tasks\001-smoke.md
```

The runner embeds both `AGENTS.md` and the selected task into the mandatory Codex prompt, invokes the documented non-interactive `codex exec` mode with explicit `gpt-5.6-luna` model selection and `workspace-write` sandboxing, parses only the selected task's `# Required tests` section, and runs the corresponding allowlisted scopes.

The current MVP allowlist is exactly `BslOnly` and `EpfBuildOnly`. The runner never executes PowerShell or shell text from a task file. Missing `# Required tests`, malformed list items, and unknown scopes are `blocked` with a clear message. It reports `passed` only when the agent and every selected scope succeed.

The full `scripts/test.ps1` mode remains unchanged and continues to report unconfigured 1C, unit, and UI/integration checks as `not_run`/`blocked`. The task runner does not convert those checks into PASS.

The runner does not commit, push, merge, create a PR, or configure a GitHub/Notion trigger. It blocks on a dirty working tree, `main`, missing Codex, unsupported CLI flags, or an unavailable Luna model.

## Results and safety

Generated logs and summaries are written under `reports/agent-task/`, which is ignored by Git. The existing generated `reports/test-summary.json` is restored after all selected scope runs so a local runner execution does not turn the baseline report into an accidental commit. Each selected scope is preserved in the machine-readable runner summary.
