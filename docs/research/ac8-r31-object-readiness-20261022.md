# R31 object-readiness-1

22.10.2026. Обновление комплекта по результатам
[офлайн-анализа зависимостей](ac8-guest-world-dependencies-20261022.md).
Игра не запускалась, runtime-приёмка не выполнялась.

## Изменение

Раньше наличие LiveActorManager допускало последующие native-шаги даже тогда,
когда его CombatZone или LiveObjectMapper ещё отсутствовали. Теперь native
backend до lookup FlightData захватывает identities этих объектов и проверяет:

- текущий игровой поток и identity World/ActorManager/CombatZone/Level/mapper;
- точные native-классы LiveActorManager, LiveCombatZone и LiveObjectMapper,
  полученные через reflection и переданные в локальном Lua-запросе;
- Outer ActorManager → World, CombatZone → Level → тот же World,
  mapper → ActorManager;
- ссылки ActorManager+1a0/+1b0 на те же объекты;
- наличие внутреннего spatial index mapper+28, shared control +30,
  marker +58==1 и сохранность этих указателей;
- повторную identity-проверку после чтений.

Захват UObject serial использует существующий проверенный identity helper.
Сама функция `world_objects_error` только читает память; неизвестные функции
и новые native entry points не вызываются. Новых объектов менеджеров она
не создаёт. Неподдержанные производные классы намеренно не допускаются этим
контрактом; это не универсальный UE5 type checker.

Проверка повторяется перед попыткой spawn, FinishSpawn и в дальнейших guard
проверках. При потере зависимостей cleanup не обходит защиту: неизвестный граф
может остаться в quarantine до обычного выхода из процесса. В отсутствие
готовых объектов подготовка сразу отказывается; блокирующего ожидания или
автоповторов нет. Одна native-попытка на процесс остаётся ограничением R31.

## Дополнительное статическое доказательство RG-02

GhidraMCP снова подтвердил офлайн-копию build25201480, base `0x140000000`, SHA256
`51510e2a520565dbe81fb0d569e95cd4393077acaaa859371489b80b8128829f`.

`0x147d30f90`, вызываемый с CombatZone+308 из `0x1473a2820`, **не сохраняет
прямой указатель на этот контекст**. Гипотеза о таком backlink опровергнута:
функция копирует/расширяет границы, создаёт spatial index и shared control.
Проверены инструкции `0x147d30fa0/fa5`, `0x147d30fb5/fd9/fde`,
`0x147d3113d/146/14e`. Они подтверждают +28, +30 и marker +58.
Последний выставляется до публикации индекса, поэтому одного marker недостаточно.

Сырые ответы: `.tools/offline-research/r31-object-readiness-20261022/`.
Их хеши и сверка 1024 байт с PE —
[byte-verification](../../evidence/r31-object-readiness-20261022/byte-verification.json).
Команда: `python scripts/verify_ac8_object_readiness_evidence.py`.
Проверены также прежние 15 memory ranges и 17 entry anchors native-контракта.

## Диагностика и совместимость

В guest-pilot-status.tsv добавлены `owner_world_objects_checked/ready/reason`,
`owner_combat_zone_pointer`, `owner_actor_mapper_pointer`. Они попадают в health
samples, автоматические ZIP и сводку анализатора. Отсутствие зависимости при
захвате также остаётся в owner_detail/engine_detail и native JSONL.
Причины начинаются с `owner_world_`; ошибку звуковой зависимости переименовали
в `owner_beginplay_sound_manager_missing`.

Manifest содержит `kit_update=object-readiness-1`, `owner_world_readiness=1`.
Лаунчер отвергает старый marker и проверяет hashes всех поставленных файлов.
Room protocol 8 и AC8P v3 не менялись. **Оба участника получают один обновлённый
ZIP и распаковывают его заново отдельно**, без старых DLL/Lua.

## Проверки и артефакт

- MSVC x64 `/W4 /WX`: DLL и loopback helper собраны.
- 51 новая C++ проверка: missing/wrong world/type/identity, незавершённая
  инициализация mapper, stale/reuse, потеря связи перед Finish; фиктивная память.
- Остальные C++ контракты R31 прошли; native-физика не исполнялась.
- Python/Lua: 570 запусков, 569 успешных, 1 прежний optional legacy smoke skip.
- PowerShell: 25 kit/clone/refusal проверок на искусственных файлах.
- Распакованный ZIP: 72 файла, CRC/hashes/exports/PS5 ValidateOnly,
  синтаксис 39 Lua, 61 текст проверен на секреты/личные пути.

Архив: `dist/ac8-steam-coop-r31-development.zip`, 10321460 байт.
SHA256: `19d16628da9c98e875cdd3f743b4a34639c066f308188084165a135a7a482167`.
DLL SHA256: `1f01615fbd5efbb4973fd4e382d5defc3952a6ea417167ec38cf26a29082ad29`.
Полный [manifest обновления](../../evidence/r31-object-readiness-20261022/manifest.json).

Не проверены в игре создание и физика самолёта, сцена/камера, синхронизация двух
ПК, фактическое retirement и прохождение миссии. Успех автономных проверок
не означает успешного совместного полёта. Оригинальный EXE сохранил SHA256;
игровые ресурсы/сохранения не менялись, Steam-подключение и публикация не делались.
