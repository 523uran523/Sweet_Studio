import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/backup_service.dart';
import '../core/media_store.dart';
import '../core/money_format.dart';
import '../core/notifications_core.dart';
import '../core/work_recurrence.dart';
import '../data/app_database.dart';
import '../data/draft_storage.dart';
import '../data/models.dart';
import '../theme/soft_atelier.dart';

class StudioStore extends ChangeNotifier {
  StudioStore({
    required this.db,
    required this.mediaStore,
    required this.drafts,
  });

  final AppDatabase db;
  final MediaStore mediaStore;
  final DraftStorage drafts;

  StudioProfile profile = const StudioProfile();
  List<Recipe> recipes = [];
  List<InventoryItem> inventoryItems = [];
  List<StockLot> stockLots = [];
  List<StockMovement> stockMovements = [];
  List<Supplier> suppliers = [];
  List<Purchase> purchases = [];
  List<ProductionRun> productionRuns = [];
  List<Client> clients = [];
  List<Order> orders = [];
  List<WorkItem> workItems = [];
  List<Account> accounts = [];
  List<MoneyTransaction> moneyTransactions = [];
  List<TimeEntry> timeEntries = [];
  List<StudioAlert> alerts = [];

  bool isLoaded = false;
  bool hideBalances = false;
  int currentTabIndex = 0;

  // Persistent Home Work Timer
  bool timerRunning = false;
  DateTime? timerStartedAt;
  int accumulatedSeconds = 0;
  String timerNote = 'Работа в кондитерской';
  Timer? _uiTick;

  AtelierPalette get palette => paletteForIndex(profile.themeIndex);

  static Future<StudioStore> bootstrap() async {
    final db = await AppDatabase.openDefault();
    final media = await MediaStore.createDefault();
    final drafts = DraftStorage();
    final store = StudioStore(db: db, mediaStore: media, drafts: drafts);
    await store.loadAll();
    await store.restoreTimerState();
    return store;
  }

  Future<void> loadAll() async {
    await db.ensureDefaultCashAccount();
    profile = await db.getProfile();
    recipes = await db.getRecipes();
    inventoryItems = await db.getInventoryItems();
    stockLots = await db.getStockLots();
    stockMovements = await db.getStockMovements();
    suppliers = await db.getSuppliers();
    purchases = await db.getPurchases();
    productionRuns = await db.getProductionRuns();
    clients = await db.getClients();
    orders = await db.getOrders();
    workItems = await db.getWorkItems();
    accounts = await db.getAccounts();
    moneyTransactions = await db.getMoneyTransactions();
    timeEntries = await db.getTimeEntries();
    alerts = buildStudioAlerts(
      orders: orders,
      workItems: workItems,
      inventoryItems: inventoryItems,
      stockLots: stockLots,
      profile: profile,
    );
    isLoaded = true;
    notifyListeners();
  }

  void setTab(int idx) {
    currentTabIndex = idx;
    notifyListeners();
  }

  void toggleHideBalances() {
    hideBalances = !hideBalances;
    notifyListeners();
  }

  // ==================== Onboarding & Settings ====================

  Future<void> completeOnboarding({
    required String studioName,
    required String slogan,
    required int themeIndex,
    required bool withDemoData,
  }) async {
    if (withDemoData) {
      await db.seedDemoData();
    } else {
      await db.clearAllBusinessData(isDemoMode: false);
    }
    final nextProfile = profile.copyWith(
      studioName: studioName.trim().isEmpty ? 'Моя кондитерская' : studioName.trim(),
      slogan: slogan.trim().isEmpty ? 'Авторские десерты на заказ' : slogan.trim(),
      themeIndex: themeIndex,
      isDemoMode: withDemoData,
      onboardingCompleted: true,
    );
    await db.saveProfile(nextProfile);
    await loadAll();
  }

  Future<void> updateProfile(StudioProfile next) async {
    await db.saveProfile(next);
    await loadAll();
  }

  Future<void> switchToCleanWorkspace() async {
    await mediaStore.clearAllMedia();
    await db.clearAllBusinessData(isDemoMode: false);
    await drafts.clearKey(DraftStorage.orderDraftKey);
    await drafts.clearKey(DraftStorage.recipeDraftKey);
    await loadAll();
  }

  Future<void> loadDemoWorkspace() async {
    await mediaStore.clearAllMedia();
    await db.seedDemoData();
    await loadAll();
  }

  // ==================== Work Timer ====================

  Future<void> restoreTimerState() async {
    final saved = await drafts.loadJson(DraftStorage.timerStateKey);
    if (saved == null) return;
    timerRunning = saved['running'] == true;
    accumulatedSeconds = (saved['accumulatedSeconds'] as num?)?.toInt() ?? 0;
    timerNote = (saved['note'] ?? 'Работа в кондитерской') as String;
    final startedIso = saved['startedAt'] as String?;
    if (timerRunning && startedIso != null) {
      timerStartedAt = DateTime.tryParse(startedIso);
      if (timerStartedAt == null) timerRunning = false;
    }
    if (timerRunning) _ensureTick();
    notifyListeners();
  }

