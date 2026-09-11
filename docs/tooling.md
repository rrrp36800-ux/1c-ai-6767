# Tooling map

Документ разделяет факты текущего репозитория, сведения из доступной документации и рабочие предположения. Команды и версии не считаются утверждёнными, пока не проверены на целевой машине.

## 1. Подтверждено текущими файлами проекта

- `AGENTS.md` требует отдельные ветки, запрет прямых изменений `main`, Pull Request и автоматизированные проверки.
- `AGENTS.md` требует не выдумывать объекты метаданных 1С и проверять неизвестные API.
- `AGENTS.md` требует краткий machine-readable summary, чтобы AI не перечитывал полный лог без необходимости.
- Перенесённая инструкция `docs/AI_1C_tolik_qollanma.md` перечисляет Claude Code, cc-1c-skills, BSL Language Server, Java, Node.js, VS Code, MCP и локальную 1С как части предлагаемого окружения.
- `tests/fixtures/StaticAnalysisSmoke.bsl` — минимальный BSL fixture без прикладной бизнес-логики.
- `scripts/test-bsl.ps1` и `scripts/test.ps1 -BslOnly` реализуют первый автоматический слой анализа.

## 2. Подтверждено официальной документацией и репозиторием BSL Language Server

### BSL Language Server

Официальная документация подтверждает запуск JAR через Java, режим `--analyze`, параметры `--srcDir`, `--reporter` и `--outputDir`, а также JSON reporter, который создаёт `bsl-json.json` в output directory. JSON содержит `fileinfos` и diagnostics с severity `Error`, `Warning`, `Hint` и `Information`.

В этой ветке зафиксирован стабильный релиз `v1.0.7`:

- JAR: `bsl-language-server-1.0.7-exec.jar`;
- официальный URL: <https://github.com/1c-syntax/bsl-language-server/releases/download/v1.0.7/bsl-language-server-1.0.7-exec.jar>;
- SHA-256: `9f62765edd344d66456da24c906eaf623a03c56e90e5aafee466200100909f64`;
- Java: минимально поддерживается 17; в документации также указаны 21 и 23.

Команда, используемая скриптом:

```powershell
java -jar bsl-language-server-1.0.7-exec.jar --analyze --srcDir <source> --reporter json --outputDir <report-directory>
```

Источники:

- <https://github.com/1c-syntax/bsl-language-server>
- <https://github.com/1c-syntax/bsl-language-server/blob/develop/docs/en/index.md>
- <https://github.com/1c-syntax/bsl-language-server/blob/develop/docs/en/reporters/json.md>
- <https://github.com/1c-syntax/bsl-language-server/blob/develop/docs/en/systemRequirements.md>
- <https://github.com/1c-syntax/bsl-language-server/releases/tag/v1.0.7>

### cc-1c-skills

Официальный репозиторий описывает набор навыков для AI-агентов, охватывающий цикл разработки на платформе 1С:Предприятие 8.3, включая работу с конфигурациями, расширениями, внешними обработками, отчётами, тестированием и веб-клиентом.

Источник: <https://github.com/Nikolay-Shirokov/cc-1c-skills>

### YaXUnit

Официальный репозиторий и документация описывают YaXUnit как расширение для запуска тестов 1С и показывают отдельные workflow проекта. Это кандидат для unit/integration слоя, но его установка, версия и способ вызова из этого репозитория ещё не подтверждены.

Источники:

- <https://github.com/bia-technologies/yaxunit>
- <https://bia-technologies.github.io/yaxunit>

### Git и GitHub Actions

Git является базовым механизмом версионирования исходников, веток и Pull Request workflow. GitHub Actions используется в этой ветке только для подтверждённого BSL-шага: GitHub-hosted runner с Temurin Java 21 запускает PowerShell-скрипт, который сам проверяет и при необходимости скачивает зафиксированный JAR.

Источник: <https://docs.github.com/en/actions>

## 3. Предположения, которые всё ещё требуют проверки

- Какая версия 1С:Предприятие 8.3 и какой режим запуска будут использоваться для будущей сборки.
- Где будет находиться тестовая информационная база и как она будет очищаться между прогонами.
- Как устанавливать и вызывать YaXUnit в CI и локально.
- Может ли выбранный runner запускать будущие операции 1С и имеет ли он доступ к лицензии/информационной базе.
- Какие UI/integration tests будут стабильными и какие тестовые данные можно хранить без секретов.

Пока эти пункты не проверены, full pipeline не должен заявлять о прохождении соответствующих проверок.

## 4. Предлагаемый порядок внедрения

1. Зафиксировать версии Windows и 1С на тестовой машине.
2. Подтвердить сборку через локальную 1С.
3. Добавить один unit-test набор YaXUnit.
4. Добавить UI/integration сценарий на изолированной базе.
5. Перенести только подтверждённые команды в full pipeline и GitHub Actions.
6. Проверить, что `reports/test-summary.json` остаётся коротким, детерминированным и полезным для AI.
