# Проверка передачи исходников — 23 октября 2026

Публикация накопленного кода, исследований и developer handoff. Нового бинарного релиза нет; игра в рамках этой передачи не запускалась.

| Проверка | Результат |
| --- | --- |
| Python/Lupa unittest discover | 690 tests, OK, skipped=1. Пропущен отдельный Connection Test DLL без AC8_CONNECTION_NATIVE_TEST_DLL. |
| Build-LifecycleLab | MSVC x64 /W4 /WX; 382 shared-session + 114 mission + 177 cinema + 169 policy checks; DLL собрана. |
| Build-MissionPause -Check -DisconnectLab | 7 ownership + 6 disconnect + 17 bootstrap checks; DLL собрана. |
| Build-SteamCoop -Revision r31 | Все включённые C++ проверки и сборка bridge/owner_lab_peer прошли. Контракты самолёта проверяются на моделях, не игровой физикой. |
| lifecycle_lab.py test | 8 сценариев PASS с настоящей native TCP DLL; gameplay_tested=false. |
| Подготовка профиля | Из официального UE4SS и собранных DLL создан новый build/handoff-check/profile. Приватный runtime предыдущего опыта не нужен. |
| Start-LifecyclePair preflight | PASS с -HeadlessGuest -StopOnDisconnect -ProfileRoot; без -Launch. |
| PowerShell parser | Prepare-LifecycleStop и Start-LifecyclePair без ошибок. |
| Локальные ссылки | README, HANDOFF, DEVELOPMENT: нет отсутствующих целей. |
| Universal-modder publish lint | Исходный срез до добавления этого отчёта: 593 файла, 0 FAIL, 12 WARN о локальных путях. Проверялся против оригинальной установки на совпадение файлов. |
| Оригинальный EXE | SHA256 51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f; совпадает. Полный побайтовый аудит всей установки не выполнялся. |

Первый запуск unittest в ограниченном окружении дал ошибки доступа к временным каталогам. Повтор вне ограничения завершился OK. Это не скрытое исправление игрового кода и не игровая приёмка.

Предупреждения lint разобраны: локальные пути в отчётах обозначают происхождение доказательств; исторические скрипты Launch-Recon/rea-env/shared_session_host_accept_trial требуют адаптации. Prepare-Mission6Capture принимает собственный PrivateRoot вне репозитория. Старый ac8_ghidra_mcp_research_client читает конфигурацию Codex по пути автора и требует настройки и Python MCP SDK; не запускать его вслепую. Содержимое конфигурации/токенов не публикуется.

Изменения переносимости этой передачи: Prepare-LifecycleStop теперь собирает runtime из официального UE4SS, исходников Lua и результатов сборки. Start-LifecyclePair принимает KitRoot/OutputRoot, выбирает stop-v4 по флагу и использует игнорируемый evidence/lifecycle-lab вместо приватного пути автора. Исторические хеши уже проверенного игрового runtime сохранены: новая компиляция DLL может иметь другой хеш.

Частные журналы текущей проверки находятся в build/handoff-check и не входят в Git. Сырые игровые снимки, игровые ресурсы, EXE, saves, DLL/PDB и архивы не добавляются. Подробности продолжения — [HANDOFF](../HANDOFF-RU.md).
