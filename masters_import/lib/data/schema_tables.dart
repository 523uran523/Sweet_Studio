/// Единый реестр таблиц: что синхронизируется, что аудируется, что попадает
/// в резервную копию и в каком порядке восстанавливается.
///
/// Зачем один список: до него добавление таблицы требовало правок в четырёх
/// местах (audit-триггеры, триггеры `sync_outbox`, `backupData`,
/// `restoreFromBackup`/`mergeFromBackup`). Любое расхождение между списками
/// означало молчаливую потерю данных: например, `suppliers`, `purchases`,
/// `purchase_lines`, `inventory_compositions`, `recurring_payments` и
/// `payroll_periods` не попадали в резервную копию вовсе.
///
/// Правило: новая таблица добавляется здесь одной строкой. Если таблицы в
/// базе ещё нет (старая схема), генераторы триггеров её пропускают — поэтому
/// реестр можно расширять заранее, до миграции.
library;

/// Ключи, которые использует формат резервной копии.
///
/// Ключ может отличаться от имени таблицы: исторически часть ключей короткая
/// (`stages`, `sessions`, `shifts`). Совместимость со старыми копиями важнее
/// единообразия, поэтому соответствие живёт здесь, а не в вызывающем коде.
class BackupTable {
  const BackupTable(this.key, this.table);

  /// Ключ в JSON резервной копии.
  final String key;

  /// Имя таблицы в SQLite.
  final String table;
}

/// Таблицы, которые участвуют в обмене между устройствами, в порядке
/// применения: сначала справочники, затем зависимые строки.
///
/// `work_sessions` намеренно отсутствуют: их идентификатор локальный
/// (autoincrement), поэтому строки не сопоставимы между устройствами.
/// `job_attachments` не синхронизируются: `file_path` — локальный путь,
/// файл на другое устройство не переносится.
const List<String> kSyncedTables = <String>[
  'clients',
  'employees',
  'suppliers',
  'accounts',
  'booking_resources',
  'inventory_items',
  'objects',
  // v24: заявка — родитель заказа (`jobs.lead_id`), поэтому раньше `jobs`.
  'leads',
  'jobs',
  'job_stages',
  'materials',
  'appointments',
  'client_reminders',
  'cash_shifts',
  'money_transactions',
  'purchases',
  'purchase_lines',
  // v25 «точки» (Э5): справочник локаций — родитель остатков, партий и
  // перемещений, поэтому стоит до зависимых таблиц.
  'locations',
  'stock_movements',
  'stock_levels',
  'stock_batches',
  'transfers',
  'transfer_lines',
  'inventory_compositions',
  'time_entries',
  'employee_payments',
  'recurring_payments',
  'payroll_periods',
  'period_closures',
  // v22: обязательства, деньги клиента, атрибуты сущностей.
  'obligations',
  'client_credits',
  'entity_attributes',
  // v24: `leads` стоит выше (перед `jobs`), здесь только снимки КП — они
  // ссылаются и на заказ, и на заявку.
  'quotes',
];

/// Порядок восстановления из резервной копии: тот же, что порядок обмена
/// (родитель раньше ребёнка), плюс таблицы, которые не синхронизируются, но
/// входят в копию.
const List<String> kBackupApplyOrder = <String>[
  ...kSyncedTables,
  'attribute_types',
  'work_sessions',
  'recipe_lines',
  // v26 «история начислений»: только в резервной копии, обмен между
  // устройствами не подтверждён до решения о формате (§12.4).
  'pay_conditions',
  'payslips',
  'accrual_entries',
];

