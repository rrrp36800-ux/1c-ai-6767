# Reusable AI + 1C template architecture

## Purpose

This repository supplies the repeatable control plane for future 1C projects. Domain metadata, forms, modules, and business rules belong to the project created from the template, not to this repository.

## Development loop

```text
scoped task
  → guarded local Codex / GPT-5.6 Luna run
  → selected BSL and/or EPF checks
  → failed diagnostics returned to a bounded repair run
  → PASS / FAIL / BLOCKED
```

The runner performs one initial run and at most two repair attempts. It never commits, pushes, merges, changes branch, or runs on `main`. It retries only a real `failed` selected test; `blocked` is an environment or contract result and stops the loop.

## Toolchain boundaries

- `scripts/test-bsl.ps1` runs BSL Language Server with Java 17+ and does not require 1C.
- `scripts/build-epf.ps1` runs the pinned `cc-1c-skills` EPF builder and real `1cv8.exe` on Windows.
- `scripts/test.ps1` preserves the existing BSL and EPF scope semantics.
- `.github/workflows/bsl-static-analysis.yml` verifies only the platform-independent BSL layer.
- EPF build is intentionally local and returns `blocked` when Windows, 1C, or the builder is unavailable.

## Project initialization

`config/epf-build.example.json` is the tracked generic configuration. `scripts/init-project.ps1` safely creates the untracked `config/epf-build.json` with `ProjectName`, `sourceFile`, and `outputFile`; it refuses to overwrite an existing file without `-Force`. No build script change is needed for a new project.

## Diagnostics contract

The runner writes a machine-readable summary under `reports/agent-task/`. It includes only paths that exist. EPF attempts compare the pre-run and post-run `%TEMP%\stub_load_log.txt` fingerprint and copy a changed current log into the ignored report directory. This makes complete platform diagnostics available to a repair agent without treating stale temp files as current failures.

## Responsibilities

- Architect: define a task and explicit Allowed/Forbidden scope.
- Codex/Luna: make the minimum permitted project changes.
- Runner: enforce safety, invoke fixed scopes, aggregate status, and bound repair.
- BSL/1C toolchain: validate the resulting project.
- GitHub: run BSL CI and review the Pull Request.
