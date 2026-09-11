# 1c-ai-6767

Тестовый каркас для создания среды AI-разработки решений под **1С:Предприятие 8.3**.

Сейчас репозиторий находится на этапе подготовки архитектуры. Прикладное решение 1С и бизнес-логика пока не добавляются.

## Что уже есть

- Правила работы AI-агентов и Git-процесс.
- Архитектура development loop и контракты проверок.
- Карта инструментов с разделением подтверждённых фактов и предположений.
- PowerShell pipeline с отдельным BSL-only scope.
- Минимальный BSL fixture без бизнес-логики.
- Machine-readable summary и GitHub Actions для BSL-проверки.

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

`src/` пока не содержит прикладного решения, а fixture в `tests/fixtures/` нужен только для проверки toolchain статического анализа.

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

Первый реально работающий слой: `BSL source → BSL Language Server → JSON report → GitHub Actions → test-summary`. Подробные границы этапов описаны в [`docs/architecture.md`](docs/architecture.md).

## Инструменты

- **BSL Language Server 1.0.7** — анализ `.bsl` без локальной 1С.
- **Java 21** — Temurin в GitHub Actions; BSL Language Server официально поддерживает Java 17, 21 и 23.
- **cc-1c-skills** — кандидат для будущих AI-операций с форматами и инструментами 1С.
- **YaXUnit** — кандидат для будущих автоматизированных тестов 1С.
- **Git** — ветки, коммиты и воспроизводимая история изменений.
- **GitHub Actions** — запуск BSL-проверки на GitHub-hosted runner.
- **Локальная 1С:Предприятие 8.3** — требуется для будущей сборки и runtime-сценариев.

Команда BSL Language Server и SHA-256 JAR зафиксированы в [`docs/tooling.md`](docs/tooling.md).

## Запуск проверок

BSL-only scope:

```powershell
./scripts/test.ps1 -BslOnly
```

Прямой запуск BSL-слоя:

```powershell
./scripts/test-bsl.ps1
```

Скрипт скачивает зафиксированный JAR, проверяет SHA-256, запускает JSON reporter и сохраняет краткий summary, полный лог и полный JSON-отчёт.

Контракт exit codes:

- `0` — все проверки выбранного scope реально завершились успешно;
- `1` — ошибка структуры, запуска или анализа;
- `2` — проверка заблокирована окружением или ещё не настроена.

`-BslOnly` возвращает `0` только после фактического BSL-анализа без диагностик severity `Error`. Обычный `./scripts/test.ps1` также включает будущие 1С build, unit и UI/integration checks; пока они не настроены, его общий результат остаётся `blocked`.

## Локальные требования

Для BSL-only слоя требуются PowerShell, Java 17 или новее и доступ к GitHub Releases. Полный цикл дополнительно потребует локальную 1С, тестовую информационную базу и подтверждённые YaXUnit и UI/integration runners.

Локальная 1С, сборка `.epf`, YaXUnit и UI/integration tests в этой задаче не проверялись.

## Правила работы

- `main` напрямую не изменять: каждая задача выполняется в отдельной ветке и через Pull Request.
- Не выдумывать объекты метаданных 1С и неизвестные API.
- После добавления BSL-кода запускать подтверждённый статический анализ.
- Не считать задачу выполненной только по виду файлов.
- AI сначала читает краткий summary, а полный JSON и лог — только при необходимости.