  int get totalTimerSeconds {
    if (!timerRunning || timerStartedAt == null) return accumulatedSeconds;
    final delta = DateTime.now().difference(timerStartedAt!).inSeconds;
    return accumulatedSeconds + (delta > 0 ? delta : 0);
  }

  void _ensureTick() {
    _uiTick?.cancel();
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  Future<void> startTimer({String? note}) async {
    if (timerRunning) return;
    if (note != null && note.trim().isNotEmpty) {
      timerNote = note.trim();
    }
    timerRunning = true;
    timerStartedAt = DateTime.now();
    _ensureTick();
    await drafts.saveJson(DraftStorage.timerStateKey, {
      'running': true,
      'startedAt': timerStartedAt!.toIso8601String(),
      'accumulatedSeconds': accumulatedSeconds,
      'note': timerNote,
    });
    notifyListeners();
  }

  Future<void> pauseTimer() async {
    if (!timerRunning) return;
    accumulatedSeconds = totalTimerSeconds;
    timerRunning = false;
    timerStartedAt = null;
    _uiTick?.cancel();
    await drafts.saveJson(DraftStorage.timerStateKey, {
      'running': false,
      'startedAt': null,
      'accumulatedSeconds': accumulatedSeconds,
      'note': timerNote,
    });
    notifyListeners();
  }

  Future<int> stopAndSaveTimer() async {
    final secs = totalTimerSeconds;
    final minutes = (secs / 60).ceil().clamp(1, 1440);
    _uiTick?.cancel();
    timerRunning = false;
    timerStartedAt = null;
    accumulatedSeconds = 0;
    await drafts.clearKey(DraftStorage.timerStateKey);
    if (secs >= 5) {
      await db.addTimeEntry(
        TimeEntry(
          id: newId('te'),
          date: todayIsoDate(),
          minutes: minutes,
          note: timerNote,
        ),
      );
      await loadAll();
      return minutes;
    }
    notifyListeners();
    return 0;
  }

  @override
  void dispose() {
    _uiTick?.cancel();
    super.dispose();
  }

  // ==================== Recipes ====================

  Future<void> saveRecipe(Recipe recipe) async {
    await db.upsertRecipe(recipe);
    await loadAll();
  }

  Future<void> deleteRecipe(String id, {String? photoPath}) async {
    await db.deleteRecipe(id);
    if (photoPath != null) {
      await mediaStore.deletePhoto(photoPath);
    }
    await loadAll();
  }

  // ==================== Clients & Orders ====================

  Future<void> saveClient(Client client) async {
    await db.upsertClient(client);
    await loadAll();
  }

  Future<void> deleteClient(String id) async {
    await db.deleteClient(id);
    await loadAll();
  }

  Future<void> saveOrder(Order order) async {
    await db.upsertOrder(order);
    await loadAll();
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await db.updateOrderStatus(orderId, status);
    await loadAll();
  }

  Future<void> deleteOrder(String id) async {
    await db.deleteOrder(id);
    await loadAll();
  }

  Future<void> deductOrderStockFefo(String orderId) async {
    await db.deductOrderStockFefo(orderId);
    await loadAll();
  }

  Future<void> recordOrderPayment({
    required String orderId,
    required String accountId,
    required int amountCents,
    String? note,
  }) async {
    await db.recordOrderPayment(
      orderId: orderId,
      accountId: accountId,
      amountCents: amountCents,
      note: note,
    );
    await loadAll();
  }

  Future<void> payOrderWithDeposit({
    required String orderId,
    int? customAmountCents,
  }) async {
    await db.payOrderWithDeposit(
      orderId: orderId,
      customAmountCents: customAmountCents,
    );
    await loadAll();
  }

  Future<void> refundOrderPayment({
    required String orderId,
    required String accountId,
    required int amountCents,
    String? reason,
  }) async {
    await db.refundOrderPayment(
      orderId: orderId,
      accountId: accountId,
      amountCents: amountCents,
      reason: reason,
    );
    await loadAll();
  }

  Future<void> topUpClientDeposit({
    required String clientId,
    required String accountId,
    required int amountCents,
    String? note,
  }) async {
    await db.topUpClientDeposit(
      clientId: clientId,
      accountId: accountId,
      amountCents: amountCents,
      note: note,
    );
    await loadAll();
  }

  // ==================== WorkHub ====================

  Future<void> saveWorkItem(WorkItem item) async {
    await db.upsertWorkItem(item);
    await loadAll();
  }

  Future<void> moveWorkItemStage(WorkItem item, WorkStage nextStage) async {
    final updated = WorkItem(
      id: item.id,
      type: item.type,
      sourceId: item.sourceId,
      title: item.title,
      dueDate: item.dueDate,
      priority: item.priority,
      stage: nextStage,
      tags: item.tags,
      recurrence: item.recurrence,
      seriesId: item.seriesId,
      occurrenceIndex: item.occurrenceIndex,
    );
    await db.upsertWorkItem(updated);
    if (nextStage == WorkStage.done && item.recurrence != WorkRecurrence.none) {
      final plan = planNextRecurringWorkItem(updated, workItems);
      if (plan != null) {
        await db.upsertWorkItem(plan.nextItem);
      }
    }
    await loadAll();
  }

  Future<void> deleteWorkItem(String id) async {
    await db.deleteWorkItem(id);
    await loadAll();
  }

  // ==================== Inventory, Purchases & Production ====================

  Future<void> saveInventoryItem(InventoryItem item) async {
    await db.upsertInventoryItem(item);
    await loadAll();
  }

  Future<void> addStockLotReceipt({
    required String itemId,
    required double qty,
    required String unit,
    required int totalCostCents,
    String? expiresAt,
    String? reason,
  }) async {
    await db.addStockLotReceipt(
      itemId: itemId,
      qty: qty,
      unit: unit,
      totalCostCents: totalCostCents,
      expiresAt: expiresAt,
      reason: reason,
    );
    await loadAll();
  }

  Future<void> writeOffStockLot({
    required String lotId,
    required double qty,
    required String reason,
    bool markExpired = false,
  }) async {
    await db.writeOffStockLot(
      lotId: lotId,
      qty: qty,
      reason: reason,
      markExpired: markExpired,
    );
    await loadAll();
  }

  Future<void> reconcileInventoryItem({
    required String itemId,
    required double actualQty,
    String? reason,
  }) async {
    await db.reconcileInventoryItem(
      itemId: itemId,
      actualQty: actualQty,
      reason: reason,
    );
    await loadAll();
  }

  Future<void> saveSupplier(Supplier s) async {
    await db.upsertSupplier(s);
    await loadAll();
  }

  Future<void> savePurchase(Purchase p) async {
    await db.upsertPurchase(p);
    await loadAll();
  }

  Future<void> receivePurchase({
    required String purchaseId,
    String? accountId,
    bool payFromAccount = false,
  }) async {
    await db.receivePurchase(
      purchaseId: purchaseId,
      accountId: accountId,
      payFromAccount: payFromAccount,
    );
    await loadAll();
  }

  Future<ProductionRun> completeProductionRun({
    required String recipeId,
    required double plannedGrams,
    required double actualGrams,
    String? expiresAt,
  }) async {
    final run = await db.completeProductionRun(
      recipeId: recipeId,
      plannedGrams: plannedGrams,
      actualGrams: actualGrams,
      expiresAt: expiresAt,
    );
    await loadAll();
    return run;
  }

  Future<void> reverseProductionRun(String runId) async {
    await db.reverseProductionRun(runId);
    await loadAll();
  }

  // ==================== Finance ====================

  Future<void> saveAccount(Account acc) async {
    await db.upsertAccount(acc);
    await loadAll();
  }

  Future<void> addMoneyTransaction({
    required TransactionKind kind,
    required String category,
    required int amountCents,
    required String accountId,
    String? note,
  }) async {
    await db.addMoneyTransaction(
      kind: kind,
      category: category,
      amountCents: amountCents,
      accountId: accountId,
      note: note,
    );
    await loadAll();
  }

  Future<void> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required int amountCents,
    String? note,
  }) async {
    await db.transferBetweenAccounts(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountCents: amountCents,
      note: note,
    );
    await loadAll();
  }

  Future<void> reverseMoneyTransaction(String txId) async {
    await db.reverseMoneyTransaction(txId);
    await loadAll();
  }

  // ==================== Backup & Notifications ====================

  Future<File> exportBackupZip() async {
    final tempDir = await getTemporaryDirectory();
    final file = await BackupService.createBackupZip(
      db: db,
      mediaStore: mediaStore,
      outputDir: tempDir,
    );
    await loadAll();
    return file;
  }

  Future<BackupInspection> inspectBackupZip(String zipPath) async {
    final tempDir = await getTemporaryDirectory();
    return BackupService.inspectBackupZip(
      zipPath: zipPath,
      tempRoot: tempDir,
      dbFactory: db.factory,
    );
  }

  Future<void> restoreFromInspection(BackupInspection inspection) async {
    final tempDir = await getTemporaryDirectory();
    await BackupService.restoreFromInspection(
      inspection: inspection,
      targetDb: db,
      targetMedia: mediaStore,
      tempRoot: tempDir,
    );
    await loadAll();
  }

  Future<bool> enableAndNotifyLocalReminders() async {
    final granted = await LocalReminderService.instance.requestPermission();
    final updated = profile.copyWith(localNotificationsEnabled: granted);
    await db.saveProfile(updated);
    await loadAll();
    if (granted && alerts.isNotEmpty) {
      await LocalReminderService.instance.showSummaryNotification(
        studioName: profile.studioName,
        alerts: alerts,
      );
    }
    return granted;
  }
}
