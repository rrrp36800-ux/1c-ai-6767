# Template tooling map

## Local prerequisites

The full workflow requires Windows, 1C:Enterprise 8.3, Windows PowerShell or PowerShell 7, Git, authenticated Codex CLI, and Java 17+. The runner discovers `codex.cmd`, `java`, and `1cv8.exe` through PATH or the existing platform auto-discovery logic; it does not contain user-specific paths.

## Codex runner

The runner uses the documented non-interactive command:

```text
codex exec --model gpt-5.6-luna --sandbox workspace-write --json --output-last-message <file> -
```

The prompt is supplied through UTF-8 stdin. The selected task's `Allowed changes`, `Forbidden changes`, and allowlisted `Required tests` are authoritative. Only `BslOnly` and `EpfBuildOnly` mappings are currently supported.

Windows resolution prefers `codex.cmd` when PowerShell would otherwise resolve `codex.ps1`. Native process stdout/stderr and exit-code handling is used for Git and Java version detection, so successful processes may write warnings to stderr without becoming failures.

## BSL

`test-bsl.ps1` downloads the pinned BSL Language Server when needed, verifies its SHA-256, requires Java 17+, writes JSON diagnostics, and returns `blocked` for missing prerequisites. Java version output is read from both stdout and stderr using the process exit code.

## EPF

`build-epf.ps1` reads `config/epf-build.json`, which is created from `config/epf-build.example.json` by `init-project.ps1`. It invokes the pinned `cc-1c-skills` builder and real `1cv8.exe`; a successful status requires a non-empty output artifact. A Linux GitHub runner cannot honestly perform this step.

## CI and generated files

GitHub Actions runs `scripts/test.ps1 -BslOnly` on Java 21 and uploads BSL reports. Local build output, Codex execution logs, downloaded skills, reports, temporary 1C databases, and other generated files are ignored. `tests/fixtures/StaticAnalysisSmoke.bsl` remains as the minimal neutral BSL fixture required for the automated static-analysis job.
