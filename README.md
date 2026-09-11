# 1c-ai-6767

Тестовый каркас для создания среды AI-разработки решений под **1С:Предприятие 8.3**.

Сейчас репозиторий находится на этапе подготовки архитектуры. Прикладная бизнес-задача 1С не реализуется.

## Что уже есть

- Правила работы AI-агентов и Git-процесс.
- Архитектура development loop и контракты проверок.
- BSL static analysis без локальной 1С.
- Минимальный исходник внешней обработки `ToolchainSmoke` без бизнес-логики.
- Локальный EPF build runner с явным `blocked`, если Windows или 1С отсутствуют.
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
├── tests/
│   └── fixtures/                # минимальные файлы для автоматических проверок
├── scripts/
│   ├── bootstrap-cc-1c-skills.ps1
│   ├── build-epf.ps1
│   ├── test.ps1
│   └── test-bsl.ps1
└── reports/
    └── test-summary.json        # короткий результат для AI и CI
```

EPF и логи сборки не хранятся в Git: они создаются только локальным runner и попадают в ignored-пути.

## Development loop

```text
AI agent
  → исходники внешней обработки
  → BSL static analysis
  → EPF build через 1С Designer
  → готовый .epf
  → reports/test-summary.json
```

BSL-анализ выполняется на GitHub-hosted runner. Сборка бинарного `.epf` в этом PR подготовлена как локальный Windows-only шаг и не эмулируется на GitHub без 1С.

## cc-1c-skills и OpenAI Codex

Актуальный репозиторий `cc-1c-skills` публикует отдельные Codex-порты в `.codex/skills/`, а также документирует установку через Codex plugin marketplace. Для этого проекта зафиксирован commit `2c15b32e7f81f87cbdd5dba74964c4b25f5a0056` ветки `port-codex`.

`scripts/bootstrap-cc-1c-skills.ps1` использует официальный `scripts/switch.py` из этого commit и устанавливает PowerShell-версию навыков в `.codex/skills/`. Это подготовка toolchain, а не доказательство наличия платформы 1С.

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
