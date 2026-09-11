# 1c-ai-6767

Тестовый каркас для создания среды AI-разработки решений под **1С:Предприятие 8.3**.

Сейчас репозиторий находится на этапе подготовки архитектуры. Прикладное решение 1С, бизнес-логику, обработки, справочники и документы пока не добавляем.

## Что уже есть

- `AGENTS.md` — правила работы AI-агентов и Git-процесс.
- `docs/AI_1C_tolik_qollanma.md` — исходная инструкция по подготовке окружения.
- `docs/architecture.md` — development loop и контракты проверок.
- `docs/tooling.md` — карта инструментов, подтверждённых фактов и предположений.
- `scripts/test.ps1` — единая точка запуска полного pipeline и BSL-only scope.
- `scripts/test-bsl.ps1` — воспроизводимый запуск BSL Language Server.
- `tests/fixtures/StaticAnalysisSmoke.bsl` — минимальный BSL fixture без бизнес-логики.
- `reports/test-summary.json` — краткий machine-readable результат текущего состояния.
- `.github/workflows/bsl-static-analysis.yml` — GitHub Actions для BSL-проверки.

## Архитектура репозитория

```text
/
├── AGENTS.md
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── bsl-static-analysis.yml
├── docs/
│   ├── AI_1C_tolik_qollanma.md
│   ├── architecture.md
│   └── tooling.md
├── src/                         # будущие исходники конфигурации/расширений/обработок
├── tests/
│   └── fixtures/                # минимальные файлы для автоматических проверок
├── scripts/
│   ├── test.ps1                 # общий pipeline
│   └── test-bsl.ps1             # BSL-only слой
└── reports/
    └── test-summary.json        # короткий результат для AI и CI
```

Папка `src/` пока не содержит прикладного решения. `tests/fixtures/StaticAnalysisSmoke.bsl` нужен только для проверки toolchain статического анализа.

## Предполагаемый development loop

```text
AI agent
  → изменение исходников
  → статический анализ BSL
  → сборка
  → unit tests
  → UI/integration tests
  → reports/test-summary.json
```

Первый реально работающий слой — `BSL source → BSL Language Server → JSON report → GitHub Actions → test-summary`. Подробное описание находится в [`docs/architecture.md`](docs/architecture.md).

## Инструменты

- **BSL Language Server 1.0.7** — первый включённый автоматический слой анализа `.bsl` без локальной 1С.
- **Java 21** — версия Temurin, используемая GitHub Actions; официальная документация BSL Language Server также указывает Java 17 и 23 как поддерживаемые версии.
- **cc-1c-skills** — кандидат для будущих AI-операций с форматами и инструментами 1С.
- **YaXUnit** — кандидат для будущих автоматизированных тестов 1С.
- **Git** — ветки, коммиты и воспроизводимая история изменений.
- **GitHub Actions** — запуск BSL-проверки на GitHub-hosted runner.
- **Локальная 1С:Предприятие 8.3** — всё ещё необходима для будущей сборки и runtime-сценариев.

Команда BSL Language Server подтверждена официальной документацией и зафиксирована вместе с SHA-256 JAR в [`docs/tooling.md`](docs/tooling.md).

## Запуск проверок

Первый доступный scope:

```powershell
./scripts/test.ps1 -BslOnly
```

Прямой запуск BSL-слоя:

```powershell
./scripts/test-bsl.ps1
```

Скрипт скачивает только зафиксированный `bsl-language-server-1.0.7-exec.jar`, проверяет SHA-256, запускает JSON reporter и сохраняет:

- краткий результат — `reports/test-summary.json`;
- полный лог — `reports/bsl-language-server.log`;
- полный JSON-анализ — `reports/bsl/bsl-json.json`.

Контракт exit codes:

- `0` — все проверки в выбранном scope реально завершились успешно;
- `1` — ошибка структуры, запуска или анализа;
- `2` — проверка заблокирована окружением или ещё не настроена.

`./scripts/test.ps1 -BslOnly` используется GitHub Actions и возвращает `0`, когда BSL-анализ завершён без диагностик severity `Error`. Обычный `./scripts/test.ps1` дополнительно включает будущие 1С build, unit и UI/integration checks; пока они не настроены, его общий результат остаётся `blocked`.

## Локальные требования

Для BSL-only слоя требуется:

- PowerShell;
- Java 17 или новее;
- доступ к GitHub Releases для загрузки зафиксированного JAR.

Для полноценного цикла дополнительно потребуется локально подтвердить наличие:

- Windows и PowerShell;
- 1С:Предприятие 8.3 для операций, требующих runtime/конфигуратора;
- Git и доступ к GitHub;
- выбранных версий cc-1c-skills и YaXUnit;
- тестовой информационной базы и UI/integration runner.

Наличие локальной 1С, сборка `.epf`, YaXUnit и UI/integration tests в этой задаче не проверялись.

## Правила работы

- `main` напрямую не изменять: каждая задача выполняется в отдельной ветке и через Pull Request.
- Не выдумывать объекты метаданных 1С и неизвестные API.
- После добавления BSL-кода запускать подтверждённый статический анализ.
- Не считать задачу выполненной только по виду файлов.
- AI сначала читает краткий `reports/test-summary.json`, а полный JSON и лог — только при необходимости.
