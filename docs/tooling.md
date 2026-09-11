# Tooling map

Документ разделяет факты текущего репозитория, сведения из первичных источников и ограничения, которые ещё требуют проверки на Windows-машине с 1С.

## 1. Подтверждено текущим проектом

- `AGENTS.md` требует отдельные ветки, Pull Request и честные автоматизированные проверки.
- BSL Language Server уже запускается отдельно от 1С.
- `config/epf-build.json` фиксирует исходник, output path и commit toolchain.
- `scripts/bootstrap-cc-1c-skills.ps1` устанавливает Codex-порт навыков из pinned commit.
- `scripts/build-epf.ps1` возвращает `blocked`, если Windows или `1cv8.exe` недоступны, и не считает код `0` достаточным без непустого `.epf`.

## 2. cc-1c-skills и OpenAI Codex

Официальный README репозитория `cc-1c-skills` прямо перечисляет OpenAI Codex как поддерживаемую платформу:

- готовая раскладка: `.codex/skills/`;
- готовые ветки: `port-codex` и `port-codex-py`;
- plugin marketplace: `codex plugin marketplace add Nikolay-Shirokov/cc-1c-skills`, затем установка через `/plugins`;
- локальная установка: официальный `scripts/switch.py codex --project-dir ...`.

Для этого PR используется PowerShell-вариант, потому что подтверждённый `epf-build` skill запускает `powershell.exe` и `1cv8.exe`. Зафиксирован commit `2c15b32e7f81f87cbdd5dba74964c4b25f5a0056`, из которого bootstrap вызывает `switch.py` и получает `.codex/skills/epf-build`.

Подтверждённые команды навыков:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".codex/skills/epf-init/scripts/init.ps1" -Name "ToolchainSmoke" -SrcDir "src"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".codex/skills/epf-build/scripts/epf-build.ps1" -SourceFile "src/ToolchainSmoke.xml" -OutputFile "build/ToolchainSmoke.epf"
```

`epf-init` создаёт XML scaffold и `ObjectModule.bsl`; `epf-build` требует платформу 1С и проверяет непустой output. В этой ветке исходник зафиксирован в Git, а bootstrap нужен для воспроизводимого получения build script.

Источники:

- <https://github.com/Nikolay-Shirokov/cc-1c-skills>
- <https://github.com/Nikolay-Shirokov/cc-1c-skills/tree/port-codex>
- <https://github.com/Nikolay-Shirokov/cc-1c-skills/blob/port-codex/.codex/skills/epf-init/SKILL.md>
- <https://github.com/Nikolay-Shirokov/cc-1c-skills/blob/port-codex/.codex/skills/epf-build/SKILL.md>

## 3. Официальный toolchain 1С для EPF

Официальная документация 1С описывает внешние обработки как отдельные файлы `.epf`. Для пакетного режима Designer официально предусмотрены операции:

- `/DumpExternalDataProcessorOrReportToFiles` — выгрузка бинарной внешней обработки/отчёта в XML-файлы;
- `/LoadExternalDataProcessorOrReportFromFiles` — загрузка XML-исходников во внешний `.epf`/`.erf`.

Используемый skill формирует вызов в режиме `DESIGNER` с файловой информационной базой и командой:

```text
1cv8.exe DESIGNER /F <info-base> /LoadExternalDataProcessorOrReportFromFiles <root-xml> <output-epf>
```

Этот синтаксис зафиксирован в исходнике `cc-1c-skills` и сопоставлен с разделом официальной документации 1С о пакетных командах внешних обработок. Параметры не расширяются непроверенными ключами.

Источники:

- <https://v8.1c.ru/platforma/vneshnie-obrabotki>
- <https://its.1c.ru/db/v838doc/bookmark/adm/TI000000493>
- <https://its.1c.ru/db/v8315doc/bookmark/adm/TI000000493>
- <https://1c-dn.com/library/v8update_461169075_new_functionality_and_changes/>

## 4. Что можно и нельзя сделать через GitHub

Можно сделать на GitHub:

- хранить и проверять XML/BSL-исходники;
- установить Codex-совместимые skills в проекте;
- запускать BSL static analysis;
- подготовить конфигурацию и локальный runner;
- review и версионирование.

Нельзя честно заявить без платформы 1С:

- выполненный `1cv8.exe DESIGNER`;
- платформенную проверку/компиляцию модулей внешней обработки;
- созданный бинарный `.epf`.

Подготовленный runner требует Windows, Windows PowerShell и установленную 1С:Предприятие 8.3. При отсутствии любого обязательного компонента он возвращает `blocked`.

## 5. Непроверенные ограничения

- точная версия 1С:Предприятие 8.3 на целевом Windows ПК;
- лицензирование и доступность Designer в headless-режиме;
- совместимость формата `2.17` с фактической версией платформы;
- успешный build конкретного fixture на целевой машине;
- последующая проверка готового `.epf` в режиме 1С:Предприятие.

## 6. Порядок проверки на Windows

1. Установить 1С:Предприятие 8.3 и убедиться, что доступен `1cv8.exe`.
2. Запустить `scripts/bootstrap-cc-1c-skills.ps1`.
3. Запустить `scripts/test.ps1 -EpfBuildOnly`.
4. Прочитать `reports/test-summary.json`.
5. При `passed` проверить существование и открытие `build/ToolchainSmoke.epf` в 1С.
6. Зафиксировать фактическую версию платформы и результат в следующем изменении; до этого GitHub PR не называет EPF собранным.
