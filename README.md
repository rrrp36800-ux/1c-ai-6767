# 1c-ai-6767

Тестовый каркас для создания среды AI-разработки решений под **1С:Предприятие 8.3**.

Сейчас репозиторий находится на этапе подготовки архитектуры. Прикладная бизнес-задача 1С не реализуется.

## Что уже есть

- Правила работы AI-агентов и Git-процесс.
- Архитектура development loop и контракты проверок.
- BSL static analysis без локальной 1С.
- Минимальный исходник внешней обработки `ToolchainSmoke` без бизнес-логики.
- Локальный EPF build runner с явным `blocked`, если Windows или 1С отсутствуют.
- Архитекторский handoff через `tasks/<task>.md` и guarded local Codex runner.
- Machine-readable summary и GitHub Actions для доступного BSL-слоя.

## Архитектура репозитория

```text
/
├── AGENTS.md
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── bsl-static-analysis.yml
├── config/
│   └── epf-build.json           # конфигурация локальной сборки EPF
├── docs/
│   ├── AI_1C_tolik_qollanma.md
│   ├── architecture.md
│   └── tooling.md
├── src/
│   ├── ToolchainSmoke.xml       # корневой XML внешней обработки
│   └── ToolchainSmoke/
│       └── Ext/ObjectModule.bsl # пустой модуль без бизнес-логики
├── tasks/
│   ├── _template.md             # строгая структура handoff-задачи
│   └── README.md
├── tests/
│   └── fixtures/                # минимальные файлы для автоматических проверок
├── scripts/
│   ├── bootstrap-cc-1c-skills.ps1
│   ├── build-epf.ps1
│   ├── run-agent-task.ps1
│   ├── test.ps1
│   └── test-bsl.ps1
└── reports/
    └── test-summary.json        # baseline; локальные результаты игнорируются
```

EPF, Codex task-runner logs and local reports are not stored in Git. They are written to ignored paths.

## Development loop

```text
architect task: tasks/<task>.md
  → guarded local runner
  → Codex CLI / explicit gpt-5.6-luna
  → project changes
  → scripts/test.ps1 -BslOnly + -EpfBuildOnly
  → PASS / FAIL / BLOCKED
```

The runner is local only. It does not merge, push, commit, create a PR, add a GitHub self-hosted runner, or configure a Notion trigger.

## Local agent task runner

Run from a clean non-`main` branch:

```powershell
.\scripts\run-agent-task.ps1 -Task tasks\001-smoke.md
```

The runner requires a task with the exact seven headings from `tasks/_template.md`, a clean Git working tree, the current branch not to be `main`, and an installed Codex CLI exposing `codex exec --model`, `--sandbox`, `--json`, and `--output-last-message`. The task path is canonicalized and must resolve inside the repository with a directory boundary, not a raw prefix match.

Before Codex, the runner records the current branch and commit SHA. After Codex, it verifies both are unchanged; if Codex commits or switches branches, the runner returns `failed` and does not run tests or rewrite history.

The documented non-interactive invocation is:

```text
codex exec --model gpt-5.6-luna --sandbox workspace-write --json --output-last-message <file> -
```

The final `-` takes the complete mandatory prompt from stdin. The prompt contains `AGENTS.md` and the selected task. `workspace-write` is the least documented sandbox mode that permits project edits; the runner additionally disables the child's Git push URL and never calls merge or push itself.

After the agent, the runner invokes only the configured MVP scopes:

```powershell
.\scripts\test.ps1 -BslOnly
.\scripts\test.ps1 -EpfBuildOnly
```

The full `scripts/test.ps1` command remains unchanged and keeps unconfigured 1C, YaXUnit, and UI/integration checks as `not_run`/`blocked`. The runner does not claim PASS for those unavailable checks. `gpt-5.6-luna` is selected explicitly, not assumed as a default. If the installed CLI lacks the model flag or the backend rejects Luna, the result is `blocked`, never a fake success.

The current development sandbox did not have a `codex` executable when this runner was prepared. Therefore the runner was not executed here and no project change or test PASS is claimed for this local prototype.

## EPF build toolchain

Конфигурация: `config/epf-build.json`.

Локальный запуск:

```powershell
./scripts/test.ps1 -EpfBuildOnly
```

или напрямую:

```powershell
./scripts/build-epf.ps1
```

Runner вызывает подтверждённый `cc-1c-skills` `epf-build.ps1`, который использует пакетный режим `1cv8.exe DESIGNER` и `/LoadExternalDataProcessorOrReportFromFiles`. Успешный статус выдаётся только если команда завершилась с кодом `0` и создала непустой `build/ToolchainSmoke.epf`.

Если отсутствуют Windows, `powershell.exe`, `1cv8.exe` или локально устанавливаемый toolchain, результатом будет `blocked`, а не fake PASS. Результаты и полный лог: `reports/epf-build-result.json` и `reports/epf-build.log`.

## Границы GitHub и локального runner

Можно подготовить через GitHub:

- XML/BSL-исходники внешней обработки;
- конфигурацию и PowerShell runner;
- BSL static analysis;
- review и историю изменений.

Требует Windows + установленной 1С:Предприятие 8.3:

- запуск `1cv8.exe DESIGNER`;
- проверка исходников платформой;
- создание бинарного `.epf`;
- проверка полученного файла в 1С.

GitHub Actions этого PR не заявляет сборку `.epf`.

## Статусы и ограничения

- `passed` — команда реально выполнилась и артефакт создан;
- `failed` — toolchain запускался, но завершился ошибкой или не создал артефакт;
- `blocked` — отсутствует обязательная среда или зависимость;
- `not_run` — проверка ещё не запускалась.

Локальная 1С, сборка `.epf`, YaXUnit и UI/integration tests не выполнялись в GitHub Actions этого проекта.
