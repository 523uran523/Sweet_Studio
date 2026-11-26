# Masters — архитектура

Обновлено: 05.11.2026. Приложение `0.3.17+20`, схема БД **v21**, тесты 131/131.
Всё, что связано с запуском, сборкой, релизами и синхронизацией — в `README.md`.

Local-first учёт для мастера/бригады: один код на Android/iOS/Windows/Web,
Cupertino UI, SQLite как единственный источник правды, работает без интернета.

## 1. Слои и пути

```
lib/main.dart                 инициализация: БД → настройки → стор → runApp
lib/app/
  app.dart                    корень: PIN/биометрия, авторизация, автосинк
  root_shell.dart             нижняя навигация, скрытие вкладок из настроек
  tax_radar_bar.dart          полоса налоговой подушки
  ui.dart                     библиотека компактных компонентов (см. §3)
  theme/                      палитра и темы
lib/state/
  masters_store.dart          центральное состояние и вся бизнес-логика
  settings_controller.dart    настройки (SharedPreferences)
  sync_service.dart           фоновый обмен с meaxis-sync
lib/data/
  app_database.dart           схема, миграции v1→v21, аудит-триггеры, integrity
  models/                     сущности (sums — целые, в копейках)
  repositories/               CRUD; getAll() фильтрует deleted_at IS NULL
lib/features/<модуль>/        экраны: today money stats jobs clients inventory
                              booking unified_booking employees more settings
                              onboarding
lib/core/                     сервисы: backup, document (PDF), update, oauth,
                              disk, sync_client, pin, biometric, reminder,
                              deep_link, text_encoding, units, api_config
test/                         131 тестов: БД, миграции, стор, деньги, кодировки
web/ web_server/              web-ассеты, wasm, локальный сервер и прокси
```

Платформенные различия — только через `kIsWeb` и условные импорты
(`dart.library.*`), как в `web_url.dart` и `main.dart`. `dart:io`/`dart:html`
в общей логике запрещены.

## 2. Данные

Все суммы — целые в минимальных единицах, `double` для денег запрещён.
`newId()` даёт sortable-идентификатор; на web — два 30-битных числа
(`1 << 32` в JS даёт `RangeError`).

Мягкое удаление и синхронизация (v7): `updated_at`, `deleted_at`, `device_id`
во всех таблицах; `delete()` только помечает запись.

Ключевые миграции:

| v | Что добавлено |
|---|---|
| 1–6 | ядро, деньги, склад, бронирования, напоминания, исполнители |
| 7 | sync-колонки |
| 8, 11 | аудит: уровень приложения + DB-триггеры |
| 9–10 | закрытые периоды, регулярные платежи, расчётные периоды |
| 12–14 | вложения к заказам, фото чека, закреплённые заказы |
| 15–17 | состояние калькулятора, таймер сессий, сторно (`reverses_id`) |
| 18 | рецептуры/составы изделий (BOM) |
| 19 | индексы единого бронирования (appointments + jobs по датам) |
| 20 | синхронизация между устройствами (meaxis-sync) |
| 21 | исправление битой кириллицы в уже сохранённых данных |

Целостность: `integrityIssues()` (`foreign_key_check` + `quick_check`).
На web `PRAGMA foreign_keys = ON` не выполняется — в wasm это «SQL logic
error», поэтому целостность проверяет приложение.

## 3. UI-конвенции (с 0.3.16)

Правило: экран не должен быть «простынёй» полноширинных кнопок. Редкие
действия уходят в меню, повторяющиеся — в чипы, список — в строки.

Примитивы (`lib/app/ui.dart`):

| Компонент | Назначение |
|---|---|
| `AppCard` | карточка-секция; `onTap` ведёт себя как нажатие, но **не** перекрашивает заголовок в акцент (обёртка `CupertinoButton` убрана намеренно) |
| `ListRow` | строка списка: иконка, подпись, подпись справа, шеврон; есть dense-вариант |
| `KeyValueRow` | выровненная строка «подпись — значение» для любых сводок |
| `ChipButton` | пилюля «иконка + подпись» для частых действий |
| `OverflowMenuButton` | меню редких действий вместо ряда кнопок |
| `MiniAction` | компактное действие внутри строки |
| `Pill` | счётчик/статус |
| `StatTile`, `ProgressBar`, `Hairline`, `SectionLabel`, `IconBadge`, `EmptyState`, `SheetHandle` | вспомогательные |

