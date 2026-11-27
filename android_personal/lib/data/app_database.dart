import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../core/calculator_core.dart';
import '../core/money_format.dart';
import '../core/orders_core.dart';
import '../core/units.dart';
import 'models.dart';

class AppDatabase {
  AppDatabase._({
    required this.dbPath,
    required this.factory,
    required Database db,
    // Named parameters cannot start with '_', so the private field is assigned in the initializer.
    // ignore: prefer_initializing_formals
  }) : _db = db;

  static const int schemaVersion = 1;
  static const String defaultDbFileName = 'sweet_studio.db';

  final String dbPath;
  final DatabaseFactory factory;
  Database _db;

  Database get rawDb => _db;

  static Future<AppDatabase> openDefault({DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dir = await f.getDatabasesPath();
    final path = p.join(dir, defaultDbFileName);
    return openAtPath(path, factory: f);
  }

  static Future<AppDatabase> openAtPath(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchemaV1(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Reserved for incremental schema migrations in future versions.
        },
      ),
    );
    return AppDatabase._(dbPath: path, factory: f, db: db);
  }

  static Future<void> _createSchemaV1(Database db) async {
    await db.execute('''
      CREATE TABLE studio_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        studio_name TEXT NOT NULL,
        slogan TEXT NOT NULL,
        currency_symbol TEXT NOT NULL,
        theme_index INTEGER NOT NULL DEFAULT 0,
        hidden_modules_json TEXT NOT NULL DEFAULT '[]',
        is_demo_mode INTEGER NOT NULL DEFAULT 0,
        onboarding_completed INTEGER NOT NULL DEFAULT 0,
        last_backup_at TEXT,
        notify_orders INTEGER NOT NULL DEFAULT 1,
        notify_tasks INTEGER NOT NULL DEFAULT 1,
        notify_stock INTEGER NOT NULL DEFAULT 1,
        notify_expiry INTEGER NOT NULL DEFAULT 1,
        local_notifications_enabled INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.insert('studio_profile', {
      'id': 1,
      'studio_name': 'Моя кондитерская',
      'slogan': 'Авторские десерты на заказ',
      'currency_symbol': '₽',
      'theme_index': 0,
      'hidden_modules_json': '[]',
      'is_demo_mode': 0,
      'onboarding_completed': 0,
      'notify_orders': 1,
      'notify_tasks': 1,
      'notify_stock': 1,
      'notify_expiry': 1,
      'local_notifications_enabled': 0,
    });

    await db.execute('''
      CREATE TABLE recipes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'approved',
        yield_grams REAL NOT NULL,
        gross_grams REAL,
        yield_portions INTEGER NOT NULL DEFAULT 1,
        form_size TEXT,
        photo_path TEXT,
        ingredients_json TEXT NOT NULL DEFAULT '[]',
        pack_variants_json TEXT NOT NULL DEFAULT '[]',
        steps_json TEXT NOT NULL DEFAULT '[]',
        allergens_json TEXT NOT NULL DEFAULT '[]',
        labor_hours REAL NOT NULL DEFAULT 1.5,
        labor_rate_cents INTEGER NOT NULL DEFAULT 55000,
        packaging_cents INTEGER NOT NULL DEFAULT 0,
        overhead_percent REAL NOT NULL DEFAULT 10,
        margin_percent REAL NOT NULL DEFAULT 45,
        cost_cents INTEGER NOT NULL DEFAULT 0,
        recommended_price_cents INTEGER NOT NULL DEFAULT 0,
        shelf_life_hours INTEGER NOT NULL DEFAULT 72,
        storage_condition TEXT,
        favorite INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        category TEXT,
        unit TEXT NOT NULL,
        qty_on_hand REAL NOT NULL DEFAULT 0,
        min_qty REAL NOT NULL DEFAULT 0,
        avg_cost_cents INTEGER NOT NULL DEFAULT 0,
        density REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_lots (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
        item_name TEXT NOT NULL,
        lot_code TEXT NOT NULL,
        unit TEXT NOT NULL,
        initial_qty REAL NOT NULL,
        remaining_qty REAL NOT NULL,
        unit_cost_cents INTEGER NOT NULL,
        expires_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        item_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        lot_id TEXT,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        total_cents INTEGER NOT NULL,
        reason TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        contact_name TEXT,
        phone TEXT,
        category TEXT,
        debt_cents INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        supplier_id TEXT,
        supplier_name TEXT NOT NULL,
        item_id TEXT,
        item_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        price_cents INTEGER NOT NULL,
        delivery_cents INTEGER NOT NULL DEFAULT 0,
        expected_date TEXT,
        expires_at TEXT,
        status TEXT NOT NULL DEFAULT 'ordered'
      )
    ''');

    await db.execute('''
      CREATE TABLE production_runs (
        id TEXT PRIMARY KEY,
        recipe_id TEXT,
        recipe_title TEXT NOT NULL,
        planned_grams REAL NOT NULL,
        actual_grams REAL NOT NULL DEFAULT 0,
        total_cost_cents INTEGER NOT NULL DEFAULT 0,
        output_lot_id TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        preferences TEXT,
        allergens TEXT,
        deposit_cents INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL,
        title TEXT NOT NULL,
        client_id TEXT,
        client_name TEXT NOT NULL,
        items_json TEXT NOT NULL DEFAULT '[]',
        recipe_id TEXT,
        recipe_title TEXT,
        weight_grams REAL NOT NULL DEFAULT 0,
        price_cents INTEGER NOT NULL DEFAULT 0,
        cost_cents INTEGER NOT NULL DEFAULT 0,
        prepayment_cents INTEGER NOT NULL DEFAULT 0,
        paid_cents INTEGER NOT NULL DEFAULT 0,
        discount_cents INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'confirmed',
        due_date TEXT,
        delivery_address TEXT,
        wishes TEXT,
        allergens TEXT,
        stock_deducted INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE work_items (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        source_id TEXT,
        title TEXT NOT NULL,
        due_date TEXT,
        priority TEXT NOT NULL DEFAULT 'normal',
        stage TEXT NOT NULL DEFAULT 'queue',
        tags_json TEXT NOT NULL DEFAULT '[]',
        recurrence TEXT NOT NULL DEFAULT 'none',
        series_id TEXT,
        occurrence_index INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        balance_cents INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE money_transactions (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        category TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        account_id TEXT NOT NULL,
        account_name TEXT NOT NULL,
        order_id TEXT,
        reverses_id TEXT,
        note TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE time_entries (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        minutes INTEGER NOT NULL,
        note TEXT
      )
    ''');
  }

  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
  }

  Future<void> _reopen() async {
    if (_db.isOpen) return;
    _db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  Future<Uint8List> exportDatabaseBytes() async {
    if (dbPath == inMemoryDatabasePath) {
      throw StateError('Нельзя экспортировать базу из памяти в файл.');
    }
    await close();
    try {
      return await File(dbPath).readAsBytes();
    } finally {
      await _reopen();
    }
  }

  Future<void> replaceDatabaseWithBytes(Uint8List bytes) async {
    if (dbPath == inMemoryDatabasePath) {
      throw StateError('Нельзя заменить базу в памяти файлом.');
    }
    await close();
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.delete();
        }
      }
      final file = File(dbPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } finally {
      await _reopen();
    }
  }

  static Future<List<String>> validateExternalDatabaseFile(
    String path, {
    DatabaseFactory? dbFactory,
  }) async {
    final f = dbFactory ?? databaseFactory;
    Database? extDb;
    try {
      extDb = await f.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final res = await extDb.rawQuery('PRAGMA integrity_check');
      final issues = <String>[];
      for (final row in res) {
        final msg = row.values.first?.toString() ?? '';
        if (msg.toLowerCase() != 'ok') {
          issues.add(msg);
        }
      }
      final tables = await extDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((r) => r['name']?.toString()).toSet();
      for (final req in [
        'studio_profile',
        'recipes',
        'orders',
        'inventory_items',
        'accounts',
      ]) {
        if (!names.contains(req)) {
          issues.add('Отсутствует обязательная таблица $req');
        }
      }
      return issues;
    } catch (e) {
      return ['Ошибка открытия SQLite: $e'];
    } finally {
      await extDb?.close();
    }
  }

  Future<List<String>> checkIntegrity() async {
    final issues = <String>[];
    final check = await _db.rawQuery('PRAGMA integrity_check');
    for (final row in check) {
      final val = row.values.first?.toString() ?? '';
      if (val.toLowerCase() != 'ok') {
        issues.add('integrity_check: $val');
      }
    }
    final fk = await _db.rawQuery('PRAGMA foreign_key_check');
    for (final row in fk) {
      issues.add('foreign_key_check: $row');
    }
    return issues;
  }

  Future<Map<String, int>> getRecordCounts() async {
    const tables = [
      'recipes',
      'inventory_items',
      'stock_lots',
      'stock_movements',
      'suppliers',
      'purchases',
      'production_runs',
      'clients',
      'orders',
      'work_items',
      'accounts',
      'money_transactions',
      'time_entries',
    ];
    final out = <String, int>{};
    for (final t in tables) {
      final res = await _db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      out[t] = (res.first['c'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  // ==================== Profile ====================

  Future<StudioProfile> getProfile() async {
    final rows = await _db.query('studio_profile', where: 'id = 1');
    if (rows.isEmpty) return const StudioProfile();
    final r = rows.first;
    final hiddenRaw = jsonDecode((r['hidden_modules_json'] ?? '[]') as String);
    final hidden = hiddenRaw is List
        ? hiddenRaw.map((e) => e.toString()).toList()
        : const <String>[];
    return StudioProfile(
      studioName: (r['studio_name'] ?? 'Моя кондитерская') as String,
      slogan: (r['slogan'] ?? 'Авторские десерты на заказ') as String,
      currencySymbol: (r['currency_symbol'] ?? '₽') as String,
      themeIndex: (r['theme_index'] as num?)?.toInt() ?? 0,
      hiddenModules: hidden,
      isDemoMode: (r['is_demo_mode'] as num?)?.toInt() == 1,
      onboardingCompleted: (r['onboarding_completed'] as num?)?.toInt() == 1,
      lastBackupAt: r['last_backup_at'] as String?,
      notifyOrders: (r['notify_orders'] as num?)?.toInt() != 0,
      notifyTasks: (r['notify_tasks'] as num?)?.toInt() != 0,
      notifyStock: (r['notify_stock'] as num?)?.toInt() != 0,
      notifyExpiry: (r['notify_expiry'] as num?)?.toInt() != 0,
      localNotificationsEnabled:
          (r['local_notifications_enabled'] as num?)?.toInt() == 1,
    );
  }

  Future<void> saveProfile(StudioProfile p) async {
    await _db.update(
      'studio_profile',
      {
        'studio_name': p.studioName,
        'slogan': p.slogan,
        'currency_symbol': p.currencySymbol,
        'theme_index': p.themeIndex,
        'hidden_modules_json': jsonEncode(p.hiddenModules),
        'is_demo_mode': p.isDemoMode ? 1 : 0,
        'onboarding_completed': p.onboardingCompleted ? 1 : 0,
        'last_backup_at': p.lastBackupAt,
        'notify_orders': p.notifyOrders ? 1 : 0,
        'notify_tasks': p.notifyTasks ? 1 : 0,
        'notify_stock': p.notifyStock ? 1 : 0,
        'notify_expiry': p.notifyExpiry ? 1 : 0,
        'local_notifications_enabled': p.localNotificationsEnabled ? 1 : 0,
      },
      where: 'id = 1',
    );
  }

  Future<void> updateLastBackupAt(String iso) async {
    await _db.update(
      'studio_profile',
      {'last_backup_at': iso},
      where: 'id = 1',
    );
  }

  Future<void> ensureDefaultCashAccount() async {
    final existing = await _db.query('accounts');
    if (existing.isEmpty) {
      await _db.insert('accounts', {
        'id': 'acc_cash',
        'name': 'Наличные',
        'kind': AccountKind.cash.name,
        'balance_cents': 0,
      });
    }
  }

  // ==================== Reads ====================

  Future<List<Recipe>> getRecipes() async {
    final rows = await _db.query('recipes', orderBy: 'favorite DESC, updated_at DESC');
    return rows.map(_recipeFromRow).toList();
  }

  Future<List<InventoryItem>> getInventoryItems() async {
    final rows = await _db.query('inventory_items', orderBy: 'name ASC');
    return rows.map(_inventoryFromRow).toList();
  }

  Future<List<StockLot>> getStockLots() async {
    final rows = await _db.query(
      'stock_lots',
      orderBy:
          "CASE WHEN expires_at IS NULL OR expires_at = '' THEN 1 ELSE 0 END ASC, expires_at ASC, created_at ASC",
    );
    return rows.map(_lotFromRow).toList();
  }

  Future<List<StockMovement>> getStockMovements({int limit = 200}) async {
    final rows = await _db.query(
      'stock_movements',
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(_movementFromRow).toList();
  }

  Future<List<Supplier>> getSuppliers() async {
    final rows = await _db.query('suppliers', orderBy: 'name ASC');
    return rows
        .map((r) => Supplier(
              id: r['id'] as String,
              name: r['name'] as String,
              contactName: r['contact_name'] as String?,
              phone: r['phone'] as String?,
              category: r['category'] as String?,
              debtCents: (r['debt_cents'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<List<Purchase>> getPurchases() async {
    final rows = await _db.query('purchases', orderBy: 'expected_date DESC');
    return rows.map(_purchaseFromRow).toList();
  }

  Future<List<ProductionRun>> getProductionRuns() async {
    final rows = await _db.query('production_runs', orderBy: 'created_at DESC');
    return rows.map(_productionFromRow).toList();
  }

  Future<List<Client>> getClients() async {
    final rows = await _db.query('clients', orderBy: 'favorite DESC, name ASC');
    return rows.map(_clientFromRow).toList();
  }

  Future<List<Order>> getOrders() async {
    final rows = await _db.query('orders', orderBy: 'created_at DESC');
    return rows.map(_orderFromRow).toList();
  }

  Future<List<WorkItem>> getWorkItems() async {
    final rows = await _db.query('work_items', orderBy: 'due_date ASC');
    return rows.map(_workItemFromRow).toList();
  }

  Future<List<Account>> getAccounts() async {
    final rows = await _db.query('accounts', orderBy: 'name ASC');
    return rows
        .map((r) => Account(
              id: r['id'] as String,
              name: r['name'] as String,
              kind: _enumByName(AccountKind.values, r['kind'] as String?,
                  AccountKind.cash),
              balanceCents: (r['balance_cents'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  Future<List<MoneyTransaction>> getMoneyTransactions() async {
    final rows =
        await _db.query('money_transactions', orderBy: 'occurred_at DESC');
    return rows
        .map((r) => MoneyTransaction(
              id: r['id'] as String,
              kind: _enumByName(TransactionKind.values, r['kind'] as String?,
                  TransactionKind.income),
              category: r['category'] as String,
              amountCents: (r['amount_cents'] as num?)?.toInt() ?? 0,
              accountId: r['account_id'] as String,
              accountName: r['account_name'] as String,
              orderId: r['order_id'] as String?,
              reversesId: r['reverses_id'] as String?,
              note: r['note'] as String?,
              occurredAt: r['occurred_at'] as String,
            ))
        .toList();
  }

  Future<List<TimeEntry>> getTimeEntries() async {
    final rows = await _db.query('time_entries', orderBy: 'date DESC');
    return rows
        .map((r) => TimeEntry(
              id: r['id'] as String,
              date: r['date'] as String,
              minutes: (r['minutes'] as num?)?.toInt() ?? 0,
              note: r['note'] as String?,
            ))
        .toList();
  }

  // ==================== CRUD Mutations ====================

  Future<void> upsertRecipe(Recipe recipe) async {
    await _db.insert(
      'recipes',
      {
        'id': recipe.id,
        'title': recipe.title,
        'category': recipe.category,
        'version': recipe.version,
        'status': recipe.status,
        'yield_grams': recipe.yieldGrams,
        'gross_grams': recipe.grossGrams,
        'yield_portions': recipe.yieldPortions,
        'form_size': recipe.formSize,
        'photo_path': recipe.photoPath,
        'ingredients_json':
            jsonEncode(recipe.ingredients.map((e) => e.toJson()).toList()),
        'pack_variants_json':
            jsonEncode(recipe.packVariants.map((e) => e.toJson()).toList()),
        'steps_json': jsonEncode(recipe.steps),
        'allergens_json': jsonEncode(recipe.allergens),
        'labor_hours': recipe.laborHours,
        'labor_rate_cents': recipe.laborRateCents,
        'packaging_cents': recipe.packagingCents,
        'overhead_percent': recipe.overheadPercent,
        'margin_percent': recipe.marginPercent,
        'cost_cents': recipe.costCents,
        'recommended_price_cents': recipe.recommendedPriceCents,
        'shelf_life_hours': recipe.shelfLifeHours,
        'storage_condition': recipe.storageCondition,
        'favorite': recipe.favorite ? 1 : 0,
        'updated_at': recipe.updatedAt.isNotEmpty
            ? recipe.updatedAt
            : DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRecipe(String recipeId) async {
    await _db.delete('recipes', where: 'id = ?', whereArgs: [recipeId]);
  }

  Future<void> upsertClient(Client client) async {
    await _db.insert(
      'clients',
      {
        'id': client.id,
        'name': client.name,
        'phone': client.phone,
        'address': client.address,
        'preferences': client.preferences,
        'allergens': client.allergens,
        'deposit_cents': client.depositCents,
        'favorite': client.favorite ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteClient(String clientId) async {
    await _db.delete('clients', where: 'id = ?', whereArgs: [clientId]);
  }

  Future<void> upsertOrder(Order order) async {
    await _db.insert(
      'orders',
      {
        'id': order.id,
        'order_number': order.orderNumber,
        'title': order.title,
        'client_id': order.clientId,
        'client_name': order.clientName,
        'items_json':
            jsonEncode(order.items.map((e) => e.toJson()).toList()),
        'recipe_id': order.recipeId,
        'recipe_title': order.recipeTitle,
        'weight_grams': order.weightGrams,
        'price_cents': order.priceCents,
        'cost_cents': order.costCents,
        'prepayment_cents': order.prepaymentCents,
        'paid_cents': order.paidCents,
        'discount_cents': order.discountCents,
        'status': order.status.name,
        'due_date': order.dueDate,
        'delivery_address': order.deliveryAddress,
        'wishes': order.wishes,
        'allergens': order.allergens,
        'stock_deducted': order.stockDeducted ? 1 : 0,
        'favorite': order.favorite ? 1 : 0,
        'created_at': order.createdAt.isNotEmpty
            ? order.createdAt
            : DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await _db.update(
      'orders',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<void> deleteOrder(String orderId) async {
    await _db.delete('orders', where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> upsertWorkItem(WorkItem item) async {
    await _db.insert(
      'work_items',
      {
        'id': item.id,
        'type': item.type.name,
        'source_id': item.sourceId,
        'title': item.title,
        'due_date': item.dueDate,
        'priority': item.priority.name,
        'stage': item.stage.name,
        'tags_json': jsonEncode(item.tags),
        'recurrence': item.recurrence.name,
        'series_id': item.seriesId,
        'occurrence_index': item.occurrenceIndex,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteWorkItem(String id) async {
    await _db.delete('work_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertInventoryItem(InventoryItem item) async {
    await _db.insert(
      'inventory_items',
      {
        'id': item.id,
        'name': item.name,
        'kind': item.kind.name,
        'category': item.category,
        'unit': item.unit,
        'qty_on_hand': item.qtyOnHand,
        'min_qty': item.minQty,
        'avg_cost_cents': item.avgCostCents,
        'density': item.density,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertSupplier(Supplier supplier) async {
    await _db.insert(
      'suppliers',
      {
        'id': supplier.id,
        'name': supplier.name,
        'contact_name': supplier.contactName,
        'phone': supplier.phone,
        'category': supplier.category,
        'debt_cents': supplier.debtCents,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertPurchase(Purchase p) async {
    await _db.insert(
      'purchases',
      {
        'id': p.id,
        'supplier_id': p.supplierId,
        'supplier_name': p.supplierName,
        'item_id': p.itemId,
        'item_name': p.itemName,
        'qty': p.qty,
        'unit': p.unit,
        'price_cents': p.priceCents,
        'delivery_cents': p.deliveryCents,
        'expected_date': p.expectedDate,
        'expires_at': p.expiresAt,
        'status': p.status.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertAccount(Account acc) async {
    await _db.insert(
      'accounts',
      {
        'id': acc.id,
        'name': acc.name,
        'kind': acc.kind.name,
        'balance_cents': acc.balanceCents,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> addTimeEntry(TimeEntry entry) async {
    await _db.insert('time_entries', {
      'id': entry.id,
      'date': entry.date,
      'minutes': entry.minutes,
      'note': entry.note,
    });
  }

  // ==================== Atomic Business Transactions ====================

  Future<void> addStockLotReceipt({
    required String itemId,
    required double qty,
    required String unit,
    required int totalCostCents,
    String? expiresAt,
    String? reason,
  }) async {
    if (qty <= 0) {
      throw StateError('Количество прихода должно быть больше нуля.');
    }
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_items',
        where: 'id = ?',
        whereArgs: [itemId],
      );
      if (rows.isEmpty) {
        throw StateError('Позиция кладовой не найдена.');
      }
      final item = _inventoryFromRow(rows.first);
      final converted = convertQtyWithDensity(
        qty,
        unit,
        item.unit,
        densityGPerMl: item.density,
      );
      if (converted == null || converted <= 0) {
        throw StateError(
          'Единица "$unit" несовместима с "${item.unit}" для "${item.name}" (проверьте плотность).',
        );
      }

      final newQty = item.qtyOnHand + converted;
      final prevValue = (item.qtyOnHand * item.avgCostCents).round();
      final newAvg = newQty > 0
          ? ((prevValue + totalCostCents) / newQty).round()
          : item.avgCostCents;
      final unitCost = (totalCostCents / converted).round();
      final nowIso = DateTime.now().toIso8601String();
      final lotId = newId('lot');
      final code =
          'LOT-${todayIsoDate().replaceAll('-', '')}-${lotId.substring(lotId.length - 4).toUpperCase()}';

      await txn.insert('stock_lots', {
        'id': lotId,
        'item_id': item.id,
        'item_name': item.name,
        'lot_code': code,
        'unit': item.unit,
        'initial_qty': converted,
        'remaining_qty': converted,
        'unit_cost_cents': unitCost,
        'expires_at': (expiresAt != null && expiresAt.isNotEmpty) ? expiresAt : null,
        'status': StockLotStatus.active.name,
        'created_at': nowIso,
      });

      await txn.insert('stock_movements', {
        'id': newId('mv'),
        'kind': MovementKind.receipt.name,
        'item_id': item.id,
        'item_name': item.name,
        'lot_id': lotId,
        'qty': converted,
        'unit': item.unit,
        'total_cents': totalCostCents,
        'reason': reason ?? 'Ручной приход партии',
        'occurred_at': nowIso,
      });

      await txn.update(
        'inventory_items',
        {
          'qty_on_hand': newQty,
          'avg_cost_cents': newAvg,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
    });
  }

  Future<void> receivePurchase({
    required String purchaseId,
    String? accountId,
    bool payFromAccount = false,
  }) async {
    await _db.transaction((txn) async {
      final pRows = await txn.query(
        'purchases',
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      if (pRows.isEmpty) {
        throw StateError('Закупка не найдена.');
      }
      final purchase = _purchaseFromRow(pRows.first);
      if (purchase.status == PurchaseStatus.received) {
        throw StateError('Эта закупка уже оприходована.');
      }
      if (purchase.status == PurchaseStatus.cancelled) {
        throw StateError('Нельзя оприходовать отменённую закупку.');
      }
      if (purchase.qty <= 0) {
        throw StateError('Количество в закупке должно быть больше нуля.');
      }

      InventoryItem? item;
      if (purchase.itemId != null && purchase.itemId!.isNotEmpty) {
        final iRows = await txn.query(
          'inventory_items',
          where: 'id = ?',
          whereArgs: [purchase.itemId],
        );
        if (iRows.isNotEmpty) item = _inventoryFromRow(iRows.first);
      }
      if (item == null) {
        final allItems = await txn.query('inventory_items');
        for (final row in allItems) {
          final parsed = _inventoryFromRow(row);
          if (parsed.name.trim().toLowerCase() ==
              purchase.itemName.trim().toLowerCase()) {
            item = parsed;
            break;
          }
        }
      }
      if (item == null) {
        final newItemId = newId('inv');
        item = InventoryItem(
          id: newItemId,
          name: purchase.itemName,
          kind: InventoryKind.raw,
          unit: purchase.unit,
          qtyOnHand: 0,
          minQty: 0,
          avgCostCents: 0,
        );
        await txn.insert('inventory_items', {
          'id': item.id,
          'name': item.name,
          'kind': item.kind.name,
          'category': null,
          'unit': item.unit,
          'qty_on_hand': 0.0,
          'min_qty': 0.0,
          'avg_cost_cents': 0,
          'density': null,
        });
      }

      final addedQty = convertQtyWithDensity(
        purchase.qty,
        purchase.unit,
        item.unit,
        densityGPerMl: item.density,
      );
      if (addedQty == null || addedQty <= 0) {
        throw StateError(
          'Единица закупки "${purchase.unit}" несовместима со складом "${item.unit}".',
        );
      }

      final totalCostCents = purchase.priceCents + purchase.deliveryCents;
      final newQty = item.qtyOnHand + addedQty;
      final oldValue = (item.qtyOnHand * item.avgCostCents).round();
      final newAvg = newQty > 0
          ? ((oldValue + totalCostCents) / newQty).round()
          : item.avgCostCents;
      final lotUnitCost = (totalCostCents / addedQty).round();
      final nowIso = DateTime.now().toIso8601String();
      final lotId = newId('lot');
      final code =
          'PUR-${todayIsoDate().replaceAll('-', '')}-${lotId.substring(lotId.length - 4).toUpperCase()}';

      await txn.insert('stock_lots', {
        'id': lotId,
        'item_id': item.id,
        'item_name': item.name,
        'lot_code': code,
        'unit': item.unit,
        'initial_qty': addedQty,
        'remaining_qty': addedQty,
        'unit_cost_cents': lotUnitCost,
        'expires_at': purchase.expiresAt,
        'status': StockLotStatus.active.name,
        'created_at': nowIso,
      });

      await txn.insert('stock_movements', {
        'id': newId('mv'),
        'kind': MovementKind.receipt.name,
        'item_id': item.id,
        'item_name': item.name,
        'lot_id': lotId,
        'qty': addedQty,
        'unit': item.unit,
        'total_cents': totalCostCents,
        'reason': 'Закупка у ${purchase.supplierName}',
        'occurred_at': nowIso,
      });

      await txn.update(
        'inventory_items',
        {
          'qty_on_hand': newQty,
          'avg_cost_cents': newAvg,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );

      await txn.update(
        'purchases',
        {
          'status': PurchaseStatus.received.name,
          'item_id': item.id,
        },
        where: 'id = ?',
        whereArgs: [purchase.id],
      );

      if (payFromAccount && accountId != null && totalCostCents > 0) {
        final accRows = await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [accountId],
        );
        if (accRows.isEmpty) {
          throw StateError('Счёт оплаты закупки не найден.');
        }
        final accRow = accRows.first;
        final accName = accRow['name'] as String;
        final prevBal = (accRow['balance_cents'] as num?)?.toInt() ?? 0;

        await txn.update(
          'accounts',
          {'balance_cents': prevBal - totalCostCents},
          where: 'id = ?',
          whereArgs: [accountId],
        );

        await txn.insert('money_transactions', {
          'id': newId('tx'),
          'kind': TransactionKind.expense.name,
          'category': 'Закупка сырья',
          'amount_cents': totalCostCents,
          'account_id': accountId,
          'account_name': accName,
          'order_id': null,
          'reverses_id': null,
          'note': '${purchase.itemName} (${purchase.supplierName})',
          'occurred_at': nowIso,
        });
      }
    });
  }

  Future<void> writeOffStockLot({
    required String lotId,
    required double qty,
    required String reason,
    bool markExpired = false,
  }) async {
    if (qty <= 0) {
      throw StateError('Количество списания должно быть больше нуля.');
    }
    await _db.transaction((txn) async {
      final lotRows = await txn.query(
        'stock_lots',
        where: 'id = ?',
        whereArgs: [lotId],
      );
      if (lotRows.isEmpty) throw StateError('Партия не найдена.');
      final lot = _lotFromRow(lotRows.first);
      if (qty > lot.remainingQty + 1e-6) {
        throw StateError(
          'Нельзя списать больше остатка партии (${formatQty(lot.remainingQty, lot.unit)}).',
        );
      }

      final newRem = (lot.remainingQty - qty) <= 1e-6 ? 0.0 : lot.remainingQty - qty;
      final newStatus = markExpired
          ? StockLotStatus.expired.name
          : (newRem <= 1e-6 ? StockLotStatus.depleted.name : lot.status.name);
      final totalCents = (qty * lot.unitCostCents).round();
      final nowIso = DateTime.now().toIso8601String();

      await txn.update(
        'stock_lots',
        {
          'remaining_qty': newRem,
          'status': newStatus,
        },
        where: 'id = ?',
        whereArgs: [lot.id],
      );

      final itemRows = await txn.query(
        'inventory_items',
        where: 'id = ?',
        whereArgs: [lot.itemId],
      );
      if (itemRows.isNotEmpty) {
        final item = _inventoryFromRow(itemRows.first);
        final nextQty = (item.qtyOnHand - qty) <= 1e-6 ? 0.0 : item.qtyOnHand - qty;
        await txn.update(
          'inventory_items',
          {'qty_on_hand': nextQty},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }

      await txn.insert('stock_movements', {
        'id': newId('mv'),
        'kind': MovementKind.adjustment.name,
        'item_id': lot.itemId,
        'item_name': lot.itemName,
        'lot_id': lot.id,
        'qty': qty,
        'unit': lot.unit,
        'total_cents': totalCents,
        'reason': reason.trim().isEmpty
            ? (markExpired ? 'Списание просрочки' : 'Списание брака')
            : reason.trim(),
        'occurred_at': nowIso,
      });
    });
  }

  Future<void> reconcileInventoryItem({
    required String itemId,
    required double actualQty,
    String? reason,
    String? todayIso,
  }) async {
    if (actualQty < 0) {
      throw StateError('Фактический остаток не может быть отрицательным.');
    }
    final today = todayIso ?? todayIsoDate();
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_items',
        where: 'id = ?',
        whereArgs: [itemId],
      );
      if (rows.isEmpty) throw StateError('Позиция не найдена.');
      final item = _inventoryFromRow(rows.first);
      final delta = actualQty - item.qtyOnHand;
      if (delta.abs() <= 1e-6) return;

      final nowIso = DateTime.now().toIso8601String();
      if (delta > 0) {
        final lotId = newId('lot');
        await txn.insert('stock_lots', {
          'id': lotId,
          'item_id': item.id,
          'item_name': item.name,
          'lot_code': 'INV-${today.replaceAll('-', '')}',
          'unit': item.unit,
          'initial_qty': delta,
          'remaining_qty': delta,
          'unit_cost_cents': item.avgCostCents,
          'expires_at': null,
          'status': StockLotStatus.active.name,
          'created_at': nowIso,
        });
        await txn.insert('stock_movements', {
          'id': newId('mv'),
          'kind': MovementKind.adjustment.name,
          'item_id': item.id,
          'item_name': item.name,
          'lot_id': lotId,
          'qty': delta,
          'unit': item.unit,
          'total_cents': (delta * item.avgCostCents).round(),
          'reason': reason?.trim().isNotEmpty == true
              ? reason!.trim()
              : 'Инвентаризация (излишек)',
          'occurred_at': nowIso,
        });
        await txn.update(
          'inventory_items',
          {'qty_on_hand': actualQty},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      } else {
        // Reduce delta via FEFO lots (including any remaining active lots regardless of expiry for physical reconciliation)
        var remainingToReduce = -delta;
        final lots = await txn.query(
          'stock_lots',
          where: "item_id = ? AND status = 'active' AND remaining_qty > 0",
          whereArgs: [item.id],
          orderBy:
              "CASE WHEN expires_at IS NULL OR expires_at = '' THEN 1 ELSE 0 END ASC, expires_at ASC, created_at ASC",
        );
        for (final r in lots) {
          if (remainingToReduce <= 1e-6) break;
          final lot = _lotFromRow(r);
          final take = remainingToReduce < lot.remainingQty
              ? remainingToReduce
              : lot.remainingQty;
          final nextRem = (lot.remainingQty - take) <= 1e-6
              ? 0.0
              : lot.remainingQty - take;
          await txn.update(
            'stock_lots',
            {
              'remaining_qty': nextRem,
              'status': nextRem <= 1e-6 ? StockLotStatus.depleted.name : 'active',
            },
            where: 'id = ?',
            whereArgs: [lot.id],
          );
          await txn.insert('stock_movements', {
            'id': newId('mv'),
            'kind': MovementKind.adjustment.name,
            'item_id': item.id,
            'item_name': item.name,
            'lot_id': lot.id,
            'qty': take,
            'unit': item.unit,
            'total_cents': (take * lot.unitCostCents).round(),
            'reason': reason?.trim().isNotEmpty == true
                ? reason!.trim()
                : 'Инвентаризация (недостача)',
            'occurred_at': nowIso,
          });
          remainingToReduce -= take;
        }
        await txn.update(
          'inventory_items',
          {'qty_on_hand': actualQty},
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
    });
  }

  Future<int> _consumeItemFefoInTxn(
    Transaction txn, {
    required String itemId,
    required double qty,
    required String unit,
    required MovementKind movementKind,
    required String reason,
    required String todayIso,
  }) async {
    if (qty <= 0) return 0;
    final itemRows = await txn.query(
      'inventory_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (itemRows.isEmpty) {
      throw StateError('Позиция кладовой ($itemId) не найдена.');
    }
    final item = _inventoryFromRow(itemRows.first);
    final needQty = convertQtyWithDensity(
      qty,
      unit,
      item.unit,
      densityGPerMl: item.density,
    );
    if (needQty == null) {
      throw StateError(
        'Нельзя перевести ${formatQty(qty, unit)} в "${item.unit}" для "${item.name}". Укажите плотность.',
      );
    }

    final lotRows = await txn.query(
      'stock_lots',
      where: "item_id = ? AND status = 'active' AND remaining_qty > 0",
      whereArgs: [item.id],
      orderBy:
          "CASE WHEN expires_at IS NULL OR expires_at = '' THEN 1 ELSE 0 END ASC, expires_at ASC, created_at ASC",
    );

    final validLots = <StockLot>[];
    var expiredCount = 0;
    var availableValid = 0.0;
    for (final row in lotRows) {
      final lot = _lotFromRow(row);
      final isExpired = lot.expiresAt != null &&
          lot.expiresAt!.isNotEmpty &&
          lot.expiresAt!.compareTo(todayIso) < 0;
      if (isExpired) {
        expiredCount++;
        continue;
      }
      validLots.add(lot);
      availableValid += lot.remainingQty;
    }

    if (availableValid + 1e-6 < needQty) {
      final expHint = expiredCount > 0
          ? ' (просроченные партии исключены по FEFO: $expiredCount шт.)'
          : '';
      throw StateError(
        'Недостаточно "${item.name}": нужно ${formatQty(needQty, item.unit)}, доступно ${formatQty(availableValid, item.unit)}$expHint.',
      );
    }

    var toConsume = needQty;
    var consumedCostCents = 0;
    final nowIso = DateTime.now().toIso8601String();

    for (final lot in validLots) {
      if (toConsume <= 1e-6) break;
      final take = toConsume < lot.remainingQty ? toConsume : lot.remainingQty;
      final nextRem =
          (lot.remainingQty - take) <= 1e-6 ? 0.0 : lot.remainingQty - take;
      final costShare = (take * lot.unitCostCents).round();
      consumedCostCents += costShare;

      await txn.update(
        'stock_lots',
        {
          'remaining_qty': nextRem,
          'status':
              nextRem <= 1e-6 ? StockLotStatus.depleted.name : StockLotStatus.active.name,
        },
        where: 'id = ?',
        whereArgs: [lot.id],
      );

      await txn.insert('stock_movements', {
        'id': newId('mv'),
        'kind': movementKind.name,
        'item_id': item.id,
        'item_name': item.name,
        'lot_id': lot.id,
        'qty': take,
        'unit': item.unit,
        'total_cents': costShare,
        'reason': reason,
        'occurred_at': nowIso,
      });

      toConsume -= take;
    }

    final nextOnHand =
        (item.qtyOnHand - needQty) <= 1e-6 ? 0.0 : item.qtyOnHand - needQty;
    await txn.update(
      'inventory_items',
      {'qty_on_hand': nextOnHand},
      where: 'id = ?',
      whereArgs: [item.id],
    );

    return consumedCostCents;
  }

  Future<void> _collectRecipeNeeds(
    Transaction txn, {
    required Recipe recipe,
    required double scale,
    required Map<String, ({double qty, String unit})> outNeeds,
    required Set<String> visitedRecipes,
  }) async {
    if (!visitedRecipes.add(recipe.id)) return;
    for (final line in recipe.ingredients) {
      final lineQty = effectiveQuantity(line.qty * scale, line.lossPercent) ??
          (line.qty * scale);
      if (lineQty <= 0) continue;

      if (line.itemId != null && line.itemId!.isNotEmpty) {
        final prev = outNeeds[line.itemId!];
        if (prev == null) {
          outNeeds[line.itemId!] = (qty: lineQty, unit: line.unit);
        } else if (prev.unit == line.unit) {
          outNeeds[line.itemId!] = (qty: prev.qty + lineQty, unit: prev.unit);
        } else {
          // Convert to previous unit if possible; otherwise check DB item unit
          final conv = convertQty(lineQty, line.unit, prev.unit);
          if (conv != null) {
            outNeeds[line.itemId!] = (qty: prev.qty + conv, unit: prev.unit);
          } else {
            outNeeds[line.itemId!] = (qty: prev.qty + lineQty, unit: prev.unit);
          }
        }
      } else if (line.subRecipeId != null && line.subRecipeId!.isNotEmpty) {
        final subRows = await txn.query(
          'recipes',
          where: 'id = ?',
          whereArgs: [line.subRecipeId],
        );
        if (subRows.isEmpty) continue;
        final sub = _recipeFromRow(subRows.first);
        // Check if semi inventory exists by exact name & has stock
        final invRows = await txn.query('inventory_items');
        InventoryItem? semiInv;
        for (final r in invRows) {
          final parsed = _inventoryFromRow(r);
          if ((parsed.kind == InventoryKind.semi ||
                  parsed.kind == InventoryKind.finished) &&
              parsed.name.trim().toLowerCase() ==
                  sub.title.trim().toLowerCase()) {
            semiInv = parsed;
            break;
          }
        }
        final needGrams = convertQty(lineQty, line.unit, 'г') ?? lineQty;
        if (semiInv != null && semiInv.qtyOnHand > 0) {
          final reqInSemiUnit =
              convertQtyWithDensity(needGrams, 'г', semiInv.unit, densityGPerMl: semiInv.density);
          if (reqInSemiUnit != null && semiInv.qtyOnHand + 1e-6 >= reqInSemiUnit) {
            final prev = outNeeds[semiInv.id];
            outNeeds[semiInv.id] = prev == null
                ? (qty: reqInSemiUnit, unit: semiInv.unit)
                : (qty: prev.qty + reqInSemiUnit, unit: semiInv.unit);
            continue;
          }
        }
        final subScale = sub.yieldGrams > 0 ? needGrams / sub.yieldGrams : 1.0;
        await _collectRecipeNeeds(
          txn,
          recipe: sub,
          scale: subScale,
          outNeeds: outNeeds,
          visitedRecipes: visitedRecipes,
        );
      }
    }
  }

  Future<void> deductOrderStockFefo(
    String orderId, {
    String? todayIso,
  }) async {
    final today = todayIso ?? todayIsoDate();
    await _db.transaction((txn) async {
      final ordRows = await txn.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      );
      if (ordRows.isEmpty) throw StateError('Заказ не найден.');
      final order = _orderFromRow(ordRows.first);
      if (order.stockDeducted) {
        throw StateError('Сырьё/товар по заказу ${order.orderNumber} уже списаны.');
      }

      final items = getOrderItemsNormalized(order);
      final allRecipesRows = await txn.query('recipes');
      final recipesById = {
        for (final r in allRecipesRows) r['id'] as String: _recipeFromRow(r),
      };
      final allInvRows = await txn.query('inventory_items');
      final allInv = allInvRows.map(_inventoryFromRow).toList();

      final rawNeeds = <String, ({double qty, String unit})>{};
      final finishedNeeds = <String, ({double qty, String unit})>{};

      for (final line in items) {
        final recipe = line.recipeId.isNotEmpty ? recipesById[line.recipeId] : null;
        final lookupName = (recipe?.title ?? line.recipeTitle).trim().toLowerCase();

        // Check if finished product already exists in stock with sufficient qty
        InventoryItem? finishedInv;
        for (final inv in allInv) {
          if (inv.kind == InventoryKind.finished &&
              inv.name.trim().toLowerCase() == lookupName) {
            finishedInv = inv;
            break;
          }
        }

        var usedFinished = false;
        if (finishedInv != null && finishedInv.qtyOnHand > 0) {
          final qtyNeeded = unitFamily(finishedInv.unit) == UnitFamily.mass &&
                  line.weightGrams > 0
              ? convertQty(line.weightGrams * line.qty, 'г', finishedInv.unit)
              : (unitFamily(finishedInv.unit) == UnitFamily.count
                  ? line.qty.toDouble()
                  : null);
          if (qtyNeeded != null &&
              qtyNeeded > 0 &&
              finishedInv.qtyOnHand + 1e-6 >= qtyNeeded) {
            final prev = finishedNeeds[finishedInv.id];
            finishedNeeds[finishedInv.id] = prev == null
                ? (qty: qtyNeeded, unit: finishedInv.unit)
                : (qty: prev.qty + qtyNeeded, unit: finishedInv.unit);
            usedFinished = true;
          }
        }

        if (!usedFinished) {
          if (recipe == null) {
            throw StateError(
              'Для позиции "${line.recipeTitle}" не найден рецепт и нет готового изделия на складе.',
            );
          }
          final scale = (line.weightGrams > 0 && recipe.yieldGrams > 0)
              ? (line.weightGrams * line.qty) / recipe.yieldGrams
              : line.qty.toDouble();
          await _collectRecipeNeeds(
            txn,
            recipe: recipe,
            scale: scale,
            outNeeds: rawNeeds,
            visitedRecipes: <String>{},
          );
        }
      }

      if (finishedNeeds.isEmpty && rawNeeds.isEmpty) {
        throw StateError(
          'В рецептах заказа нет позиций, привязанных к кладовой. Привяжите ингредиенты в рецепте или оприходуйте готовые изделия.',
        );
      }

      for (final entry in finishedNeeds.entries) {
        await _consumeItemFefoInTxn(
          txn,
          itemId: entry.key,
          qty: entry.value.qty,
          unit: entry.value.unit,
          movementKind: MovementKind.sale,
          reason: 'Выдача готового по заказу ${order.orderNumber}',
          todayIso: today,
        );
      }
      for (final entry in rawNeeds.entries) {
        await _consumeItemFefoInTxn(
          txn,
          itemId: entry.key,
          qty: entry.value.qty,
          unit: entry.value.unit,
          movementKind: MovementKind.issue,
          reason: 'Списание на заказ ${order.orderNumber}',
          todayIso: today,
        );
      }

      await txn.update(
        'orders',
        {'stock_deducted': 1},
        where: 'id = ?',
        whereArgs: [order.id],
      );
    });
  }

  Future<ProductionRun> completeProductionRun({
    required String recipeId,
    required double plannedGrams,
    required double actualGrams,
    String? expiresAt,
    String? todayIso,
  }) async {
    if (plannedGrams <= 0 || actualGrams <= 0) {
      throw StateError('План и фактический выход должны быть больше нуля.');
    }
    final today = todayIso ?? todayIsoDate();

    return _db.transaction((txn) async {
      final recRows = await txn.query(
        'recipes',
        where: 'id = ?',
        whereArgs: [recipeId],
      );
      if (recRows.isEmpty) throw StateError('Рецепт не найден.');
      final recipe = _recipeFromRow(recRows.first);

      final scale = recipe.yieldGrams > 0 ? plannedGrams / recipe.yieldGrams : 1.0;
      final needs = <String, ({double qty, String unit})>{};
      await _collectRecipeNeeds(
        txn,
        recipe: recipe,
        scale: scale,
        outNeeds: needs,
        visitedRecipes: <String>{},
      );
      if (needs.isEmpty) {
        throw StateError(
          'В рецепте "${recipe.title}" нет ингредиентов, привязанных к кладовой.',
        );
      }

      var totalMaterialsCost = 0;
      for (final entry in needs.entries) {
        totalMaterialsCost += await _consumeItemFefoInTxn(
          txn,
          itemId: entry.key,
          qty: entry.value.qty,
          unit: entry.value.unit,
          movementKind: MovementKind.productionOut,
          reason: 'Выпуск "${recipe.title}" (${plannedGrams.round()} г)',
          todayIso: today,
        );
      }

      final targetKind = recipe.category.toLowerCase().contains('полуфабр')
          ? InventoryKind.semi
          : InventoryKind.finished;

      final allInv = await txn.query('inventory_items');
      InventoryItem? outItem;
      for (final row in allInv) {
        final parsed = _inventoryFromRow(row);
        if (parsed.kind == targetKind &&
            parsed.name.trim().toLowerCase() == recipe.title.trim().toLowerCase()) {
          outItem = parsed;
          break;
        }
      }

      final nowIso = DateTime.now().toIso8601String();
      if (outItem == null) {
        outItem = InventoryItem(
          id: newId('inv'),
          name: recipe.title,
          kind: targetKind,
          category: recipe.category,
          unit: 'кг',
          qtyOnHand: 0,
          minQty: 0,
          avgCostCents: 0,
        );
        await txn.insert('inventory_items', {
          'id': outItem.id,
          'name': outItem.name,
          'kind': outItem.kind.name,
          'category': outItem.category,
          'unit': outItem.unit,
          'qty_on_hand': 0.0,
          'min_qty': 0.0,
          'avg_cost_cents': 0,
          'density': null,
        });
      }

      final addedInItemUnit = convertQtyWithDensity(
            actualGrams,
            'г',
            outItem.unit,
            densityGPerMl: outItem.density,
          ) ??
          (actualGrams / 1000.0);

      final lotUnitCost = addedInItemUnit > 0
          ? (totalMaterialsCost / addedInItemUnit).round()
          : totalMaterialsCost;
      final newQty = outItem.qtyOnHand + addedInItemUnit;
      final prevVal = (outItem.qtyOnHand * outItem.avgCostCents).round();
      final newAvg = newQty > 0
          ? ((prevVal + totalMaterialsCost) / newQty).round()
          : lotUnitCost;

      final lotId = newId('lot');
      final runId = newId('prod');
      final lotCode =
          'PRD-${today.replaceAll('-', '')}-${runId.substring(runId.length - 4).toUpperCase()}';

      await txn.insert('stock_lots', {
        'id': lotId,
        'item_id': outItem.id,
        'item_name': outItem.name,
        'lot_code': lotCode,
        'unit': outItem.unit,
        'initial_qty': addedInItemUnit,
        'remaining_qty': addedInItemUnit,
        'unit_cost_cents': lotUnitCost,
        'expires_at': (expiresAt != null && expiresAt.isNotEmpty) ? expiresAt : null,
        'status': StockLotStatus.active.name,
        'created_at': nowIso,
      });

      await txn.insert('stock_movements', {
        'id': newId('mv'),
        'kind': MovementKind.productionIn.name,
        'item_id': outItem.id,
        'item_name': outItem.name,
        'lot_id': lotId,
        'qty': addedInItemUnit,
        'unit': outItem.unit,
        'total_cents': totalMaterialsCost,
        'reason': 'Выпуск $lotCode (${actualGrams.round()} г)',
        'occurred_at': nowIso,
      });

      await txn.update(
        'inventory_items',
        {
          'qty_on_hand': newQty,
          'avg_cost_cents': newAvg,
        },
        where: 'id = ?',
        whereArgs: [outItem.id],
      );

      final run = ProductionRun(
        id: runId,
        recipeId: recipe.id,
        recipeTitle: recipe.title,
        plannedGrams: plannedGrams,
        actualGrams: actualGrams,
        totalCostCents: totalMaterialsCost,
        outputLotId: lotId,
        status: ProductionStatus.completed,
        createdAt: nowIso,
      );

      await txn.insert('production_runs', {
        'id': run.id,
        'recipe_id': run.recipeId,
        'recipe_title': run.recipeTitle,
        'planned_grams': run.plannedGrams,
        'actual_grams': run.actualGrams,
        'total_cost_cents': run.totalCostCents,
        'output_lot_id': run.outputLotId,
        'status': run.status.name,
        'created_at': run.createdAt,
      });

      return run;
    });
  }

  Future<void> reverseProductionRun(String runId) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'production_runs',
        where: 'id = ?',
        whereArgs: [runId],
      );
      if (rows.isEmpty) throw StateError('Выпуск не найден.');
      final run = _productionFromRow(rows.first);
      if (run.status == ProductionStatus.reversed) {
        throw StateError('Этот выпуск уже сторнирован.');
      }

      if (run.outputLotId != null) {
        final lotRows = await txn.query(
          'stock_lots',
          where: 'id = ?',
          whereArgs: [run.outputLotId],
        );
        if (lotRows.isNotEmpty) {
          final outLot = _lotFromRow(lotRows.first);
          if ((outLot.remainingQty - outLot.initialQty).abs() > 1e-4) {
            throw StateError(
              'Нельзя отменить выпуск: готовая партия ${outLot.lotCode} уже частично израсходована или продана.',
            );
          }

          await txn.update(
            'stock_lots',
            {
              'remaining_qty': 0.0,
              'status': StockLotStatus.depleted.name,
            },
            where: 'id = ?',
            whereArgs: [outLot.id],
          );

          final itemRows = await txn.query(
            'inventory_items',
            where: 'id = ?',
            whereArgs: [outLot.itemId],
          );
          if (itemRows.isNotEmpty) {
            final item = _inventoryFromRow(itemRows.first);
            final nextQty = (item.qtyOnHand - outLot.initialQty) <= 1e-6
                ? 0.0
                : item.qtyOnHand - outLot.initialQty;
            await txn.update(
              'inventory_items',
              {'qty_on_hand': nextQty},
              where: 'id = ?',
              whereArgs: [item.id],
            );
          }

          await txn.insert('stock_movements', {
            'id': newId('mv'),
            'kind': MovementKind.adjustment.name,
            'item_id': outLot.itemId,
            'item_name': outLot.itemName,
            'lot_id': outLot.id,
            'qty': outLot.initialQty,
            'unit': outLot.unit,
            'total_cents': run.totalCostCents,
            'reason': 'Сторно выпуска "${run.recipeTitle}"',
            'occurred_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // Restore consumed raw lots using recorded production_out movements matching recipe & timestamp window
      if (run.recipeId != null) {
        final mvs = await txn.query(
          'stock_movements',
          where: "kind = ? AND reason LIKE ? AND occurred_at >= ?",
          whereArgs: [
            MovementKind.productionOut.name,
            'Выпуск "${run.recipeTitle}"%',
            run.createdAt.substring(0, run.createdAt.length >= 16 ? 16 : run.createdAt.length),
          ],
        );
        for (final row in mvs) {
          final mv = _movementFromRow(row);
          if (mv.lotId != null) {
            final lRows = await txn.query(
              'stock_lots',
              where: 'id = ?',
              whereArgs: [mv.lotId],
            );
            if (lRows.isNotEmpty) {
              final l = _lotFromRow(lRows.first);
              await txn.update(
                'stock_lots',
                {
                  'remaining_qty': l.remainingQty + mv.qty,
                  'status': StockLotStatus.active.name,
                },
                where: 'id = ?',
                whereArgs: [l.id],
              );
            }
          }
          final iRows = await txn.query(
            'inventory_items',
            where: 'id = ?',
            whereArgs: [mv.itemId],
          );
          if (iRows.isNotEmpty) {
            final item = _inventoryFromRow(iRows.first);
            await txn.update(
              'inventory_items',
              {'qty_on_hand': item.qtyOnHand + mv.qty},
              where: 'id = ?',
              whereArgs: [item.id],
            );
          }
          await txn.insert('stock_movements', {
            'id': newId('mv'),
            'kind': MovementKind.adjustment.name,
            'item_id': mv.itemId,
            'item_name': mv.itemName,
            'lot_id': mv.lotId,
            'qty': mv.qty,
            'unit': mv.unit,
            'total_cents': mv.totalCents,
            'reason': 'Возврат сырья при сторно выпуска "${run.recipeTitle}"',
            'occurred_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await txn.update(
        'production_runs',
        {'status': ProductionStatus.reversed.name},
        where: 'id = ?',
        whereArgs: [run.id],
      );
    });
  }

  // ==================== Order Payments & Finance ====================

  Future<void> recordOrderPayment({
    required String orderId,
    required String accountId,
    required int amountCents,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw StateError('Сумма оплаты должна быть больше нуля.');
    }
    await _db.transaction((txn) async {
      final ordRows =
          await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (ordRows.isEmpty) throw StateError('Заказ не найден.');
      final order = _orderFromRow(ordRows.first);

      final accRows =
          await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
      if (accRows.isEmpty) throw StateError('Счёт не найден.');
      final accRow = accRows.first;
      final accName = accRow['name'] as String;
      final prevBal = (accRow['balance_cents'] as num?)?.toInt() ?? 0;

      final nextPaid = order.paidCents + amountCents;
      final nextPrepay = order.paidCents == 0 && amountCents < order.priceCents
          ? amountCents
          : order.prepaymentCents;

      await txn.update(
        'orders',
        {
          'paid_cents': nextPaid,
          'prepayment_cents': nextPrepay,
        },
        where: 'id = ?',
        whereArgs: [order.id],
      );

      await txn.update(
        'accounts',
        {'balance_cents': prevBal + amountCents},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': TransactionKind.income.name,
        'category': nextPaid < order.priceCents ? 'Предоплата' : 'Оплата заказа',
        'amount_cents': amountCents,
        'account_id': accountId,
        'account_name': accName,
        'order_id': order.id,
        'reverses_id': null,
        'note': note ?? '${order.orderNumber} · ${order.clientName}',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> payOrderWithDeposit({
    required String orderId,
    int? customAmountCents,
  }) async {
    await _db.transaction((txn) async {
      final ordRows =
          await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (ordRows.isEmpty) throw StateError('Заказ не найден.');
      final order = _orderFromRow(ordRows.first);
      if (order.clientId == null || order.clientId!.isEmpty) {
        throw StateError('К заказу не привязана карточка клиента.');
      }

      final cRows = await txn
          .query('clients', where: 'id = ?', whereArgs: [order.clientId]);
      if (cRows.isEmpty) throw StateError('Клиент не найден.');
      final client = _clientFromRow(cRows.first);
      if (client.depositCents <= 0) {
        throw StateError('У клиента нет доступного депозита.');
      }
      final due = order.balanceDueCents;
      if (due <= 0) {
        throw StateError('Заказ уже полностью оплачен.');
      }
      final apply = customAmountCents != null
          ? customAmountCents.clamp(0, due)
          : (client.depositCents < due ? client.depositCents : due);
      if (apply <= 0 || apply > client.depositCents) {
        throw StateError('Недостаточно депозита для зачёта.');
      }

      await txn.update(
        'clients',
        {'deposit_cents': client.depositCents - apply},
        where: 'id = ?',
        whereArgs: [client.id],
      );
      await txn.update(
        'orders',
        {'paid_cents': order.paidCents + apply},
        where: 'id = ?',
        whereArgs: [order.id],
      );
    });
  }

  Future<void> refundOrderPayment({
    required String orderId,
    required String accountId,
    required int amountCents,
    String? reason,
  }) async {
    if (amountCents <= 0) {
      throw StateError('Сумма возврата должна быть больше нуля.');
    }
    await _db.transaction((txn) async {
      final ordRows =
          await txn.query('orders', where: 'id = ?', whereArgs: [orderId]);
      if (ordRows.isEmpty) throw StateError('Заказ не найден.');
      final order = _orderFromRow(ordRows.first);
      if (amountCents > order.paidCents) {
        throw StateError('Нельзя вернуть больше оплаченной суммы.');
      }

      final accRows =
          await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
      if (accRows.isEmpty) throw StateError('Счёт возврата не найден.');
      final accRow = accRows.first;
      final accName = accRow['name'] as String;
      final prevBal = (accRow['balance_cents'] as num?)?.toInt() ?? 0;

      await txn.update(
        'orders',
        {'paid_cents': order.paidCents - amountCents},
        where: 'id = ?',
        whereArgs: [order.id],
      );

      await txn.update(
        'accounts',
        {'balance_cents': prevBal - amountCents},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': TransactionKind.expense.name,
        'category': 'Возврат клиенту',
        'amount_cents': amountCents,
        'account_id': accountId,
        'account_name': accName,
        'order_id': order.id,
        'reverses_id': null,
        'note': reason?.trim().isNotEmpty == true
            ? reason!.trim()
            : 'Возврат по заказу ${order.orderNumber}',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> topUpClientDeposit({
    required String clientId,
    required String accountId,
    required int amountCents,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw StateError('Сумма пополнения депозита должна быть больше нуля.');
    }
    await _db.transaction((txn) async {
      final cRows =
          await txn.query('clients', where: 'id = ?', whereArgs: [clientId]);
      if (cRows.isEmpty) throw StateError('Клиент не найден.');
      final client = _clientFromRow(cRows.first);

      final accRows =
          await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
      if (accRows.isEmpty) throw StateError('Счёт не найден.');
      final accRow = accRows.first;
      final accName = accRow['name'] as String;
      final prevBal = (accRow['balance_cents'] as num?)?.toInt() ?? 0;

      await txn.update(
        'clients',
        {'deposit_cents': client.depositCents + amountCents},
        where: 'id = ?',
        whereArgs: [client.id],
      );

      await txn.update(
        'accounts',
        {'balance_cents': prevBal + amountCents},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': TransactionKind.income.name,
        'category': 'Пополнение депозита',
        'amount_cents': amountCents,
        'account_id': accountId,
        'account_name': accName,
        'order_id': null,
        'reverses_id': null,
        'note': note ?? 'Депозит клиента ${client.name}',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> addMoneyTransaction({
    required TransactionKind kind,
    required String category,
    required int amountCents,
    required String accountId,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw StateError('Сумма операции должна быть больше нуля.');
    }
    if (kind != TransactionKind.income && kind != TransactionKind.expense) {
      throw StateError('Используйте отдельный перевод или сторно.');
    }
    await _db.transaction((txn) async {
      final accRows =
          await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
      if (accRows.isEmpty) throw StateError('Счёт не найден.');
      final accRow = accRows.first;
      final accName = accRow['name'] as String;
      final prevBal = (accRow['balance_cents'] as num?)?.toInt() ?? 0;
      final delta = kind == TransactionKind.income ? amountCents : -amountCents;

      await txn.update(
        'accounts',
        {'balance_cents': prevBal + delta},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': kind.name,
        'category': category,
        'amount_cents': amountCents,
        'account_id': accountId,
        'account_name': accName,
        'order_id': null,
        'reverses_id': null,
        'note': note,
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
    String? note,
  }) async {
    if (amountCents <= 0) {
      throw StateError('Сумма перевода должна быть больше нуля.');
    }
    if (fromAccountId == toAccountId) {
      throw StateError('Выберите разные счета для перевода.');
    }
    await _db.transaction((txn) async {
      final fromRows = await txn
          .query('accounts', where: 'id = ?', whereArgs: [fromAccountId]);
      final toRows = await txn
          .query('accounts', where: 'id = ?', whereArgs: [toAccountId]);
      if (fromRows.isEmpty || toRows.isEmpty) {
        throw StateError('Счёт для перевода не найден.');
      }
      final fromName = fromRows.first['name'] as String;
      final toName = toRows.first['name'] as String;
      final fromBal = (fromRows.first['balance_cents'] as num?)?.toInt() ?? 0;
      final toBal = (toRows.first['balance_cents'] as num?)?.toInt() ?? 0;

      await txn.update(
        'accounts',
        {'balance_cents': fromBal - amountCents},
        where: 'id = ?',
        whereArgs: [fromAccountId],
      );
      await txn.update(
        'accounts',
        {'balance_cents': toBal + amountCents},
        where: 'id = ?',
        whereArgs: [toAccountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': TransactionKind.transfer.name,
        'category': 'Перевод между счетами',
        'amount_cents': amountCents,
        'account_id': fromAccountId,
        'account_name': '$fromName → $toName',
        'order_id': null,
        'reverses_id': null,
        'note': note,
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> reverseMoneyTransaction(String txId) async {
    await _db.transaction((txn) async {
      final txRows = await txn
          .query('money_transactions', where: 'id = ?', whereArgs: [txId]);
      if (txRows.isEmpty) throw StateError('Операция не найдена.');
      final orig = txRows.first;
      final origKind = _enumByName(
        TransactionKind.values,
        orig['kind'] as String?,
        TransactionKind.income,
      );
      if (origKind == TransactionKind.reversal ||
          origKind == TransactionKind.transfer) {
        throw StateError('Переводы и записи сторно не сторнируются.');
      }

      final existingRev = await txn.query(
        'money_transactions',
        where: 'reverses_id = ?',
        whereArgs: [txId],
      );
      if (existingRev.isNotEmpty) {
        throw StateError('Эта операция уже сторнирована.');
      }

      final accountId = orig['account_id'] as String;
      final amountCents = (orig['amount_cents'] as num).toInt();
      final accRows =
          await txn.query('accounts', where: 'id = ?', whereArgs: [accountId]);
      if (accRows.isEmpty) throw StateError('Счёт операции не найден.');
      final prevBal = (accRows.first['balance_cents'] as num?)?.toInt() ?? 0;
      final delta =
          origKind == TransactionKind.income ? -amountCents : amountCents;

      await txn.update(
        'accounts',
        {'balance_cents': prevBal + delta},
        where: 'id = ?',
        whereArgs: [accountId],
      );

      await txn.insert('money_transactions', {
        'id': newId('tx'),
        'kind': TransactionKind.reversal.name,
        'category': 'Сторно: ${orig['category']}',
        'amount_cents': amountCents,
        'account_id': accountId,
        'account_name': orig['account_name'] as String,
        'order_id': orig['order_id'] as String?,
        'reverses_id': txId,
        'note': 'Отмена операции $txId',
        'occurred_at': DateTime.now().toIso8601String(),
      });
    });
  }

  // ==================== Clean vs Demo Reset ====================

  Future<void> clearAllBusinessData({required bool isDemoMode}) async {
    await _db.transaction((txn) async {
      for (final table in [
        'stock_movements',
        'stock_lots',
        'production_runs',
        'purchases',
        'suppliers',
        'money_transactions',
        'work_items',
        'orders',
        'clients',
        'recipes',
        'inventory_items',
        'time_entries',
        'accounts',
      ]) {
        await txn.delete(table);
      }

      await txn.insert('accounts', {
        'id': 'acc_cash',
        'name': 'Наличные',
        'kind': AccountKind.cash.name,
        'balance_cents': 0,
      });

      await txn.update(
        'studio_profile',
        {'is_demo_mode': isDemoMode ? 1 : 0},
        where: 'id = 1',
      );
    });
  }

  Future<void> seedDemoData({String? todayIso}) async {
    final today = todayIso ?? todayIsoDate();
    final tomorrow = addDaysIso(today, 1);
    final in3Days = addDaysIso(today, 3);
    final in5Days = addDaysIso(today, 5);
    final in20Days = addDaysIso(today, 20);
    final yesterday = addDaysIso(today, -1);

    await clearAllBusinessData(isDemoMode: true);

    await _db.transaction((txn) async {
      await txn.delete('accounts');
      await txn.insert('accounts', {
        'id': 'acc_cash',
        'name': 'Наличные',
        'kind': AccountKind.cash.name,
        'balance_cents': 1850000,
      });
      await txn.insert('accounts', {
        'id': 'acc_card',
        'name': 'Карта мастера',
        'kind': AccountKind.card.name,
        'balance_cents': 6420000,
      });

      final invSeed = [
        InventoryItem(
          id: 'inv_cream',
          name: 'Сливки 33%',
          kind: InventoryKind.raw,
          category: 'Молочные',
          unit: 'мл',
          qtyOnHand: 3000,
          minQty: 1000,
          avgCostCents: 65, // 65 коп/мл = 650₽/л
          density: 1.01,
        ),
        InventoryItem(
          id: 'inv_choc',
          name: 'Тёмный шоколад 54%',
          kind: InventoryKind.raw,
          category: 'Шоколад',
          unit: 'г',
          qtyOnHand: 2200,
          minQty: 500,
          avgCostCents: 185, // 1850₽/кг
        ),
        InventoryItem(
          id: 'inv_mascarpone',
          name: 'Сыр маскарпоне',
          kind: InventoryKind.raw,
          category: 'Молочные',
          unit: 'г',
          qtyOnHand: 1500,
          minQty: 500,
          avgCostCents: 110, // 1100₽/кг
        ),
        InventoryItem(
          id: 'inv_pistachio',
          name: 'Фисташковая паста',
          kind: InventoryKind.raw,
          category: 'Пасты и орехи',
          unit: 'г',
          qtyOnHand: 350,
          minQty: 400, // triggers low stock alert intentionally for demo visibility
          avgCostCents: 420, // 4200₽/кг
        ),
        InventoryItem(
          id: 'inv_berry',
          name: 'Малина с/м',
          kind: InventoryKind.raw,
          category: 'Ягоды',
          unit: 'г',
          qtyOnHand: 1600,
          minQty: 500,
          avgCostCents: 95,
        ),
        InventoryItem(
          id: 'inv_box',
          name: 'Коробка для торта 25×25 с окном',
          kind: InventoryKind.packaging,
          category: 'Упаковка',
          unit: 'шт',
          qtyOnHand: 14,
          minQty: 5,
          avgCostCents: 18500, // 185₽/шт
        ),
      ];

      for (final item in invSeed) {
        await txn.insert('inventory_items', {
          'id': item.id,
          'name': item.name,
          'kind': item.kind.name,
          'category': item.category,
          'unit': item.unit,
          'qty_on_hand': item.qtyOnHand,
          'min_qty': item.minQty,
          'avg_cost_cents': item.avgCostCents,
          'density': item.density,
        });
        await txn.insert('stock_lots', {
          'id': 'lot_${item.id}',
          'item_id': item.id,
          'item_name': item.name,
          'lot_code': 'DEMO-${item.id.substring(4).toUpperCase()}',
          'unit': item.unit,
          'initial_qty': item.qtyOnHand,
          'remaining_qty': item.qtyOnHand,
          'unit_cost_cents': item.avgCostCents,
          'expires_at': item.id == 'inv_cream'
              ? in3Days
              : (item.id == 'inv_mascarpone' ? in5Days : in20Days),
          'status': StockLotStatus.active.name,
          'created_at': '${yesterday}T09:00:00',
        });
      }

      final ganashRecipe = Recipe(
        id: 'rec_ganash',
        title: 'Ганаш тёмный',
        category: 'Полуфабрикаты',
        yieldGrams: 500,
        grossGrams: 520,
        yieldPortions: 1,
        ingredients: const [
          RecipeIngredientLine(
            itemId: 'inv_choc',
            name: 'Тёмный шоколад 54%',
            qty: 280,
            unit: 'г',
            priceCents: 185000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_cream',
            name: 'Сливки 33%',
            qty: 240,
            unit: 'мл',
            priceCents: 65000,
            priceUnit: 'за л',
          ),
        ],
        steps: const ['Нагреть сливки до 85 °C', 'Эмульгировать шоколад блендером'],
        allergens: const ['Лактоза'],
        laborHours: 0.4,
        laborRateCents: 60000,
        overheadPercent: 8,
        marginPercent: 30,
        costCents: 99000,
        recommendedPriceCents: 130000,
        shelfLifeHours: 120,
        storageCondition: '+4 °C',
        updatedAt: '${yesterday}T10:00:00',
      );

      final berryCake = Recipe(
        id: 'rec_berry_cake',
        title: 'Торт «Ягодный бархат»',
        category: 'Торты',
        yieldGrams: 2000,
        grossGrams: 2180,
        yieldPortions: 10,
        formSize: 'Ø 18 см',
        ingredients: const [
          RecipeIngredientLine(
            subRecipeId: 'rec_ganash',
            name: 'Ганаш тёмный',
            qty: 300,
            unit: 'г',
            priceCents: 99000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_mascarpone',
            name: 'Сыр маскарпоне',
            qty: 500,
            unit: 'г',
            priceCents: 110000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_cream',
            name: 'Сливки 33%',
            qty: 400,
            unit: 'мл',
            priceCents: 65000,
            priceUnit: 'за л',
          ),
          RecipeIngredientLine(
            itemId: 'inv_berry',
            name: 'Малина с/м',
            qty: 350,
            unit: 'г',
            lossPercent: 10,
            priceCents: 95000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_box',
            name: 'Коробка для торта 25×25 с окном',
            qty: 1,
            unit: 'шт',
            priceCents: 18500,
            priceUnit: 'за шт',
            isPackaging: true,
          ),
        ],
        packVariants: const [
          RecipePackVariant(
            id: 'pv_15',
            label: 'Мини 1,5 кг',
            qtyOrGrams: 1500,
            mode: 'grams',
            packagingCents: 18500,
            priceCents: 450000,
          ),
          RecipePackVariant(
            id: 'pv_20',
            label: 'Стандарт 2 кг',
            qtyOrGrams: 2000,
            mode: 'grams',
            packagingCents: 18500,
            priceCents: 580000,
          ),
        ],
        steps: const [
          'Выпечь бисквит, остудить 4 часа',
          'Собрать торт с малиновым конфи и кремом чиз',
          'Выровнять ганашем перед декором',
        ],
        allergens: const ['Глютен', 'Яйца', 'Лактоза'],
        laborHours: 3.0,
        laborRateCents: 65000,
        packagingCents: 18500,
        overheadPercent: 10,
        marginPercent: 55,
        costCents: 374000,
        recommendedPriceCents: 580000,
        shelfLifeHours: 72,
        storageCondition: '+2…+4 °C',
        favorite: true,
        updatedAt: '${today}T09:00:00',
      );

      final pistachioRoll = Recipe(
        id: 'rec_pistachio_roll',
        title: 'Меренговый рулет с фисташкой',
        category: 'Рулеты',
        yieldGrams: 1100,
        grossGrams: 1220,
        yieldPortions: 8,
        ingredients: const [
          RecipeIngredientLine(
            itemId: 'inv_mascarpone',
            name: 'Сыр маскарпоне',
            qty: 250,
            unit: 'г',
            priceCents: 110000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_cream',
            name: 'Сливки 33%',
            qty: 200,
            unit: 'мл',
            priceCents: 65000,
            priceUnit: 'за л',
          ),
          RecipeIngredientLine(
            itemId: 'inv_pistachio',
            name: 'Фисташковая паста',
            qty: 60,
            unit: 'г',
            priceCents: 420000,
            priceUnit: 'за кг',
          ),
          RecipeIngredientLine(
            itemId: 'inv_berry',
            name: 'Малина с/м',
            qty: 180,
            unit: 'г',
            priceCents: 95000,
            priceUnit: 'за кг',
          ),
        ],
        steps: const [
          'Взбить меренгу до плотных пиков',
          'Выпечь 28 минут при 150 °C',
          'Прослоить фисташковым кремом и малиной',
        ],
        allergens: const ['Яйца', 'Лактоза', 'Орехи'],
        laborHours: 1.5,
        laborRateCents: 65000,
        packagingCents: 12000,
        overheadPercent: 10,
        marginPercent: 50,
        costCents: 195000,
        recommendedPriceCents: 320000,
        shelfLifeHours: 48,
        storageCondition: '+2…+4 °C',
        favorite: true,
        updatedAt: '${today}T08:30:00',
      );

      for (final r in [ganashRecipe, berryCake, pistachioRoll]) {
        await txn.insert('recipes', {
          'id': r.id,
          'title': r.title,
          'category': r.category,
          'version': r.version,
          'status': r.status,
          'yield_grams': r.yieldGrams,
          'gross_grams': r.grossGrams,
          'yield_portions': r.yieldPortions,
          'form_size': r.formSize,
          'photo_path': null,
          'ingredients_json':
              jsonEncode(r.ingredients.map((e) => e.toJson()).toList()),
          'pack_variants_json':
              jsonEncode(r.packVariants.map((e) => e.toJson()).toList()),
          'steps_json': jsonEncode(r.steps),
          'allergens_json': jsonEncode(r.allergens),
          'labor_hours': r.laborHours,
          'labor_rate_cents': r.laborRateCents,
          'packaging_cents': r.packagingCents,
          'overhead_percent': r.overheadPercent,
          'margin_percent': r.marginPercent,
          'cost_cents': r.costCents,
          'recommended_price_cents': r.recommendedPriceCents,
          'shelf_life_hours': r.shelfLifeHours,
          'storage_condition': r.storageCondition,
          'favorite': r.favorite ? 1 : 0,
          'updated_at': r.updatedAt,
        });
      }

      await txn.insert('clients', {
        'id': 'cli_anna',
        'name': 'Анна Соколова',
        'phone': '+7 999 123-45-67',
        'address': 'ул. Садовая, 14, кв. 8',
        'preferences': 'Нежный крем, минимум сахара',
        'allergens': 'Без арахиса',
        'deposit_cents': 150000,
        'favorite': 1,
      });
      await txn.insert('clients', {
        'id': 'cli_dmitry',
        'name': 'Дмитрий Орлов',
        'phone': '+7 916 555-18-90',
        'address': 'Самовывоз',
        'preferences': 'Классика с ягодами',
        'allergens': '',
        'deposit_cents': 0,
        'favorite': 0,
      });

      final ord1Items = [
        const OrderItem(
          id: 'oi_1',
          recipeId: 'rec_berry_cake',
          recipeTitle: 'Торт «Ягодный бархат»',
          qty: 1,
          weightGrams: 2000,
          priceCents: 580000,
          costCents: 374000,
        ),
        const OrderItem(
          id: 'oi_2',
          recipeId: 'rec_pistachio_roll',
          recipeTitle: 'Меренговый рулет с фисташкой',
          qty: 1,
          weightGrams: 1100,
          priceCents: 320000,
          costCents: 195000,
        ),
      ];
      await txn.insert('orders', {
        'id': 'ord_demo_1',
        'order_number': '№104',
        'title': buildOrderSummaryTitle(ord1Items),
        'client_id': 'cli_anna',
        'client_name': 'Анна Соколова',
        'items_json': jsonEncode(ord1Items.map((e) => e.toJson()).toList()),
        'recipe_id': 'rec_berry_cake',
        'recipe_title': 'Торт «Ягодный бархат»',
        'weight_grams': 3100.0,
        'price_cents': 900000,
        'cost_cents': 569000,
        'prepayment_cents': 450000,
        'paid_cents': 450000,
        'discount_cents': 0,
        'status': OrderStatus.inProgress.name,
        'due_date': tomorrow,
        'delivery_address': 'ул. Садовая, 14, кв. 8',
        'wishes': 'Надпись «С днём рождения!» белым шоколадом',
        'allergens': 'Без арахиса',
        'stock_deducted': 0,
        'favorite': 1,
        'created_at': '${yesterday}T14:20:00',
      });

      final ord2Items = [
        const OrderItem(
          id: 'oi_3',
          recipeId: 'rec_pistachio_roll',
          recipeTitle: 'Меренговый рулет с фисташкой',
          qty: 1,
          weightGrams: 1100,
          priceCents: 320000,
          costCents: 195000,
        ),
      ];
      await txn.insert('orders', {
        'id': 'ord_demo_2',
        'order_number': '№103',
        'title': buildOrderSummaryTitle(ord2Items),
        'client_id': 'cli_dmitry',
        'client_name': 'Дмитрий Орлов',
        'items_json': jsonEncode(ord2Items.map((e) => e.toJson()).toList()),
        'recipe_id': 'rec_pistachio_roll',
        'recipe_title': 'Меренговый рулет с фисташкой',
        'weight_grams': 1100.0,
        'price_cents': 320000,
        'cost_cents': 195000,
        'prepayment_cents': 100000,
        'paid_cents': 320000,
        'discount_cents': 0,
        'status': OrderStatus.delivered.name,
        'due_date': yesterday,
        'delivery_address': 'Самовывоз',
        'wishes': null,
        'allergens': null,
        'stock_deducted': 1,
        'favorite': 0,
        'created_at': '${addDaysIso(today, -3)}T11:00:00',
      });

      await txn.insert('work_items', {
        'id': 'wi_demo_1',
        'type': WorkItemType.production.name,
        'source_id': 'ord_demo_1',
        'title': 'Собрать и выровнять торт №104',
        'due_date': today,
        'priority': WorkPriority.high.name,
        'stage': WorkStage.inProgress.name,
        'tags_json': jsonEncode(['Выпечка', 'Заказ №104']),
        'recurrence': WorkRecurrence.none.name,
        'series_id': null,
        'occurrence_index': null,
      });
      await txn.insert('work_items', {
        'id': 'wi_demo_2',
        'type': WorkItemType.quality.name,
        'source_id': null,
        'title': 'Проверить температуру витрины и сроки сливок',
        'due_date': today,
        'priority': WorkPriority.normal.name,
        'stage': WorkStage.queue.name,
        'tags_json': jsonEncode(['Регулярно', 'Качество']),
        'recurrence': WorkRecurrence.daily.name,
        'series_id': 'ser_fridge_check',
        'occurrence_index': 1,
      });

      await txn.insert('suppliers', {
        'id': 'sup_metro',
        'name': 'Кондитерский Дом «Арт»',
        'contact_name': 'Елена',
        'phone': '+7 495 220-11-44',
        'category': 'Шоколад и сливки',
        'debt_cents': 0,
      });
      await txn.insert('purchases', {
        'id': 'pur_demo_1',
        'supplier_id': 'sup_metro',
        'supplier_name': 'Кондитерский Дом «Арт»',
        'item_id': 'inv_pistachio',
        'item_name': 'Фисташковая паста',
        'qty': 500.0,
        'unit': 'г',
        'price_cents': 210000,
        'delivery_cents': 0,
        'expected_date': tomorrow,
        'expires_at': in20Days,
        'status': PurchaseStatus.ordered.name,
      });

      await txn.insert('money_transactions', {
        'id': 'tx_demo_1',
        'kind': TransactionKind.income.name,
        'category': 'Предоплата',
        'amount_cents': 450000,
        'account_id': 'acc_card',
        'account_name': 'Карта мастера',
        'order_id': 'ord_demo_1',
        'reverses_id': null,
        'note': '№104 · Анна Соколова',
        'occurred_at': '${yesterday}T14:25:00',
      });
      await txn.insert('money_transactions', {
        'id': 'tx_demo_2',
        'kind': TransactionKind.income.name,
        'category': 'Оплата заказа',
        'amount_cents': 320000,
        'account_id': 'acc_cash',
        'account_name': 'Наличные',
        'order_id': 'ord_demo_2',
        'reverses_id': null,
        'note': '№103 · Дмитрий Орлов',
        'occurred_at': '${yesterday}T18:10:00',
      });
      await txn.insert('money_transactions', {
        'id': 'tx_demo_3',
        'kind': TransactionKind.expense.name,
        'category': 'Закупка сырья',
        'amount_cents': 285000,
        'account_id': 'acc_card',
        'account_name': 'Карта мастера',
        'order_id': null,
        'reverses_id': null,
        'note': 'Сливки 33% и ягоды',
        'occurred_at': '${addDaysIso(today, -2)}T12:00:00',
      });

      await txn.insert('time_entries', {
        'id': 'te_demo_1',
        'date': yesterday,
        'minutes': 210,
        'note': 'Выпечка и сборка заказов',
      });
    });
  }

  // ==================== Row Mappers ====================

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  Recipe _recipeFromRow(Map<String, dynamic> r) {
    final ingRaw = jsonDecode((r['ingredients_json'] ?? '[]') as String) as List;
    final packRaw = jsonDecode((r['pack_variants_json'] ?? '[]') as String) as List;
    final stepsRaw = jsonDecode((r['steps_json'] ?? '[]') as String) as List;
    final allRaw = jsonDecode((r['allergens_json'] ?? '[]') as String) as List;
    return Recipe(
      id: r['id'] as String,
      title: r['title'] as String,
      category: r['category'] as String,
      version: (r['version'] as num?)?.toInt() ?? 1,
      status: (r['status'] ?? 'approved') as String,
      yieldGrams: (r['yield_grams'] as num).toDouble(),
      grossGrams: (r['gross_grams'] as num?)?.toDouble(),
      yieldPortions: (r['yield_portions'] as num?)?.toInt() ?? 1,
      formSize: r['form_size'] as String?,
      photoPath: r['photo_path'] as String?,
      ingredients: ingRaw
          .whereType<Map<String, dynamic>>()
          .map(RecipeIngredientLine.fromJson)
          .toList(),
      packVariants: packRaw
          .whereType<Map<String, dynamic>>()
          .map(RecipePackVariant.fromJson)
          .toList(),
      steps: stepsRaw.map((e) => e.toString()).toList(),
      allergens: allRaw.map((e) => e.toString()).toList(),
      laborHours: (r['labor_hours'] as num?)?.toDouble() ?? 1.5,
      laborRateCents: (r['labor_rate_cents'] as num?)?.toInt() ?? 55000,
      packagingCents: (r['packaging_cents'] as num?)?.toInt() ?? 0,
      overheadPercent: (r['overhead_percent'] as num?)?.toDouble() ?? 10,
      marginPercent: (r['margin_percent'] as num?)?.toDouble() ?? 45,
      costCents: (r['cost_cents'] as num?)?.toInt() ?? 0,
      recommendedPriceCents:
          (r['recommended_price_cents'] as num?)?.toInt() ?? 0,
      shelfLifeHours: (r['shelf_life_hours'] as num?)?.toInt() ?? 72,
      storageCondition: r['storage_condition'] as String?,
      favorite: (r['favorite'] as num?)?.toInt() == 1,
      updatedAt: (r['updated_at'] ?? '') as String,
    );
  }

  InventoryItem _inventoryFromRow(Map<String, dynamic> r) => InventoryItem(
        id: r['id'] as String,
        name: r['name'] as String,
        kind: _enumByName(
            InventoryKind.values, r['kind'] as String?, InventoryKind.raw),
        category: r['category'] as String?,
        unit: r['unit'] as String,
        qtyOnHand: (r['qty_on_hand'] as num).toDouble(),
        minQty: (r['min_qty'] as num?)?.toDouble() ?? 0,
        avgCostCents: (r['avg_cost_cents'] as num?)?.toInt() ?? 0,
        density: (r['density'] as num?)?.toDouble(),
      );

  StockLot _lotFromRow(Map<String, dynamic> r) => StockLot(
        id: r['id'] as String,
        itemId: r['item_id'] as String,
        itemName: r['item_name'] as String,
        lotCode: r['lot_code'] as String,
        unit: r['unit'] as String,
        initialQty: (r['initial_qty'] as num).toDouble(),
        remainingQty: (r['remaining_qty'] as num).toDouble(),
        unitCostCents: (r['unit_cost_cents'] as num).toInt(),
        expiresAt: r['expires_at'] as String?,
        status: _enumByName(
            StockLotStatus.values, r['status'] as String?, StockLotStatus.active),
        createdAt: (r['created_at'] ?? '') as String,
      );

  StockMovement _movementFromRow(Map<String, dynamic> r) => StockMovement(
        id: r['id'] as String,
        kind: _enumByName(
            MovementKind.values, r['kind'] as String?, MovementKind.receipt),
        itemId: r['item_id'] as String,
        itemName: r['item_name'] as String,
        lotId: r['lot_id'] as String?,
        qty: (r['qty'] as num).toDouble(),
        unit: r['unit'] as String,
        totalCents: (r['total_cents'] as num).toInt(),
        reason: r['reason'] as String?,
        occurredAt: r['occurred_at'] as String,
      );

  Purchase _purchaseFromRow(Map<String, dynamic> r) => Purchase(
        id: r['id'] as String,
        supplierId: r['supplier_id'] as String?,
        supplierName: r['supplier_name'] as String,
        itemId: r['item_id'] as String?,
        itemName: r['item_name'] as String,
        qty: (r['qty'] as num).toDouble(),
        unit: r['unit'] as String,
        priceCents: (r['price_cents'] as num).toInt(),
        deliveryCents: (r['delivery_cents'] as num?)?.toInt() ?? 0,
        expectedDate: r['expected_date'] as String?,
        expiresAt: r['expires_at'] as String?,
        status: _enumByName(PurchaseStatus.values, r['status'] as String?,
            PurchaseStatus.ordered),
      );

  ProductionRun _productionFromRow(Map<String, dynamic> r) => ProductionRun(
        id: r['id'] as String,
        recipeId: r['recipe_id'] as String?,
        recipeTitle: r['recipe_title'] as String,
        plannedGrams: (r['planned_grams'] as num).toDouble(),
        actualGrams: (r['actual_grams'] as num?)?.toDouble() ?? 0,
        totalCostCents: (r['total_cost_cents'] as num?)?.toInt() ?? 0,
        outputLotId: r['output_lot_id'] as String?,
        status: _enumByName(ProductionStatus.values, r['status'] as String?,
            ProductionStatus.completed),
        createdAt: r['created_at'] as String,
      );

  Client _clientFromRow(Map<String, dynamic> r) => Client(
        id: r['id'] as String,
        name: r['name'] as String,
        phone: r['phone'] as String?,
        address: r['address'] as String?,
        preferences: r['preferences'] as String?,
        allergens: r['allergens'] as String?,
        depositCents: (r['deposit_cents'] as num?)?.toInt() ?? 0,
        favorite: (r['favorite'] as num?)?.toInt() == 1,
      );

  Order _orderFromRow(Map<String, dynamic> r) {
    final itemsRaw = jsonDecode((r['items_json'] ?? '[]') as String) as List;
    return Order(
      id: r['id'] as String,
      orderNumber: r['order_number'] as String,
      title: r['title'] as String,
      clientId: r['client_id'] as String?,
      clientName: r['client_name'] as String,
      items: itemsRaw
          .whereType<Map<String, dynamic>>()
          .map(OrderItem.fromJson)
          .toList(),
      recipeId: r['recipe_id'] as String?,
      recipeTitle: r['recipe_title'] as String?,
      weightGrams: (r['weight_grams'] as num?)?.toDouble() ?? 0,
      priceCents: (r['price_cents'] as num?)?.toInt() ?? 0,
      costCents: (r['cost_cents'] as num?)?.toInt() ?? 0,
      prepaymentCents: (r['prepayment_cents'] as num?)?.toInt() ?? 0,
      paidCents: (r['paid_cents'] as num?)?.toInt() ?? 0,
      discountCents: (r['discount_cents'] as num?)?.toInt() ?? 0,
      status: _enumByName(
          OrderStatus.values, r['status'] as String?, OrderStatus.confirmed),
      dueDate: r['due_date'] as String?,
      deliveryAddress: r['delivery_address'] as String?,
      wishes: r['wishes'] as String?,
      allergens: r['allergens'] as String?,
      stockDeducted: (r['stock_deducted'] as num?)?.toInt() == 1,
      favorite: (r['favorite'] as num?)?.toInt() == 1,
      createdAt: r['created_at'] as String,
    );
  }

  WorkItem _workItemFromRow(Map<String, dynamic> r) {
    final tagsRaw = jsonDecode((r['tags_json'] ?? '[]') as String) as List;
    return WorkItem(
      id: r['id'] as String,
      type: _enumByName(
          WorkItemType.values, r['type'] as String?, WorkItemType.task),
      sourceId: r['source_id'] as String?,
      title: r['title'] as String,
      dueDate: r['due_date'] as String?,
      priority: _enumByName(
          WorkPriority.values, r['priority'] as String?, WorkPriority.normal),
      stage: _enumByName(
          WorkStage.values, r['stage'] as String?, WorkStage.queue),
      tags: tagsRaw.map((e) => e.toString()).toList(),
      recurrence: _enumByName(
          WorkRecurrence.values, r['recurrence'] as String?, WorkRecurrence.none),
      seriesId: r['series_id'] as String?,
      occurrenceIndex: (r['occurrence_index'] as num?)?.toInt(),
    );
  }
}
