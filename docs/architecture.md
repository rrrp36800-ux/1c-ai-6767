# Архитектура development loop

## Цель

Этот документ описывает каркас разработки решений 1С:Предприятие 8.3 через AI-агентов. В текущем PR прикладная бизнес-логика не добавляется: `src/` содержит только минимальный исходник внешней обработки для проверки toolchain.

## Основной цикл

```text
AI agent
  → изменение исходников
  → статический анализ BSL
  → сборка внешней обработки через 1С Designer
  → готовый .epf
  → краткий machine-readable report
```

### 1. AI agent

Агент читает `AGENTS.md`, задачу и текущий `reports/test-summary.json`, затем предлагает минимальное изменение. Агент не должен считать задачу завершённой по одному только виду файлов.

### 2. Исходники внешней обработки

`src/ToolchainSmoke.xml` и `src/ToolchainSmoke/Ext/ObjectModule.bsl` — минимальный scaffold внешней обработки без бизнес-логики. XML-структура подготовлена по формату, который использует `cc-1c-skills` `epf-init`. Этот PR не добавляет формы, реквизиты, макеты или прикладные процедуры.

### 3. Статический анализ BSL

Существующий BSL слой запускается отдельно и не требует 1С. Он проверяет доступный fixture и формирует JSON report. Этот слой не создаёт `.epf`.

### 4. Сборка EPF

Подтверждённый путь сборки:

```text
XML + BSL sources
  → cc-1c-skills epf-build.ps1
  → 1cv8.exe DESIGNER /F <file infobase>
    /LoadExternalDataProcessorOrReportFromFiles <root XML> <output EPF>
  → non-empty .epf
```

`scripts/build-epf.ps1` вызывает официальный Codex-порт `epf-build.ps1` из зафиксированного `cc-1c-skills` commit. Скрипт проверяет исходники, наличие Windows и `1cv8.exe`, удаляет старый output перед запуском и требует непустой output после кода `0`.

Без Windows и установленной 1С платформа не может выполнить этот шаг. GitHub-hosted runner в текущем workflow используется только для BSL; сборка `.epf` не имитируется и не называется успешной.

### 5. Краткий отчёт

`reports/test-summary.json` — первый файл, который должен читать AI. Полные логи и подробные отчёты открываются только при необходимости.

Схема summary:

```json
{
  "schemaVersion": 1,
  "scope": "bsl-static-analysis | epf-build-toolchain | full-pipeline | bootstrap",
  "status": "not_run | blocked | passed | failed",
  "generatedAt": "ISO-8601 timestamp",
  "generatedBy": "producer name",
  "reason": "optional short explanation",
  "checks": [
    {
      "name": "check-name",
      "status": "not_run | blocked | passed | failed",
      "details": "short explanation",
      "report": "optional/path/to/report",
      "log": "optional/path/to/log"
    }
  ],
  "logFiles": [],
  "nextAction": "short actionable hint"
}
```

Статусы `passed` и `failed` допустимы только после реального запуска соответствующей проверки. Отсутствие зависимости или ненастроенной команды означает `blocked`, а ещё не запускавшаяся проверка — `not_run`.

### Exit codes для CI и локального runner

- `0` — все проверки выбранного scope завершились успешно;
- `1` — проверка запускалась, но обнаружена ошибка или отсутствует ожидаемый артефакт;
- `2` — проверка заблокирована окружением или ещё не настроена.

`./scripts/test.ps1 -BslOnly` запускает только BSL. `./scripts/test.ps1 -EpfBuildOnly` запускает только локальный EPF toolchain. Обычный `./scripts/test.ps1` запускает доступные BSL и EPF scopes, поэтому без 1С его общий результат остаётся `blocked`.

## Границы ответственности

- **AI/GitHub:** создают исходники, конфигурацию, скрипты, BSL report и историю изменений.
- **cc-1c-skills:** предоставляет подтверждённые XML/PowerShell-абстракции, включая `epf-init` и `epf-build`.
- **Локальная 1С:** выполняет Designer и создаёт бинарный `.epf`.
- **CI:** проверяет BSL и не выдаёт EPF PASS без реального Windows runner с 1С.

## Что намеренно не сделано

- нет бизнес-логики;
- нет форм, реквизитов и макетов;
- нет утверждения, что `.epf` собран;
- нет эмуляции 1С на GitHub-hosted runner;
- нет YaXUnit и UI/integration tests.

Следующий шаг после проверки на Windows — выполнить локальный EPF build и сохранить фактический результат/ограничения в summary, не подменяя его предположением.
