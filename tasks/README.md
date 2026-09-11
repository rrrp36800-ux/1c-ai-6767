# Agent tasks

`tasks/` contains handoff documents from an architect to the local Codex runner.

## Minimal workflow

1. Copy `_template.md` to a new task, for example `tasks/001-project-bootstrap.md`.
2. Keep the seven headings in the exact order.
3. Define the scope in `# Allowed changes` and `# Forbidden changes`.
4. List only `- BslOnly` and/or `- EpfBuildOnly` under `# Required tests`.
5. Create a feature branch from `main` and confirm the working tree is clean.
6. Run `scripts/run-agent-task.ps1 -Task tasks\001-project-bootstrap.md`.
7. Read `reports/agent-task/summary.json` and obtain `passed`, `failed`, or `blocked`.

The runner executes the initial agent once. A failed selected scope may receive at most two repair attempts. A blocked result, changed HEAD/branch, invalid task, or unavailable environment does not trigger another model run.

The repair prompt points the agent to existing per-attempt logs, summaries, and current EPF/1C diagnostics. It does not paste giant logs or execute commands from task Markdown.

Generated logs and summaries under `reports/agent-task/` are ignored by Git. The existing `scripts/test.ps1` semantics are preserved; only the selected allowlisted scope mappings are invoked.