/// Соответствие «ключ резервной копии → таблица», в порядке восстановления.
///
/// В `restoreFromBackup` строки вставляются в этом порядке, поэтому он же
/// защищает от вставки ребёнка раньше родителя.
const List<BackupTable> kBackupTables = <BackupTable>[
  BackupTable('clients', 'clients'),
  BackupTable('employees', 'employees'),
  BackupTable('suppliers', 'suppliers'),
  BackupTable('accounts', 'accounts'),
  BackupTable('booking_resources', 'booking_resources'),
  BackupTable('inventory_items', 'inventory_items'),
  BackupTable('inventory_compositions', 'inventory_compositions'),
  BackupTable('recipe_lines', 'recipe_lines'),
  BackupTable('objects', 'objects'),
  // v24: заявка — родитель заказа (`jobs.lead_id`), поэтому вставляется раньше.
  BackupTable('leads', 'leads'),
  BackupTable('jobs', 'jobs'),
  BackupTable('stages', 'job_stages'),
  BackupTable('materials', 'materials'),
  BackupTable('sessions', 'work_sessions'),
  BackupTable('appointments', 'appointments'),
  BackupTable('client_reminders', 'client_reminders'),
  BackupTable('shifts', 'cash_shifts'),
  BackupTable('money_transactions', 'money_transactions'),
  BackupTable('purchases', 'purchases'),
  BackupTable('purchase_lines', 'purchase_lines'),
  // v25 «точки» (Э5).
  BackupTable('locations', 'locations'),
  BackupTable('stock_movements', 'stock_movements'),
  BackupTable('stock_levels', 'stock_levels'),
  BackupTable('stock_batches', 'stock_batches'),
  BackupTable('transfers', 'transfers'),
  BackupTable('transfer_lines', 'transfer_lines'),
  BackupTable('time_entries', 'time_entries'),
  BackupTable('employee_payments', 'employee_payments'),
  BackupTable('recurring_payments', 'recurring_payments'),
  BackupTable('payroll_periods', 'payroll_periods'),
  BackupTable('period_closures', 'period_closures'),
  // v26: история начислений — только в копии, не в обмене.
  BackupTable('pay_conditions', 'pay_conditions'),
  BackupTable('payslips', 'payslips'),
  BackupTable('accrual_entries', 'accrual_entries'),
  // v22
  BackupTable('obligations', 'obligations'),
  BackupTable('client_credits', 'client_credits'),
  BackupTable('entity_attributes', 'entity_attributes'),
  BackupTable('attribute_types', 'attribute_types'),
  // v24: `quotes` ссылается на `jobs` и `leads`, оба выше — вставляются последними.
  BackupTable('quotes', 'quotes'),
];

/// Таблицы, для которых генерируются audit-триггеры.
///
/// Шире реестра обмена: сюда входят локальные таблицы, изменения которых
/// всё равно нужно видеть в журнале (`work_sessions`, `recipe_lines`).
/// `job_attachments` намеренно без аудита: это файлы, а не данные.
const List<String> kAuditedTables = <String>[
  'clients',
  'objects',
  'jobs',
  'job_stages',
  'materials',
  'work_sessions',
  'accounts',
  'cash_shifts',
  'money_transactions',
  'inventory_items',
  'suppliers',
  'purchases',
  'purchase_lines',
  'stock_movements',
  'recipe_lines',
  'booking_resources',
  'appointments',
  'client_reminders',
  'employees',
  'time_entries',
  'employee_payments',
  'recurring_payments',
  'payroll_periods',
  'period_closures',
  // v22
  'obligations',
  'client_credits',
  'entity_attributes',
  // v24
  'leads',
  'quotes',
  // v25: перемещения и партии — часть товарного учёта, их правки видны в
  // журнале наравне с `stock_movements`.
  'locations',
  'stock_levels',
  'stock_batches',
  'transfers',
  'transfer_lines',
  // v26: правки истории начислений видны в журнале.
  'pay_conditions',
  'payslips',
  'accrual_entries',
];

/// Таблицы, которые нужно пересоздавать при обновлении схемы добавлением
/// sync-колонок (`updated_at`, `deleted_at`, `device_id`).
///
/// Это исторический список миграций v7/v11/v20: он покрывает таблицы, которые
/// существовали до появления синхронизации. Новые таблицы объявляют колонки
/// сразу в `CREATE TABLE`, поэтому здесь их нет.
const List<String> kSyncColumnTables = <String>[
  'clients',
  'objects',
  'jobs',
  'job_stages',
  'materials',
  'work_sessions',
  'accounts',
  'cash_shifts',
  'money_transactions',
  'inventory_items',
  'suppliers',
  'purchases',
  'purchase_lines',
  'stock_movements',
  'recipe_lines',
  'inventory_compositions',
  'booking_resources',
  'appointments',
  'client_reminders',
  'employees',
  'time_entries',
  'employee_payments',
  'recurring_payments',
  'payroll_periods',
  // v26: история начислений — колонки синхронизации есть, но сам обмен
  // между устройствами не подтверждён (таблицы не в kSyncedTables).
  'pay_conditions',
  'payslips',
  'accrual_entries',
];

