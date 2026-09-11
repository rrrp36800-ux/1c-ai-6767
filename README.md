# Reusable AI + 1C project template

This repository is a reusable starting point for AI-assisted 1C:Enterprise 8.3 projects. It provides the common infrastructure for:

- scoped architect tasks;
- Codex CLI / GPT-5.6 Luna execution;
- BSL Language Server analysis;
- local EPF build through the pinned `cc-1c-skills` toolchain;
- bounded repair (initial run plus at most two repair attempts);
- machine-readable PASS / FAIL / BLOCKED results;
- GitHub Actions for the platform-independent BSL check.

It intentionally contains no business domain, metadata object, form, or EPF fixture. Each project created from this template supplies its own 1C sources and EPF configuration.

## Prerequisites

For the full local workflow, install:

- Windows;
- 1C:Enterprise 8.3 with an available `1cv8.exe`;
- Codex CLI authenticated for the target account and able to run `codex exec`;
- Java 17 or newer for BSL Language Server;
- Git;
- Windows PowerShell or PowerShell 7;
- network access for the pinned BSL/toolchain downloads when caches are absent.

Codex authentication is performed by the normal Codex CLI login flow on the target machine. The runner does not store credentials or modify PowerShell ExecutionPolicy. On Windows it prefers `codex.cmd` discovered through `PATH`, then a native `codex` executable.

## Initialize a project created from this template

After creating a repository from this template:

```powershell
# Create a project branch; never work directly on main.
git switch -c feat/project-bootstrap

# Configure the project's EPF source and output paths.
.\scripts\init-project.ps1 `
  -ProjectName didox-automation `
  -EpfSourcePath src\didox-automation.xml `
  -EpfOutputPath build\didox-automation.epf
```

The initialization script creates `config/epf-build.json` from the tracked example and refuses to overwrite an existing configuration unless `-Force` is explicitly supplied. It does not create 1C metadata or business logic.

Add the project's XML/BSL sources, then create a task:

```powershell
Copy-Item tasks\_template.md tasks\001-project-bootstrap.md
```

Fill the seven required sections. In `# Required tests`, use only:

```text
- BslOnly
- EpfBuildOnly
```

## Run the task workflow

```text
create task
  → create feature branch
  → run scripts/run-agent-task.ps1
  → Codex / GPT-5.6 Luna changes the project
  → selected tests run
  → failed tests may receive up to two bounded repairs
  → PASS / FAIL / BLOCKED
```

Run from a clean non-`main` branch:

```powershell
.\scripts\run-agent-task.ps1 -Task tasks\001-project-bootstrap.md
```

The runner preserves clean-tree, branch, HEAD, main, push, and no-commit protections. It parses only the task's `# Required tests` section and never executes arbitrary commands from Markdown. `blocked` results do not start another model run. Failed selected scopes provide their existing log, summary, and EPF diagnostics to the repair prompt.

## Statuses

- `passed` — the agent and every selected scope completed successfully;
- `failed` — the agent or a selected check ran and reported a real failure;
- `blocked` — a required environment or dependency was unavailable, or the task/scope was invalid;
- `not_run` — a check was not selected or has not been executed.

## Checks and boundaries

GitHub-hosted CI runs `scripts/test.ps1 -BslOnly` with Java 21 and uploads BSL reports. It does not emulate 1C or claim an EPF build.

The local `EpfBuildOnly` scope requires Windows, PowerShell, `1cv8.exe`, the configured source XML, and the pinned `cc-1c-skills` builder. It creates a non-empty `.epf` only when the real Designer process succeeds.

Generated reports, build output, Codex logs, downloaded skills, temporary 1C databases, and local artifacts are ignored by Git. Read `tasks/README.md`, `docs/architecture.md`, and `docs/tooling.md` for the detailed contracts.
