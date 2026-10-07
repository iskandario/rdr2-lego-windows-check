# RDR2 + Assassin's Creed Unity: Windows installation check

**Это проверка установок, не игровой кроссовер.** Версия 0.2.0 переключена с LEGO на Assassin's Creed Unity по запросу владельца. Название репозитория сохранено для старых ссылок.

[Скачать актуальный CHECK-WINDOWS.cmd](https://github.com/iskandario/rdr2-lego-windows-check/releases/latest/download/CHECK-WINDOWS.cmd)

Запусти файл на Windows. Если Unity не найдётся, выбери `ACU.exe` в появившемся окне. Пришли JSON из **Рабочий стол → RDR2-UNITY-Reports**. Ничего в игровых папках не изменяется, файлы и отчёт никуда не отправляются.

Подробности и ссылки на исходники загрузчиков — в [README.txt](README.txt). Старая проверка RDR2 + LEGO доступна в [v0.1.1](https://github.com/iskandario/rdr2-lego-windows-check/releases/tag/v0.1.1).

## Исходники первого игрового прототипа

[Dead Eye-inspired режим для Unity](mods/deadeye-unity/README.md): C++-логика замедления с ограниченным запасом и интеграция в закреплённую версию исходников ACUFixes. Локальные тесты логики пройдены. **Windows-DLL ещё не собрана; в игре прототип не проверен.** Это не перенос Артура и не полный кроссовер.

В папке есть исходники, тесты, скрипт Windows-сборки и журнал исследования. Игровые файлы, сторонний загрузчик и извлечённые ресурсы не включены.