/// Текстовые колонки, где живут пользовательские строки на русском.
///
/// Технические поля (id, статусы, пути, JSON) намеренно исключены: их
/// «починка» от двойной кодировки только испортила бы данные.
const Map<String, List<String>> kMojibakeScanColumns = <String, List<String>>{
  'clients': <String>['name', 'note'],
  'objects': <String>['title', 'address', 'note'],
  'jobs': <String>['title', 'note'],
  'job_stages': <String>['title'],
  'materials': <String>['name', 'unit'],
  'work_sessions': <String>['note'],
  'recurring_payments': <String>['name', 'category', 'note'],
  'payroll_periods': <String>['name', 'note'],
  'period_closures': <String>['note'],
  'employees': <String>['name'],
  'time_entries': <String>['note'],
  'employee_payments': <String>['note'],
  'client_reminders': <String>['title', 'body'],
  'booking_resources': <String>['name'],
  'appointments': <String>['title', 'note'],
  'inventory_items': <String>['name', 'unit', 'category'],
  'suppliers': <String>['name', 'note'],
  'purchases': <String>['note'],
  'stock_movements': <String>['note'],
  'inventory_compositions': <String>['note'],
  'accounts': <String>['name'],
  'cash_shifts': <String>['note'],
  'money_transactions': <String>['category', 'note'],
  'job_attachments': <String>['file_name'],
  // v24
  'leads': <String>['name', 'request', 'note'],
  // v25
  'locations': <String>['name', 'description'],
};

/// Обязательные ссылки: таблица → (колонка, родительская таблица).
///
/// Нужны при восстановлении копии: если родительской строки в копии нет,
/// строку-сироту пропускаем, иначе она всплывёт в интерфейсе «пустой».
/// На web внешние ключи не проверяются, поэтому проверка живёт в коде.
const Map<String, List<List<String>>> kTableDependencies =
    <String, List<List<String>>>{
  'objects': <List<String>>[
    <String>['client_id', 'clients'],
  ],
  'jobs': <List<String>>[
    <String>['client_id', 'clients'],
  ],
  // v24: заявка может быть привязана к клиенту; снимок КП — к заказу/заявке.
  'leads': <List<String>>[
    <String>['client_id', 'clients'],
  ],
  'quotes': <List<String>>[
    <String>['job_id', 'jobs'],
    <String>['lead_id', 'leads'],
  ],
  'job_stages': <List<String>>[
    <String>['job_id', 'jobs'],
  ],
  'materials': <List<String>>[
    <String>['job_id', 'jobs'],
  ],
  'work_sessions': <List<String>>[
    <String>['job_id', 'jobs'],
  ],
  'purchase_lines': <List<String>>[
    <String>['purchase_id', 'purchases'],
  ],
  'inventory_compositions': <List<String>>[
    <String>['item_id', 'inventory_items'],
  ],
  'recipe_lines': <List<String>>[
    <String>['product_item_id', 'inventory_items'],
  ],
  // v25 «точки» (Э5): остатки и партии привязаны к позиции и локации, строки
  // перемещения — к перемещению. Ссылочная колонка обязана существовать в
  // копии, иначе строка-сирота покажет «пустую» локацию в интерфейсе.
  'stock_levels': <List<String>>[
    <String>['item_id', 'inventory_items'],
    <String>['location_id', 'locations'],
  ],
  'stock_batches': <List<String>>[
    <String>['item_id', 'inventory_items'],
    <String>['location_id', 'locations'],
  ],
  'transfers': <List<String>>[
    <String>['from_location_id', 'locations'],
    <String>['to_location_id', 'locations'],
  ],
  'transfer_lines': <List<String>>[
    <String>['transfer_id', 'transfers'],
    <String>['item_id', 'inventory_items'],
  ],
  // v26: ведомость привязана к периоду и сотруднику, строка начисления —
  // к условиям оплаты, ведомости и сотрудникам. Сироты пропускаются.
  'pay_conditions': <List<String>>[
    <String>['employee_id', 'employees'],
  ],
  'payslips': <List<String>>[
    <String>['period_id', 'payroll_periods'],
    <String>['employee_id', 'employees'],
  ],
  'accrual_entries': <List<String>>[
    <String>['employee_id', 'employees'],
    <String>['pay_condition_id', 'pay_conditions'],
    <String>['payslip_id', 'payslips'],
  ],
};