Склонения русских существительных — только из `lib/core/utils/app_utils.dart`
(`pluralRu` + `ordersWord`, `itemsWord`, `accountsWord`, `employeesWord`,
`clientsWord`, `suppliersWord`, `daysWord`, `eventsWord`, `operationsWord`,
`minutesWord` и др.). Конкатенация числа со словом в экранах запрещена.

Что это дало по экранам: «Сегодня» — сводка карточкой `KeyValueRow`, заказы
одним списком с `Pill` статуса, действия WhatsApp/SMS чипами; «Деньги» —
карточка «Сегодня», чипы операций, компактные регулярные платежи; «Итоги» —
`StatTile` без обрезки подписей и единый барный список срезов; «Команда»,
«Склад», «Клиенты» — `ListRow` + `OverflowMenuButton`; «Ещё» — вместо
`CupertinoListTile` те же `ListRow`; «События» — компактные заголовки колонок
канбана и строка дней недели в календаре.

## 4. Состояние: `MastersStore`

Один `ChangeNotifier` на всё приложение: typed-списки, агрегаты, кэши
(`_intCache`, `_earnedCache`, `_balanceCache`), инвалидация в
`notifyListeners()`. Экраны читают стор синхронно, стор вызывает репозитории.

Группы API: клиенты/объекты/заказы (+материалы, сессии, этапы, себестоимость,
минуты); деньги (счета, смены, транзакции, переводы, сторно, Excel-импорт,
регулярные платежи, закрытые периоды, прогноз до конца месяца); люди
(табель, выплаты, начисления за период, ведомость); синхронизация и бэкап
(`backupData`, `restoreFromBackup`, `mergeFromBackup` →
`BackupMergeResult { affected, keptLocal, conflicts }`); безопасность
(`checkDataIntegrity`, guard `ensurePeriodOpen`).

Закрытые смены и периоды не редактируются — только корректировочная запись.

## 5. Синхронизация и бэкап

Три независимых канала:

1. **JSON-бэкап** — `backupData()` снимает все таблицы, `restoreFromBackup()`
   заменяет транзакционно, `mergeFromBackup()` сливает по `updated_at`.
2. **Яндекс.Диск** — OAuth (PKCE) + REST, файл `disk:/Masters/
   masters-backup-latest.json`, общий для web и Android. Секрет в браузер не
   попадает: его подставляет локальный сервер/прокси из переменной окружения.
   Регистрация приложения и redirect URI — в `README.md`.
3. **meaxis-sync** (v20) — собственный сервер, слияние по записям; клиент в
   `lib/core/sync_client.dart` + `lib/state/sync_service.dart`.

CSV — только ручная выгрузка «для Excel», на синхронизацию не влияет.

## 6. Обновления и безопасность

`lib/core/update_service.dart`: сверяет `version_code`, скачивает APK с
дозагрузкой по HTTP Range, проверяет SHA-256 (несовпадение — файл удаляется),
устанавливает через `open_filex`. **Клиент обновляется только по `version_code`**,
поэтому каждый выпуск обязан поднимать и build-номер.

PIN и биометрия (`app_pin_service.dart`, `app_biometric.dart`), журнал
действий (`audit_log` + триггеры), защита закрытых периодов.

## 7. Web-специфика

- `databaseFactoryFfiWebNoWebWorker` (без worker — проще отлаживать),
  `web/sqlite3.wasm` зафиксирован под пакет `sqlite3 3.5.2`.
  `dart run sqflite_common_ffi_web:setup` вслепую не запускать: он ставит
  несовместимый wasm.
- `web_server/server.dart` — статика + SPA-fallback; `api_proxy.dart` —
  маршруты `/api/oauth/token`, `/api/disk/*`, `/api/upload`, `/api/fetch`.
- Две вкладки приложения пишут в одну IndexedDB; `single_tab_coordinator*`
  показывает предупреждение.

## 8. Что дальше

- **Masters 2.0 — реконструкция интерфейса.** ТЗ, визуальный прототип и этапы
  0–7 — в `docs/masters-2/`. Учётное ядро и схема v26 не переписываются;
  новые таблицы (черновики, шаблоны, пользовательские поля) — только отдельной
  миграцией с backup/restore и тестами.
- Синхронизация: довести конфликты до UI и вынести обмен токена с мобильных
  сборок на backend. Таблицы v26 (`pay_conditions`, `payslips`,
  `accrual_entries`) в `kSyncedTables` не включать без отдельного протокола
  согласованности.
- Пилот на 3–5 реальных бизнесах; ручная сверка старых закрытых периодов
  зарплаты (они остаются «предварительно, требует сверки»).
- Очередь задач — в `docs/specs/_queue.md`.
