import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../core/backup_service.dart';
import '../core/money_format.dart';
import '../core/reminder_service.dart';
import '../core/utils/app_utils.dart';
import '../data/schema_tables.dart';
import '../data/app_database.dart';
import '../data/models/account.dart';
import '../data/models/appointment.dart';
import '../data/models/booking_resource.dart';
import '../data/models/cash_shift.dart';
import '../data/models/client.dart';
import '../data/models/employee.dart';
import '../data/models/time_entry.dart';
import '../data/models/client_reminder.dart';
import '../data/models/attribute_type.dart';
import '../data/models/entity_attribute.dart';
import '../data/models/unified_event.dart';
import '../data/models/inventory_composition.dart';
import '../data/models/inventory_item.dart';
import '../data/models/job_attachment.dart';
import '../data/models/supplier.dart';
import '../data/models/stock_movement.dart';
import '../data/models/stock_location.dart';
import '../data/models/stock_batch.dart';
import '../data/models/stock_transfer.dart';
import '../data/models/production_need.dart';
import '../data/models/job.dart';
import '../data/models/job_items.dart';
import '../data/models/money_transaction.dart';
import '../data/models/recurring_payment.dart';
import '../data/repositories/recurring_payment_repository.dart';
import '../data/repositories/attribute_type_repository.dart';
import '../data/repositories/entity_attribute_repository.dart';
import '../data/models/obligation.dart';
import '../data/repositories/obligation_repository.dart';
import '../data/models/lead.dart';
import '../data/repositories/lead_repository.dart';
import '../data/models/quote.dart';
import '../data/repositories/quote_repository.dart';
import '../data/models/client_credit.dart';
import '../data/repositories/client_credit_repository.dart';
import '../data/models/credit_change.dart';
import '../data/models/work_object.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/booking_resource_repository.dart';
import '../data/repositories/cash_shift_repository.dart';
import '../data/repositories/employee_repository.dart';
import '../data/repositories/time_entry_repository.dart';
import '../data/repositories/client_reminder_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/inventory_composition_repository.dart';
import '../data/repositories/accrual_entry_repository.dart';
import '../data/repositories/pay_condition_repository.dart';
import '../data/repositories/payslip_repository.dart';
import '../data/models/accrual_entry.dart';
import '../data/models/pay_condition.dart';
import '../data/models/payslip.dart';
import '../core/payroll_engine.dart';
import '../core/payroll_calc.dart';
import '../data/repositories/inventory_item_repository.dart';
import '../data/repositories/job_repository.dart';
import '../data/repositories/stock_movement_repository.dart';
import '../data/repositories/stock_location_repository.dart';
import '../data/repositories/stock_batch_repository.dart';
import '../data/repositories/stock_transfer_repository.dart';
import '../data/repositories/money_transaction_repository.dart';
import '../data/repositories/material_repository.dart';
import '../data/repositories/object_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/stage_repository.dart';
import '../data/repositories/supplier_repository.dart';
import 'settings_controller.dart';

class ClosedPeriod {
  const ClosedPeriod({
    required this.id,
    required this.start,
    required this.end,
    required this.closedAt,
    this.note,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final DateTime closedAt;
  final String? note;

  factory ClosedPeriod.fromMap(Map<String, Object?> map) {
    return ClosedPeriod(
      id: (map['id'] as String?) ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(
        (map['start_at'] as num?)?.toInt() ?? 0,
      ),
      end: DateTime.fromMillisecondsSinceEpoch(
        (map['end_at'] as num?)?.toInt() ?? 0,
      ),
      closedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['closed_at'] as num?)?.toInt() ?? 0,
      ),
      note: map['note'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'start_at': start.millisecondsSinceEpoch,
    'end_at': end.millisecondsSinceEpoch,
    'closed_at': closedAt.millisecondsSinceEpoch,
    'note': note,
  };

  bool contains(DateTime date) => !date.isBefore(start) && !date.isAfter(end);
}

/// Один день платёжного календаря (`store.cashPlan`).
class CashPlanDay {
  const CashPlanDay({
    required this.date,
    required this.balanceStart,
    required this.incoming,
    required this.outgoing,
    required this.balanceEnd,
  });

  final DateTime date;
  final int balanceStart;

  /// Ожидаемые поступления: дебиторка со сроком в этот день + регулярные
  /// платежи «в ноль» и выше.
  final int incoming;

  /// Ожидаемые платежи: кредиторка + регулярные расходы.
  final int outgoing;
  final int balanceEnd;

  int get net => incoming - outgoing;

  /// Баланс уходит в минус — денег не хватает.
  bool get isGap => balanceEnd < 0;
}

class MastersStore extends ChangeNotifier {
  MastersStore(this._appDatabase, this.settings) {
    _clientRepo = ClientRepository(_appDatabase.database);
    _objectRepo = ObjectRepository(_appDatabase.database);
    _jobRepo = JobRepository(_appDatabase.database);
    _stageRepo = StageRepository(_appDatabase.database);
    _materialRepo = MaterialRepository(_appDatabase.database);
    _sessionRepo = SessionRepository(_appDatabase.database);
    _accountRepo = AccountRepository(_appDatabase.database);
    _reminderRepo = ClientReminderRepository(_appDatabase.database);
    _employeeRepo = EmployeeRepository(_appDatabase.database);
    _timeEntryRepo = TimeEntryRepository(_appDatabase.database);
    _paymentRepo = EmployeePaymentRepository(_appDatabase.database);
    _supplierRepo = SupplierRepository(_appDatabase.database);
    _purchaseRepo = PurchaseRepository(_appDatabase.database);
    _moneyTxRepo = MoneyTransactionRepository(_appDatabase.database);
    _shiftRepo = CashShiftRepository(_appDatabase.database);
    _inventoryRepo = InventoryItemRepository(_appDatabase.database);
    _stockMovementRepo = StockMovementRepository(_appDatabase.database);
    _compositionRepo = InventoryCompositionRepository(_appDatabase.database);
    _appointmentRepo = AppointmentRepository(_appDatabase.database);
    _bookingResourceRepo = BookingResourceRepository(_appDatabase.database);
    _recurringRepo = RecurringPaymentRepository(_appDatabase.database);
    _payrollRepo = PayrollPeriodRepository(_appDatabase.database);
    _accrualEntryRepo = AccrualEntryRepository(_appDatabase.database);
    _payConditionRepo = PayConditionRepository(_appDatabase.database);
    _payslipRepo = PayslipRepository(_appDatabase.database);
    _attributeRepo = EntityAttributeRepository(_appDatabase.database);
    _attributeTypeRepo = AttributeTypeRepository(_appDatabase.database);
    _obligationRepo = ObligationRepository(_appDatabase.database);
    _leadRepo = LeadRepository(_appDatabase.database);
    _quoteRepo = QuoteRepository(_appDatabase.database);
    _creditRepo = ClientCreditRepository(_appDatabase.database);
    _locationRepo = StockLocationRepository(_appDatabase.database);
    _batchRepo = StockBatchRepository(_appDatabase.database);
    _transferRepo = StockTransferRepository(_appDatabase.database);
  }

  final AppDatabase _appDatabase;
  final SettingsController settings;

  late final ClientRepository _clientRepo;
  late final ObjectRepository _objectRepo;
  late final JobRepository _jobRepo;
  late final StageRepository _stageRepo;
  late final MaterialRepository _materialRepo;
  late final SessionRepository _sessionRepo;
  late final AccountRepository _accountRepo;
  late final ClientReminderRepository _reminderRepo;
  late final EmployeeRepository _employeeRepo;
  late final TimeEntryRepository _timeEntryRepo;
  late final EmployeePaymentRepository _paymentRepo;
  late final MoneyTransactionRepository _moneyTxRepo;
  late final CashShiftRepository _shiftRepo;
  late final InventoryItemRepository _inventoryRepo;
  late final StockMovementRepository _stockMovementRepo;
  late final InventoryCompositionRepository _compositionRepo;
  late final AppointmentRepository _appointmentRepo;
  late final BookingResourceRepository _bookingResourceRepo;
  late final SupplierRepository _supplierRepo;
  late final PurchaseRepository _purchaseRepo;
  late final RecurringPaymentRepository _recurringRepo;
  late final PayrollPeriodRepository _payrollRepo;
  late final AccrualEntryRepository _accrualEntryRepo;
  late final PayConditionRepository _payConditionRepo;
  late final PayslipRepository _payslipRepo;
  final _payConditionCache = <String, List<PayCondition>>{};
  List<Payslip> _payslips = [];
  List<PayCondition> _payConditions = [];
  List<AccrualEntry> _accrualEntries = [];
  late final EntityAttributeRepository _attributeRepo;
  late final AttributeTypeRepository _attributeTypeRepo;
  late final ObligationRepository _obligationRepo;
  late final LeadRepository _leadRepo;
  late final QuoteRepository _quoteRepo;
  late final ClientCreditRepository _creditRepo;
  late final StockLocationRepository _locationRepo;
  late final StockBatchRepository _batchRepo;
  late final StockTransferRepository _transferRepo;

  List<Client> _clients = [];
  List<WorkObject> _objects = [];
  List<Job> _jobs = [];
  List<JobStage> _stages = [];
  List<MaterialItem> _materials = [];
  List<EntityAttribute> _attributes = [];
  List<AttributeType> _attributeTypes = [];
  List<WorkSession> _sessions = [];
  List<Account> _accounts = [];
  List<MoneyTransaction> _moneyTransactions = [];
  List<CashShift> _shifts = [];
  List<InventoryItem> _inventoryItems = [];
  List<StockMovement> _stockMovements = [];
  List<InventoryCompositionLine> _compositionLines = [];
  List<Appointment> _appointments = [];
  List<BookingResource> _bookingResources = [];
  List<ClientReminder> _reminders = [];
  List<Employee> _employees = [];
  List<TimeEntry> _timeEntries = [];
  List<EmployeePayment> _employeePayments = [];
  List<Supplier> _suppliers = [];
  List<Purchase> _purchases = [];
  List<PurchaseLine> _purchaseLines = [];
  List<Obligation> _obligations = [];
  List<Lead> _leads = [];
  List<Quote> _quotes = [];
  List<ClientCredit> _credits = [];

  /// Склад по точкам (Э5): локации, материализованные остатки, партии и
  /// перемещения. Таблицы существуют всегда (§12.2), списки пусты, пока
  /// `module_locations` не включён и бэкфилл не создал «Основной склад».
  List<StockLocation> _locations = [];
  List<StockLevel> _stockLevels = [];
  List<StockBatch> _batches = [];
  List<StockTransfer> _transfers = [];
  List<StockTransferLine> _transferLines = [];

  /// Движения кредитов из `audit_log` (§12.1): списаний в `money_transactions`
  /// намеренно нет, поэтому история живёт только здесь.
  List<CreditChange> _creditChanges = [];
  bool _loaded = false;

  // Cache invalidation is centralized: notifyListeners() bumps state and
  // clears the derived views and memoized computations above.
  bool _viewsDirty = true;
  List<Client>? _clientsView;
  List<WorkObject>? _objectsView;
  List<Job>? _jobsView;
  List<JobStage>? _stagesView;
  List<MaterialItem>? _materialsView;
  List<WorkSession>? _sessionsView;
  List<Account>? _accountsView;
  List<MoneyTransaction>? _moneyTransactionsView;
  List<CashShift>? _shiftsView;
  List<InventoryItem>? _inventoryItemsView;
  List<StockMovement>? _stockMovementsView;
  List<Appointment>? _appointmentsView;
  List<BookingResource>? _bookingResourcesView;
  List<ClientReminder>? _remindersView;
  List<Employee>? _employeesView;
  List<TimeEntry>? _timeEntriesView;
  List<EmployeePayment>? _employeePaymentsView;

  final Map<String, int> _intCache = {};
  List<ClosedPeriod> _closedPeriods = [];
  List<RecurringPayment> _recurringPayments = [];
  List<PayrollPeriod> _payrollPeriods = [];

  ({
    int dailyNet,
    int daysToGo,
    int scheduledNet,
    int scheduledFutureIncoming,
    int monthIncomeCents,
  })
  _monthEndProjectionPieces() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final recentStart = now.subtract(const Duration(days: 30));

    int monthIncomeCents = 0;
    for (final transaction in _moneyTransactions) {
      if (transaction.voided || transaction.direction != 'in') continue;
      if (transaction.createdAt.isAfter(now)) continue;
      if (transaction.createdAt.year != now.year ||
          transaction.createdAt.month != now.month) {
        continue;
      }
      monthIncomeCents += transaction.amountCents;
    }

    int income = 0;
    int expense = 0;
    for (final transaction in _moneyTransactions) {
      if (transaction.voided ||
          transaction.createdAt.isBefore(recentStart) ||
          transaction.createdAt.isAfter(now)) {
        continue;
      }
      if (transaction.direction == 'in') income += transaction.amountCents;
      if (transaction.direction == 'out') expense += transaction.amountCents;
    }
    final daysSeen = now.difference(recentStart).inDays < 1
        ? 1
        : now.difference(recentStart).inDays;
    final dailyNet = ((income - expense) / daysSeen).round();

    int scheduledNet = 0;
    int scheduledFutureIncoming = 0;
    for (final payment in _recurringPayments.where((p) => p.active)) {
      final step = payment.intervalDays < 1 ? 1 : payment.intervalDays;
      DateTime cursor = payment.nextDueAt;
      while (!cursor.isAfter(end)) {
        if (!cursor.isBefore(now)) {
          if (payment.direction == 'in') {
            scheduledNet += payment.amountCents;
            scheduledFutureIncoming += payment.amountCents;
          } else {
            scheduledNet -= payment.amountCents;
          }
        }
        cursor = cursor.add(Duration(days: step));
        if (cursor.isAtSameMomentAs(payment.nextDueAt)) break;
      }
    }

    final daysToGo = end.difference(now).inDays < 1
        ? 0
        : end.difference(now).inDays;
    return (
      dailyNet: dailyNet,
      daysToGo: daysToGo,
      scheduledNet: scheduledNet,
      scheduledFutureIncoming: scheduledFutureIncoming,
      monthIncomeCents: monthIncomeCents,
    );
  }

  int forecastCashToEndOfMonth() {
    final p = _monthEndProjectionPieces();
    final taxRate = settings.getActiveTaxRate();
    int projectedTaxReserve = 0;
    if (taxRate > 0) {
      final projectedMonthIncome =
          p.monthIncomeCents + p.scheduledFutureIncoming;
      projectedTaxReserve = (projectedMonthIncome * taxRate / 100).round();
    }
    return totalBalanceCents() +
        p.dailyNet * p.daysToGo +
        p.scheduledNet -
        projectedTaxReserve;
  }

  int forecastTaxReserveToEndOfMonth() {
    final p = _monthEndProjectionPieces();
    final taxRate = settings.getActiveTaxRate();
    if (taxRate <= 0) return 0;
    final projectedMonthIncome = p.monthIncomeCents + p.scheduledFutureIncoming;
    return (projectedMonthIncome * taxRate / 100).round();
  }

  /// Сумма доходов (direction 'in', не voided) за указанный год.
  int annualIncomeCents({int? year}) {
    final y = year ?? DateTime.now().year;
    var sum = 0;
    for (final t in _moneyTransactions) {
      if (t.voided || t.direction != 'in') continue;
      if (t.createdAt.year != y) continue;
      sum += t.amountCents;
    }
    return sum;
  }

  /// Прогресс годового дохода против NPD-лимита (0..1).
  double get taxRadarProgress {
    final limit = settings.taxIncomeLimitCents;
    if (limit <= 0) return 0.0;
    final p = annualIncomeCents() / limit;
    if (p < 0) return 0.0;
    if (p > 1) return 1.0;
    return p.toDouble();
  }

  /// Остаток до NPD-лимита (центы, >= 0).
  int get taxRadarLeftCents {
    final left = settings.taxIncomeLimitCents - annualIncomeCents();
    return left < 0 ? 0 : left;
  }

  // Алиасы из spec для совместимости.
  double get annualIncomeNpdLimitProgress => taxRadarProgress;
  int get annualIncomeLeftCents => taxRadarLeftCents;

  @override
  void notifyListeners() {
    _viewsDirty = true;
    _clientsView = null;
    _objectsView = null;
    _jobsView = null;
    _stagesView = null;
    _materialsView = null;
    _sessionsView = null;
    _accountsView = null;
    _moneyTransactionsView = null;
    _shiftsView = null;
    _inventoryItemsView = null;
    _stockMovementsView = null;
    _appointmentsView = null;
    _bookingResourcesView = null;
    _remindersView = null;
    _employeesView = null;
    _timeEntriesView = null;
    _employeePaymentsView = null;
    _intCache.clear();
    _earnedCache.clear();
    _balanceCache.clear();
    super.notifyListeners();
  }

  void _ensureViews() {
    if (_viewsDirty) {
      _clientsView = List.unmodifiable(_clients);
      _objectsView = List.unmodifiable(_objects);
      _jobsView = List.unmodifiable(_jobs);
      _stagesView = List.unmodifiable(_stages);
      _materialsView = List.unmodifiable(_materials);
      _sessionsView = List.unmodifiable(_sessions);
      _accountsView = List.unmodifiable(_accounts);
      _moneyTransactionsView = List.unmodifiable(_moneyTransactions);
      _shiftsView = List.unmodifiable(_shifts);
      _inventoryItemsView = List.unmodifiable(_inventoryItems);
      _stockMovementsView = List.unmodifiable(_stockMovements);
      _appointmentsView = List.unmodifiable(_appointments);
      _bookingResourcesView = List.unmodifiable(_bookingResources);
      _remindersView = List.unmodifiable(_reminders);
      _employeesView = List.unmodifiable(_employees);
      _timeEntriesView = List.unmodifiable(_timeEntries);
      _employeePaymentsView = List.unmodifiable(_employeePayments);
      _viewsDirty = false;
    }
  }

  final Map<String, int> _earnedCache = {};
  final Map<String, int> _balanceCache = {};

  bool get isLoaded => _loaded;

  List<Client> get clients {
    _ensureViews();
    return _clientsView!;
  }

  List<WorkObject> get objects {
    _ensureViews();
    return _objectsView!;
  }

  List<Job> get jobs {
    _ensureViews();
    return _jobsView!;
  }

  List<JobStage> get stages {
    _ensureViews();
    return _stagesView!;
  }

  List<MaterialItem> get materials {
    _ensureViews();
    return _materialsView!;
  }

  List<WorkSession> get sessions {
    _ensureViews();
    return _sessionsView!;
  }

  List<Account> get accounts {
    _ensureViews();
    return _accountsView!;
  }

  List<MoneyTransaction> get moneyTransactions {
    _ensureViews();
    return _moneyTransactionsView!;
  }

  List<CashShift> get shifts {
    _ensureViews();
    return _shiftsView!;
  }

  List<InventoryItem> get inventoryItems {
    _ensureViews();
    return _inventoryItemsView!;
  }

  List<StockMovement> get stockMovements {
    _ensureViews();
    return _stockMovementsView!;
  }

  List<Appointment> get appointments {
    _ensureViews();
    return _appointmentsView!;
  }

  List<BookingResource> get bookingResources {
    _ensureViews();
    return _bookingResourcesView!;
  }

  List<ClientReminder> get reminders {
    _ensureViews();
    return _remindersView!;
  }

  List<Employee> get employees {
    _ensureViews();
    return _employeesView!;
  }

  Employee? get selfEmployee =>
      _employees
          .where((e) => e.role == 'owner' && e.name == 'Я' && !e.archived)
          .cast<Employee?>()
          .firstOrNull ??
      (_employees.isNotEmpty ? _employees.first : null);
  List<TimeEntry> get timeEntries {
    _ensureViews();
    return _timeEntriesView!;
  }

  List<EmployeePayment> get employeePayments {
    _ensureViews();
    return _employeePaymentsView!;
  }

  /// Локации (§5.6, Э5).
  List<StockLocation> get locations => List.unmodifiable(_locations);

  /// Материализованные остатки позиций на локациях.
  List<StockLevel> get stockLevels => List.unmodifiable(_stockLevels);

  /// Партии со сроками годности.
  List<StockBatch> get batches => List.unmodifiable(_batches);

  /// Перемещения между локациями.
  List<StockTransfer> get transfers => List.unmodifiable(_transfers);

  /// Закупки: экрану приёмки (§5.6) нужен весь список, а не только строки
  /// одного поставщика — «непринятые» ищутся по всем поставщикам сразу.
  List<Purchase> get purchases => List.unmodifiable(_purchases);

  Client? clientById(String id) {
    for (final c in _clients) {
      if (c.id == id) return c;
    }
    return null;
  }

  WorkObject? objectById(String? id) {
    if (id == null) return null;
    for (final o in _objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  Job? jobById(String id) {
    for (final j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  Appointment? appointmentById(String id) {
    for (final a in _appointments) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> load() async {
    final core = await Future.wait([
      _clientRepo.getAll(),
      _objectRepo.getAll(),
      _jobRepo.getAll(),
      _stageRepo.getAll(),
      _materialRepo.getAll(),
      _sessionRepo.getAll(),
    ]);
    _clients = core[0] as List<Client>;
    _objects = core[1] as List<WorkObject>;
    _jobs = core[2] as List<Job>;
    _stages = core[3] as List<JobStage>;
    _materials = core[4] as List<MaterialItem>;
    _sessions = core[5] as List<WorkSession>;

    final accounts = await _accountRepo.getAll();
    _accounts = accounts;
    if (_accounts.isEmpty) {
      final acc = Account(
        id: newId(),
        name: 'Наличные',
        type: 'cash',
        createdAt: DateTime.now(),
      );
      await _accountRepo.save(acc);
      _accounts = [acc];
    }

    final rest = await Future.wait([
      _moneyTxRepo.getAll(),
      _shiftRepo.getAll(),
      _inventoryRepo.getAll(),
      _stockMovementRepo.getAll(),
      _appointmentRepo.getAll(),
      _bookingResourceRepo.getAll(),
      _reminderRepo.getAll(includeDone: true),
      _supplierRepo.getAll(),
      _purchaseRepo.getAll(),
      _employeeRepo.getAll(),
      _timeEntryRepo.getAll(),
      _paymentRepo.getAll(),
      _attributeRepo.getAll(),
    ]);
    _moneyTransactions = rest[0] as List<MoneyTransaction>;
    _shifts = rest[1] as List<CashShift>;
    _inventoryItems = rest[2] as List<InventoryItem>;
    _stockMovements = rest[3] as List<StockMovement>;
    _appointments = rest[4] as List<Appointment>;
    _bookingResources = rest[5] as List<BookingResource>;
    _reminders = rest[6] as List<ClientReminder>;
    _suppliers = rest[7] as List<Supplier>;
    _purchases = rest[8] as List<Purchase>;
    _employees = rest[9] as List<Employee>;
    if (!_employees.any(
      (e) => e.role == 'owner' && e.name == 'Я' && !e.archived,
    )) {
      final self = Employee(
        id: newId(),
        name: 'Я',
        role: 'owner',
        payType: 'salary',
        rateCents: 0,
        percent: 0,
        createdAt: DateTime.now(),
      );
      await _employeeRepo.save(self);
      _employees = [self, ..._employees];
    }
    _timeEntries = rest[10] as List<TimeEntry>;
    _employeePayments = rest[11] as List<EmployeePayment>;
    _attributes = rest[12] as List<EntityAttribute>;
    _attributeTypes = await _attributeTypeRepo.getAll();
    _purchaseLines = await _purchaseRepo.getAllLines();
    _compositionLines = await _compositionRepo.getAll();

    _closedPeriods = (await _appDatabase.periodClosures())
        .map((m) => ClosedPeriod.fromMap(Map<String, Object?>.from(m)))
        .toList();
    _recurringPayments = await _recurringRepo.getAll();
    try {
      await _scheduleRecurringReminder();
    } catch (_) {}
    _payrollPeriods = await _payrollRepo.getAll();
    // Если миграция v26 упала, база восстановлена на v25, и таблиц истории
    // начислений ещё нет. Экран должен открыться, а не падать: данные пустые,
    // пользователь увидит предложение восстановить копию.
    final tables = await _appDatabase.existingTables();
    if (tables.contains('payslips') &&
        tables.contains('pay_conditions') &&
        tables.contains('accrual_entries')) {
      _payslips = await _payslipRepo.getAll();
      _payConditions = await _payConditionRepo.getAll();
      _accrualEntries = await _accrualEntryRepo.getAllIncludingDeleted();
    } else {
      _payslips = const [];
      _payConditions = const [];
      _accrualEntries = const [];
    }
    _obligations = await _obligationRepo.getAll();
    _leads = await _leadRepo.getAll();
    _quotes = await _quoteRepo.getAll();
    _credits = await _creditRepo.getAll();
    _creditChanges = await _appDatabase.creditChanges();

    // ── Склад по точкам (Э5) ──────────────────────────────────────────
    _locations = await _locationRepo.getAll();
    _stockLevels = await _locationRepo.getAllLevels();
    _batches = await _batchRepo.getAll();
    _transfers = await _transferRepo.getAll();
    _transferLines = <StockTransferLine>[];
    for (final t in _transfers) {
      final lines = await _transferRepo.linesForTransfer(t.id);
      _transferLines = [..._transferLines, ...lines];
    }

    // ── Просрочка ─────────────────────────────────────────────────────
    await _reconcileEmployeePayments();
    // §12.1: срок истёк — статус меняется при открытии, деньги остаются на балансе.
    await expireCredits();

    if (_bookingResources.isEmpty) {
      final r = BookingResource(
        id: newId(),
        name: 'Основной',
        createdAt: DateTime.now(),
      );
      await _bookingResourceRepo.save(r);
      _bookingResources = [r];
    }
    _loaded = true;
    notifyListeners();
  }

  // Clients
  Future<Client> createClient({
    required String name,
    String phone = '',
    String? note,
  }) async {
    final now = DateTime.now();
    final client = Client(
      id: newId(),
      name: name.trim(),
      phone: phone.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _clientRepo.save(client);
    _clients = [client, ..._clients];
    notifyListeners();
    return client;
  }

  Future<void> updateClient(Client client) async {
    final updated = client.copyWith(updatedAt: DateTime.now());
    await _clientRepo.save(updated);
    final index = _clients.indexWhere((c) => c.id == updated.id);
    if (index == -1) {
      _clients = [updated, ..._clients];
    } else {
      _clients[index] = updated;
    }
    notifyListeners();
  }

  Future<void> deleteClient(String id) async {
    await _clientRepo.delete(id);
    _clients = _clients.where((c) => c.id != id).toList();
    final objectIds = _objects
        .where((o) => o.clientId == id)
        .map((o) => o.id)
        .toSet();
    _objects = _objects.where((o) => o.clientId != id).toList();
    final jobIds = _jobs
        .where((j) => j.clientId == id)
        .map((j) => j.id)
        .toSet();
    _jobs = _jobs.where((j) => j.clientId != id).toList();
    _stages = _stages.where((s) => !jobIds.contains(s.jobId)).toList();
    _materials = _materials.where((m) => !jobIds.contains(m.jobId)).toList();
    _sessions = _sessions.where((s) => !jobIds.contains(s.jobId)).toList();
    // objects of client removed above; also jobs with those objects already by client
    objectIds;
    notifyListeners();
  }

  // Client duplicate handling
  List<List<Client>> findDuplicateClients() {
    final grouped = <String, List<Client>>{};
    for (final client in _clients) {
      final key = client.duplicateKey;
      if (key == null || key.isEmpty) continue;
      grouped.putIfAbsent(key, () => <Client>[]).add(client);
    }
    return grouped.values
        .where((group) => group.length > 1)
        .map((group) => List<Client>.unmodifiable(group))
        .toList();
  }

  Future<void> mergeClientInto({
    required String sourceId,
    required String targetId,
  }) async {
    if (sourceId == targetId) {
      throw ArgumentError('Клиенты должны различаться.');
    }
    final source = clientById(sourceId);
    final target = clientById(targetId);
    if (source == null || target == null) {
      throw StateError('Клиент не найден.');
    }
    ensurePeriodOpen();

    final movedObjectIds = _objects
        .where((o) => o.clientId == sourceId)
        .map((o) => o.id)
        .toList();
    final movedJobIds = _jobs
        .where(
          (j) =>
              j.clientId == sourceId ||
              (j.objectId != null && movedObjectIds.contains(j.objectId)),
        )
        .map((j) => j.id)
        .toList();

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    final mergedName = target.name.trim().isEmpty
        ? source.name.trim()
        : target.name;
    final mergedPhone = target.phone.trim().isEmpty
        ? source.phone.trim()
        : target.phone;
    final mergedNote = _mergeClientNotes(target, source);

    final db = _appDatabase.database;
    await db.transaction((txn) async {
      final jobPlaceholders = List.filled(movedJobIds.length, '?').join(',');
      final objectPlaceholders = List.filled(
        movedObjectIds.length,
        '?',
      ).join(',');

      await txn.update(
        'objects',
        {'client_id': targetId, 'updated_at': nowMs},
        where: 'client_id = ? AND deleted_at IS NULL',
        whereArgs: [sourceId],
      );

      final jobWhere = movedObjectIds.isEmpty
          ? 'client_id = ? AND deleted_at IS NULL'
          : '(client_id = ? OR object_id IN ($objectPlaceholders)) AND deleted_at IS NULL';
      final jobArgs = movedObjectIds.isEmpty
          ? <Object?>[sourceId]
          : <Object?>[sourceId, ...movedObjectIds];
      await txn.update(
        'jobs',
        {'client_id': targetId, 'updated_at': nowMs},
        where: jobWhere,
        whereArgs: jobArgs,
      );

      final appointmentWhere = movedObjectIds.isEmpty
          ? 'client_id = ? AND deleted_at IS NULL'
          : '(client_id = ? OR object_id IN ($objectPlaceholders)) AND deleted_at IS NULL';
      final appointmentArgs = movedObjectIds.isEmpty
          ? <Object?>[sourceId]
          : <Object?>[sourceId, ...movedObjectIds];
      await txn.update(
        'appointments',
        {'client_id': targetId, 'updated_at': nowMs},
        where: appointmentWhere,
        whereArgs: appointmentArgs,
      );

      final reminderWhere = movedJobIds.isEmpty
          ? 'deleted_at IS NULL AND client_id = ?'
          : 'deleted_at IS NULL AND (client_id = ? OR job_id IN ($jobPlaceholders))';
      final reminderArgs = movedJobIds.isEmpty
          ? <Object?>[sourceId]
          : <Object?>[sourceId, ...movedJobIds];
      await txn.update(
        'client_reminders',
        {'client_id': targetId, 'updated_at': nowMs},
        where: reminderWhere,
        whereArgs: reminderArgs,
      );

      final moneySqlWhere = movedJobIds.isEmpty
          ? 'client_id = ? AND deleted_at IS NULL'
          : '(client_id = ? OR job_id IN ($jobPlaceholders)) AND deleted_at IS NULL';
      final moneyArgs = movedJobIds.isEmpty
          ? <Object?>[sourceId]
          : <Object?>[sourceId, ...movedJobIds];
      await txn.update(
        'money_transactions',
        {'client_id': targetId, 'updated_at': nowMs},
        where: moneySqlWhere,
        whereArgs: moneyArgs,
      );

      await txn.update(
        'clients',
        {
          'name': mergedName,
          'phone': mergedPhone,
          'note': mergedNote,
          'updated_at': nowMs,
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [targetId],
      );
    });

    // Soft-delete source client via repository; do not call store-level delete.
    await _clientRepo.delete(sourceId);

    // Reload affected lists.
    _objects = await _objectRepo.getAll();
    _jobs = await _jobRepo.getAll();
    _stages = await _stageRepo.getAll();
    _materials = await _materialRepo.getAll();
    _sessions = await _sessionRepo.getAll();
    _appointments = await _appointmentRepo.getAll();
    _reminders = await _reminderRepo.getAll(includeDone: true);
    _moneyTransactions = await _moneyTxRepo.getAll();
    _clients = await _clientRepo.getAll();

    try {
      await auditAction(
        action: 'client.merge',
        entity: 'client',
        entityId: targetId,
        before: {
          'source_id': sourceId,
          'target_id': targetId,
          'source_name': source.name,
          'target_name': target.name,
        },
        after: {
          'source_id': sourceId,
          'target_id': targetId,
          'moved_object_ids': movedObjectIds,
          'moved_job_ids': movedJobIds,
          'merged_name': mergedName,
          'merged_phone': mergedPhone,
          'merged_note': mergedNote,
        },
      );
    } catch (_) {}

    notifyListeners();
  }

  String? _mergeClientNotes(Client target, Client source) {
    final targetNote = target.note?.trim();
    final sourceNote = source.note?.trim();
    final hasTarget = targetNote != null && targetNote.isNotEmpty;
    final hasSource = sourceNote != null && sourceNote.isNotEmpty;
    if (hasTarget && !hasSource) return targetNote;
    if (!hasTarget && hasSource) return sourceNote;
    if (!hasTarget && !hasSource) return null;
    if (targetNote == sourceNote) return targetNote;
    return '${targetNote!}\n---\n${sourceNote!}';
  }

  // Objects
  Future<WorkObject> createObject({
    required String clientId,
    required String title,
    String address = '',
    String? note,
  }) async {
    final obj = WorkObject(
      id: newId(),
      clientId: clientId,
      title: title.trim(),
      address: address.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now(),
    );
    await _objectRepo.save(obj);
    _objects = [obj, ..._objects];
    notifyListeners();
    return obj;
  }

  Future<void> updateObject(WorkObject obj) async {
    await _objectRepo.save(obj);
    final index = _objects.indexWhere((o) => o.id == obj.id);
    if (index == -1) {
      _objects = [obj, ..._objects];
    } else {
      _objects[index] = obj;
    }
    notifyListeners();
  }

  Future<void> deleteObject(String id) async {
    final affected = _jobs.where((j) => j.objectId == id).toList();
    await _objectRepo.delete(id);
    _objects = _objects.where((o) => o.id != id).toList();
    for (final job in affected) {
      final updated = job.copyWith(objectId: null, updatedAt: DateTime.now());
      await _jobRepo.save(updated);
    }
    _jobs = _jobs
        .map((j) => j.objectId == id ? j.copyWith(objectId: null) : j)
        .toList();
    notifyListeners();
  }

  // Jobs
  Future<Job> createJob({
    required String clientId,
    String? objectId,
    required String title,
    JobStatus status = JobStatus.nuevo,
    JobPriority priority = JobPriority.medium,
    int priceCents = 0,
    int costCents = 0,
    DateTime? dueDate,
    String? note,
    String? assigneeId,
    String? tags,
    String? leadId,
  }) async {
    final now = DateTime.now();
    final job = Job(
      id: newId(),
      clientId: clientId,
      objectId: objectId,
      assigneeId: assigneeId,
      tags: tags?.trim().isEmpty == true ? null : tags?.trim(),
      leadId: leadId,
      title: title.trim(),
      status: status,
      priority: priority,
      priceCents: priceCents,
      costCents: costCents,
      dueDate: dueDate,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _jobRepo.save(job);
    _jobs = [job, ..._jobs];
    notifyListeners();
    await syncJobObligations(job.id);
    return job;
  }

  Future<void> updateJob(Job job) async {
    ensurePeriodOpen();
    final updated = job.copyWith(updatedAt: DateTime.now());
    await _jobRepo.save(updated);
    final index = _jobs.indexWhere((j) => j.id == updated.id);
    if (index == -1) {
      _jobs = [updated, ..._jobs];
    } else {
      _jobs[index] = updated;
    }
    notifyListeners();
    await syncJobObligations(updated.id);
  }

  Future<void> setJobStatus(String jobId, JobStatus status) async {
    ensurePeriodOpen();
    final job = jobById(jobId);
    if (job == null) return;
    final now = DateTime.now();
    var updated = job.copyWith(status: status, updatedAt: now);
    if (status == JobStatus.inProgress && job.startedAt == null) {
      updated = updated.copyWith(startedAt: now);
    }
    if ((status == JobStatus.done || status == JobStatus.closed) &&
        job.finishedAt == null) {
      updated = updated.copyWith(finishedAt: now);
    }
    await _jobRepo.save(updated);
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index != -1) _jobs[index] = updated;
    if (status == JobStatus.done &&
        !_reminders.any((r) => r.jobId == jobId && r.type == 'warranty')) {
      await createReminder(
        clientId: job.clientId,
        jobId: jobId,
        type: 'warranty',
        title: 'Проверить гарантию: ${job.title}',
        dueAt: now.add(const Duration(days: 180)),
      );
    }
    notifyListeners();
  }

  Future<void> deleteJob(String id) async {
    await _jobRepo.delete(id);
    await _obligationRepo.deleteForJob(id);
    _obligations = _obligations.where((o) => o.jobId != id).toList();
    _jobs = _jobs.where((j) => j.id != id).toList();
    _stages = _stages.where((s) => s.jobId != id).toList();
    _materials = _materials.where((m) => m.jobId != id).toList();
    _sessions = _sessions.where((s) => s.jobId != id).toList();
    notifyListeners();
  }

  Future<void> setArchived(String id, bool value) async {
    await _jobRepo.setArchived(id, value);
    final job = jobById(id);
    if (job != null) {
      final index = _jobs.indexWhere((j) => j.id == id);
      if (index != -1) _jobs[index] = job.copyWith(archived: value);
    }
    notifyListeners();
  }

  Future<void> setJobPinned(String id, bool value) async {
    await _jobRepo.setPinned(id, value);
    final job = jobById(id);
    if (job != null) {
      final index = _jobs.indexWhere((j) => j.id == id);
      if (index != -1) _jobs[index] = job.copyWith(pinned: value);
    }
    notifyListeners();
  }

  /// Дублирует заказ: новый заказ с теми же строками, пустыми датами,
  /// статус nuevo, тот же клиент. Строки копируются с текущими
  /// `price_cents` и `cost_at_order_cents` (снимок на момент дублирования).
  Future<Job> duplicateJob(String sourceJobId) async {
    ensurePeriodOpen();
    final source = _jobs.firstWhere(
      (j) => j.id == sourceJobId,
      orElse: () => throw ArgumentError('Заказ $sourceJobId не найден'),
    );
    final lines = jobLines(sourceJobId);

    // Создаём новый заказ без строк
    final newJob = await createJob(
      clientId: source.clientId,
      title: '${source.title} (копия)',
      status: JobStatus.nuevo,
      priority: source.priority,
      priceCents: 0,
      costCents: 0,
      dueDate: null,
      note: source.note,
      assigneeId: source.assigneeId,
      tags: source.tags,
    );

    // Копируем строки с текущими снимками цен
    for (final line in lines) {
      await addMaterial(
        jobId: newJob.id,
        name: line.name,
        quantity: line.quantity,
        unit: line.unit,
        priceCents: line.priceCents,
        itemId: line.itemId,
        kind: line.kind,
        costAtOrderCents: line.costAtOrderCents,
        discountCents: line.discountCents,
      );
    }

    // Пересчитываем итог (синхронизирует обязательства)
    await recalcJobTotals(newJob.id);
    return newJob;
  }

  List<Job> jobsByStatus(JobStatus status) =>
      _jobs.where((j) => !j.archived && j.status == status).toList();

  List<Job> jobsForClient(String clientId) =>
      _jobs.where((j) => j.clientId == clientId && !j.archived).toList();

  List<Job> jobsForObject(String objectId) =>
      _jobs.where((j) => j.objectId == objectId && !j.archived).toList();

  // Stages
  List<JobStage> stagesForJob(String jobId) =>
      _stages.where((s) => s.jobId == jobId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<JobStage> addStage(String jobId, String title) async {
    final existing = stagesForJob(jobId);
    final stage = JobStage(
      id: newId(),
      jobId: jobId,
      title: title.trim(),
      sortOrder: (existing.length + 1).toDouble(),
    );
    await _stageRepo.save(stage);
    _stages = [..._stages, stage];
    notifyListeners();
    return stage;
  }

  Future<void> toggleStage(String stageId) async {
    final index = _stages.indexWhere((s) => s.id == stageId);
    if (index == -1) return;
    final updated = _stages[index].copyWith(done: !_stages[index].done);
    await _stageRepo.save(updated);
    _stages[index] = updated;
    notifyListeners();
  }

  Future<void> deleteStage(String stageId) async {
    await _stageRepo.delete(stageId);
    _stages = _stages.where((s) => s.id != stageId).toList();
    notifyListeners();
  }

  // Materials
  List<MaterialItem> materialsForJob(String jobId) =>
      _materials.where((m) => m.jobId == jobId).toList();

  int totalMaterialCents(String jobId) => _intCache.putIfAbsent(
    'materials:$jobId',
    () => materialsForJob(jobId).fold(0, (sum, m) => sum + m.totalCents),
  );

  Future<MaterialItem> addMaterial({
    required String jobId,
    required String name,
    double quantity = 1,
    String unit = 'шт',
    int priceCents = 0,
    String? itemId,
    String kind = 'work',
    int costAtOrderCents = 0,
    int discountCents = 0,
  }) async {
    final item = MaterialItem(
      id: newId(),
      jobId: jobId,
      name: name.trim(),
      quantity: quantity,
      unit: unit.trim().isEmpty ? 'шт' : unit.trim(),
      priceCents: priceCents,
      itemId: itemId,
      kind: kind,
      costAtOrderCents: costAtOrderCents,
      discountCents: discountCents,
      createdAt: DateTime.now(),
    );
    await _materialRepo.save(item);
    _materials = [..._materials, item];
    _intCache.remove('cost:$jobId');
    notifyListeners();
    return item;
  }

  /// Добавляет в заказ строку из каталога со снимком себестоимости.
  ///
  /// Снимок берётся здесь, а не в UI: цена каталога может измениться, пока
  /// заказ открыт, и маржа не должна «поехать» задним числом.
  Future<MaterialItem> addCatalogLine({
    required String jobId,
    required String itemId,
    double quantity = 1,
  }) async {
    final item = _inventoryItems.firstWhere(
      (i) => i.id == itemId,
      orElse: () => throw ArgumentError('Позиция каталога не найдена'),
    );
    return addMaterial(
      jobId: jobId,
      name: item.name,
      quantity: quantity,
      unit: item.unit,
      priceCents: item.sellPriceCents,
      itemId: item.id,
      kind: item.kind == 'service' ? 'work' : 'good',
      costAtOrderCents: item.costCents,
    );
  }

  /// Строки заказа: работы и товары.
  ///
  /// Отдельный геттер нужен, чтобы экраны не смешивали «материалы» со
  /// старым смыслом (расходники) и строки заказа из каталога.
  List<MaterialItem> jobLines(String jobId) =>
      _materials.where((m) => m.jobId == jobId).toList();

  /// Создаёт или обновляет строку заказа.
  ///
  /// [costAtOrderCents] по умолчанию берётся у позиции каталога: снимок
  /// себестоимости должен фиксироваться в момент оформления, иначе маржа
  /// изменится после правки цены товара.
  Future<MaterialItem> createJobLine(
    String jobId, {
    String? itemId,
    String kind = 'work',
    String? name,
    double qty = 1,
    String unit = 'шт',
    int priceCents = 0,
    int? costAtOrderCents,
    int discountCents = 0,
  }) async {
    InventoryItem? catalogItem;
    if (itemId != null) {
      for (final candidate in _inventoryItems) {
        if (candidate.id == itemId) {
          catalogItem = candidate;
          break;
        }
      }
    }
    return addMaterial(
      jobId: jobId,
      name: name ?? catalogItem?.name ?? 'Строка',
      quantity: qty,
      unit: unit == 'шт' && catalogItem != null ? catalogItem.unit : unit,
      priceCents: priceCents == 0 && catalogItem != null
          ? catalogItem.sellPriceCents
          : priceCents,
      itemId: itemId,
      kind: kind,
      costAtOrderCents:
          costAtOrderCents ??
          (catalogItem == null
              ? 0
              : (catalogItem.kind == 'service' ? 0 : catalogItem.costCents)),
      discountCents: discountCents,
    );
  }

  /// Обновляет строку заказа и пересчитывает итоги заказа.
  Future<void> updateJobLine(
    String lineId, {
    double? qty,
    int? priceCents,
    int? costAtOrderCents,
    int? discountCents,
    String? name,
    String? unit,
  }) async {
    MaterialItem? current;
    for (final m in _materials) {
      if (m.id == lineId) {
        current = m;
        break;
      }
    }
    if (current == null) return;
    // copyWith отличает «не передано» от значения, поэтому null не пропускаем.
    final updated = current.copyWith(
      quantity: qty ?? current.quantity,
      priceCents: priceCents ?? current.priceCents,
      costAtOrderCents: costAtOrderCents ?? current.costAtOrderCents,
      discountCents: discountCents ?? current.discountCents,
      name: name ?? current.name,
      unit: unit ?? current.unit,
    );
    await _materialRepo.save(updated);
    _materials = [
      for (final m in _materials) if (m.id == lineId) updated else m,
    ];
    _intCache.remove('cost:${updated.jobId}');
    notifyListeners();
  }

  /// Строка из каталога с подстановкой цены, единицы и себестоимости.
  Future<MaterialItem> addLineFromCatalog(
    String jobId,
    String itemId, {
    double qty = 1,
  }) => addCatalogLine(jobId: jobId, itemId: itemId, quantity: qty);

  /// Пересчитывает цену и себестоимость заказа по строкам.
  ///
  /// Ручное значение `cost_cents` остаётся только у заказов без строк:
  /// иначе правка цены каталога задним числом меняла бы маржу закрытых
  /// заказов, а ручной ввод спорил бы со снимками в строках.
  Future<void> recalcJobTotals(String jobId) async {
    final lines = jobLines(jobId);
    if (lines.isEmpty) return;
    var price = 0;
    var cost = 0;
    for (final line in lines) {
      price += line.totalCents - line.discountCents;
      cost += line.costTotalCents;
    }
    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    final job = _jobs[idx];
    if (job.priceCents == price && job.costCents == cost) return;
    final updated = job.copyWith(priceCents: price, costCents: cost);
    await _jobRepo.save(updated);
    _jobs[idx] = updated;
    _intCache
      ..remove('cost:$jobId')
      ..remove('paid:$jobId');
    notifyListeners();
    // Итог заказа изменился — обязательство должно следовать за суммой,
    // иначе «Принять оплату» в заказе предложит устаревший остаток.
    await syncJobObligations(jobId);
  }

  // Атрибуты сущностей (entity_attributes): параметры изделия, свойства клиента.

  /// Помечает позицию каталога «популярной» — фильтр на экране каталога.
  ///
  /// Отдельного столбца в `inventory_items` под это нет (миграции Э0 уже
  /// закрыты), а заводить boolean-колонку ради одного фильтра дороже, чем
  /// пара ключ/значение в `entity_attributes`.
  Future<void> setItemPopular(String itemId, bool popular) => setAttribute(
    entityType: 'item',
    entityId: itemId,
    key: 'popular',
    valueText: popular ? '1' : null,
  );

  bool isItemPopular(String itemId) =>
      attributeValue('item', itemId, 'popular') != null;

  /// Списание материалов заказа со склада по составу его каталожных строк.
  ///
  /// [lineIds] — какие строки списать (пустой список = ничего). Расход
  /// считается как `кол-во строки × кол-во компонента состава`; строки без
  /// `item_id` и компоненты ручного труда пропускаются. Ссылка движения —
  /// на заказ, чтобы история склада показывала, ради чего ушло.
  Future<int> writeOffJobMaterials(
    String jobId, {
    required List<String> lineIds,
  }) async {
    if (lineIds.isEmpty) return 0;
    final selected = lineIds.toSet();
    var written = 0;
    for (final line in jobLines(jobId)) {
      if (!selected.contains(line.id)) continue;
      final itemId = line.itemId;
      if (itemId == null) continue;
      for (final part in itemComposition(itemId)) {
        if (part.isLabor) continue;
        final componentId = part.componentId;
        if (componentId == null) continue;
        final qty = line.quantity * part.qty;
        if (qty <= 0) continue;
        await adjustStock(
          itemId: componentId,
          delta: -qty,
          type: 'writeoff',
          reason: 'order',
          refType: 'job',
          refId: jobId,
          note: 'Состав: ${line.name}',
        );
        written++;
      }
    }
    return written;
  }

  /// Атрибуты сущности в порядке отображения.
  List<EntityAttribute> attributesOf(String entityType, String entityId) =>
      _attributes
          .where((a) => a.entityType == entityType && a.entityId == entityId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Значение одного атрибута или `null`.
  String? attributeValue(String entityType, String entityId, String key) {
    for (final a in _attributes) {
      if (a.entityType == entityType &&
          a.entityId == entityId &&
          a.key == key) {
        return a.valueText ?? a.valueNum?.toString();
      }
    }
    return null;
  }

  /// Создаёт или обновляет атрибут по ключу.
  Future<void> setAttribute({
    required String entityType,
    required String entityId,
    required String key,
    String? valueText,
    double? valueNum,
    double sortOrder = 0,
  }) async {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) return;
    EntityAttribute? existing;
    for (final a in _attributes) {
      if (a.entityType == entityType &&
          a.entityId == entityId &&
          a.key == trimmedKey) {
        existing = a;
        break;
      }
    }
    final now = DateTime.now();
    final attribute = EntityAttribute(
      id: existing?.id ?? newId(),
      entityType: entityType,
      entityId: entityId,
      key: trimmedKey,
      valueText: valueText,
      valueNum: valueNum,
      sortOrder: sortOrder,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _attributeRepo.save(attribute);
    _attributes = [
      for (final a in _attributes)
        if (a.id == attribute.id) attribute else a,
    ];
    if (!_attributes.any((a) => a.id == attribute.id)) {
      _attributes = [..._attributes, attribute];
    }
    notifyListeners();
  }

  Future<void> deleteAttribute(String id) async {
    await _attributeRepo.delete(id);
    _attributes = _attributes.where((a) => a.id != id).toList();
    notifyListeners();
  }

  /// Типы параметров, доступные для сущности: её собственные и общие (`*`).
  List<AttributeType> attributeTypesOf(String entityType) =>
      _attributeTypes
          .where((t) => t.entityType == entityType || t.isUniversal)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));

  /// Тип параметра по ключу или `null`, если ключ пользовательский.
  AttributeType? attributeType(String entityType, String key) {
    for (final t in _attributeTypes) {
      if (t.key == key && (t.entityType == entityType || t.isUniversal)) {
        return t;
      }
    }
    return null;
  }

  /// Записывает значение параметра, сверив его с типом из справочника (§1.3).
  ///
  /// Это точка входа для интерфейса: строка из поля ввода проходит через
  /// [AttributeType.parse] и в базу попадает уже в нужной колонке — число в
  /// `value_num`, остальное в `value_text`. Без типа ключа значение пишется
  /// как текст, иначе старые пользовательские параметры перестали бы
  /// сохраняться. Бросает [FormatException], если значение не соответствует
  /// типу, — интерфейс показывает подсказку вместо молчаливой порчи данных.
  Future<void> setAttributeValue({
    required String entityType,
    required String entityId,
    required String key,
    required String raw,
    double sortOrder = 0,
  }) async {
    final type = attributeType(entityType, key.trim());
    if (type == null) {
      await setAttribute(
        entityType: entityType,
        entityId: entityId,
        key: key,
        valueText: AttributeType.isBlank(raw) ? null : raw.trim(),
        sortOrder: sortOrder,
      );
      return;
    }
    final parsed = type.parse(raw);
    if (parsed == null) {
      throw FormatException(
        'Значение «${raw.trim()}» не подходит для параметра '
        '«${type.label}» (ожидается ${type.formatHint.toLowerCase()})',
      );
    }
    await setAttribute(
      entityType: entityType,
      entityId: entityId,
      key: key,
      valueText: parsed.text,
      valueNum: parsed.num,
      sortOrder: sortOrder,
    );
  }

  Future<void> deleteMaterial(String id) async {
    String? jobId;
    for (final m in _materials) {
      if (m.id == id) {
        jobId = m.jobId;
        break;
      }
    }
    await _materialRepo.delete(id);
    _materials = _materials.where((m) => m.id != id).toList();
    if (jobId != null) _intCache.remove('cost:$jobId');
    notifyListeners();
  }

  // Sessions
  List<WorkSession> sessionsForJob(String jobId) =>
      _sessions.where((s) => s.jobId == jobId).toList();

  int totalMinutesForJob(String jobId) => _intCache.putIfAbsent(
    'minutes:$jobId',
    () => sessionsForJob(jobId).fold(0, (sum, s) => sum + s.minutes),
  );

  /// Currently running (not finished) work session, if any.
  WorkSession? get openWorkSession {
    for (final s in _sessions) {
      if (s.endedAt == null) return s;
    }
    return null;
  }

  /// Worked seconds for [jobId] today (local day by started_at).
  int workSecondsForJobToday(String jobId) {
    final now = DateTime.now();
    final key = dayKey(now);
    return _sessions
        .where((s) => s.jobId == jobId && dayKey(s.startedAt) == key)
        .fold(0, (sum, s) => sum + workSeconds(s));
  }

  /// Worked seconds today across all jobs (local day by started_at).
  int workSecondsToday() {
    final now = DateTime.now();
    final key = dayKey(now);
    return _sessions
        .where((s) => dayKey(s.startedAt) == key)
        .fold(0, (sum, s) => sum + workSeconds(s));
  }

  /// Total worked seconds for a single session (running sessions use now).
  int workSeconds(WorkSession session) {
    final end = session.endedAt ?? DateTime.now();
    final seconds =
        end.difference(session.startedAt).inSeconds - session.pausedSeconds;
    return seconds.clamp(0, seconds < 0 ? 0 : seconds);
  }

  Future<WorkSession> addSession({
    required String jobId,
    required DateTime startedAt,
    DateTime? endedAt,
    int minutes = 0,
    String? note,
  }) async {
    final session = WorkSession(
      id: 0,
      jobId: jobId,
      startedAt: startedAt,
      endedAt: endedAt,
      minutes: minutes < 0 ? 0 : minutes,
      pausedSeconds: 0,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    final assigned = await _sessionRepo.insertSession(session);
    final stored = session.copyWith(id: assigned);
    _sessions = [stored, ..._sessions];
    notifyListeners();
    return stored;
  }

  /// Start a new work session (optionally linked to a job, or without one).
  Future<void> startWorkSession({String? jobId}) async {
    final session = WorkSession(
      id: 0,
      jobId: jobId,
      startedAt: DateTime.now(),
      pausedSeconds: 0,
    );
    final assigned = await _sessionRepo.insertSession(session);
    final stored = session.copyWith(id: assigned);
    _sessions = [stored, ..._sessions];
    notifyListeners();
  }

  /// Finish the running session with [id].
  Future<void> stopWorkSession(int id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final session = _sessions[idx];
    if (session.endedAt != null) return;
    final updated = session.copyWith(endedAt: DateTime.now());
    await _sessionRepo.save(updated);
    _sessions = [..._sessions]..[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteSession(int id) async {
    await _sessionRepo.delete(id);
    _sessions = _sessions.where((s) => s.id != id).toList();
    notifyListeners();
  }

  // Money
  Account? accountById(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  int balanceCents(String accountId) => _intCache.putIfAbsent(
    'balance:$accountId',
    () => _moneyTransactions
        .where((t) => !t.voided && t.accountId == accountId)
        .fold(0, (s, t) => s + t.signedAmount),
  );

  int totalBalanceCents() => _intCache.putIfAbsent(
    'balance:total',
    () => _accounts.fold(0, (s, a) => s + balanceCents(a.id)),
  );

  CashShift? openShift() {
    for (final s in _shifts) {
      if (s.isOpen) return s;
    }
    return null;
  }

  Future<Account> createAccount({
    required String name,
    String type = 'cash',
    String color = '#007AFF',
  }) async {
    final acc = Account(
      id: newId(),
      name: name.trim(),
      type: type,
      color: color,
      createdAt: DateTime.now(),
    );
    await _accountRepo.save(acc);
    _accounts = [..._accounts, acc];
    notifyListeners();
    return acc;
  }

  Future<void> updateAccount(Account acc) async {
    await _accountRepo.save(acc);
    final idx = _accounts.indexWhere((a) => a.id == acc.id);
    if (idx == -1) {
      _accounts = [..._accounts, acc];
    } else {
      _accounts[idx] = acc;
    }
    notifyListeners();
  }

  Future<void> archiveAccount(String id, bool value) async {
    final acc = accountById(id);
    if (acc == null) return;
    await updateAccount(acc.copyWith(archived: value));
  }

  Future<CashShift> openCashShift({
    required String accountId,
    required int openingCents,
    String? note,
  }) async {
    final shift = CashShift(
      id: newId(),
      accountId: accountId,
      openedAt: DateTime.now(),
      openingCents: openingCents,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      status: 'open',
    );
    await _shiftRepo.save(shift);
    _shifts = [shift, ..._shifts];
    notifyListeners();
    return shift;
  }

  int expectedForShift(CashShift shift) =>
      _intCache.putIfAbsent('shiftExpected:${shift.id}', () {
        final txSum = _moneyTransactions
            .where((t) => !t.voided && t.shiftId == shift.id)
            .fold(0, (s, t) => s + t.signedAmount);
        return shift.openingCents + txSum;
      });

  Future<void> closeCashShift(
    CashShift shift,
    int closingCents, {
    String? note,
  }) async {
    ensurePeriodOpen();
    final expected = expectedForShift(shift);
    final updated = shift.copyWith(
      closedAt: DateTime.now(),
      closingCents: closingCents,
      expectedCents: expected,
      discrepancyCents: closingCents - expected,
      note: note?.trim().isEmpty == true ? shift.note : note?.trim(),
      status: 'closed',
    );
    await _shiftRepo.save(updated);
    final idx = _shifts.indexWhere((s) => s.id == updated.id);
    if (idx != -1) _shifts[idx] = updated;
    notifyListeners();
  }

  Future<MoneyTransaction> addTransaction({
    required String accountId,
    required String kind,
    required String direction,
    required int amountCents,
    String category = '',
    String? note,
    String? clientId,
    String? jobId,
    String? shiftId,
    String? relatedTransactionId,
    String? reversesId,
    String? obligationId,
    String? receiptPath,
    String? paymentMethod,
  }) async {
    if (amountCents <= 0) throw ArgumentError('Сумма должна быть больше 0.');
    ensurePeriodOpen();
    final tx = MoneyTransaction(
      id: newId(),
      accountId: accountId,
      kind: kind,
      direction: direction,
      amountCents: amountCents,
      category: category.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      clientId: clientId,
      jobId: jobId,
      shiftId: shiftId ?? openShift()?.id,
      relatedTransactionId: relatedTransactionId,
      reversesId: reversesId,
      obligationId: obligationId,
      paymentMethod: paymentMethod?.trim().isEmpty == true
          ? null
          : paymentMethod?.trim(),
      receiptPath: receiptPath?.trim().isEmpty == true
          ? null
          : receiptPath?.trim(),
      createdAt: DateTime.now(),
    );
    final updatesOrder =
        tx.isOrderPayment &&
        (obligationId == null || tx.isOrderRefund || tx.reversesId != null);
    if (jobId != null && updatesOrder) {
      final updated = await _saveOrderPayment(tx, jobId);
      if (updated != null) _cacheJobPaymentProgress(updated);
    } else {
      await _moneyTxRepo.save(tx);
    }
    _moneyTransactions = [tx, ..._moneyTransactions];
    try {
      await _appDatabase.audit(
        action: 'money.transaction.add',
        entity: 'money_transaction',
        entityId: tx.id,
        after: tx.toMap(),
      );
    } catch (_) {}
    notifyListeners();
    return tx;
  }

  Future<Obligation?> _saveOrderPayment(MoneyTransaction tx, String jobId) {
    return _appDatabase.database.transaction((txn) async {
      final money = MoneyTransactionRepository(txn);
      final reversalOf = tx.reversesId;
      if (reversalOf != null && await money.hasReversal(reversalOf)) {
        throw StateError('Эта операция уже сторнирована.');
      }
      final obligations = ObligationRepository(txn);
      final orderObligations = await obligations.forJob(jobId);
      final eligible = orderObligations.where(
        (o) =>
            o.direction == 'receivable' &&
            o.kind == 'client_payment' &&
            o.status != 'cancelled',
      );
      final target = tx.obligationId == null
          ? eligible.where((o) => !o.isClosed).firstOrNull ?? eligible.firstOrNull
          : eligible.where((o) => o.id == tx.obligationId).firstOrNull;
      final previousPaid = (await money.forJob(jobId))
          .where(
            (payment) =>
                target == null ||
                payment.obligationId == null ||
                payment.obligationId == target.id,
          )
          .fold<int>(0, (sum, p) => sum + p.orderPaymentCents);
      final nextPaid = previousPaid + tx.orderPaymentCents;
      await money.save(tx);

      if (target != null) {
        // Apply the change in capped cash payments to the stored progress,
        // which can also include customer credit and historical allocations.
        final before = previousPaid.clamp(0, target.amountCents);
        final after = nextPaid.clamp(0, target.amountCents);
        final updated = _jobPaymentProgress(target, after - before);
        if (updated != null) await obligations.save(updated);
        return updated;
      }

      final job = jobById(jobId);
      // Legacy payments can exist without a stored receivable.
      if (!tx.isOrderRefund ||
          orderObligations.isNotEmpty ||
          job == null ||
          job.priceCents <= 0 ||
          previousPaid <= 0 ||
          nextPaid >= job.priceCents) {
        return null;
      }
      final paid = nextPaid.clamp(0, job.priceCents);
      final created = Obligation(
        id: newId(),
        direction: 'receivable',
        kind: 'client_payment',
        counterpartyType: 'client',
        counterpartyId: job.clientId,
        jobId: job.id,
        title: 'Оплата заказа: ${job.title}',
        amountCents: job.priceCents,
        paidCents: paid,
        dueAt: job.dueDate ?? tx.createdAt,
        status: paid > 0 ? 'partial' : 'planned',
        createdAt: tx.createdAt,
        updatedAt: tx.createdAt,
      );
      await obligations.save(created);
      return created;
    });
  }

  Future<void> _applyJobPaymentToObligation(
    String jobId,
    int deltaCents,
  ) async {
    Obligation? target;
    for (final o in _obligations) {
      if (o.jobId == jobId &&
          o.direction == 'receivable' &&
          o.kind == 'client_payment' &&
          o.status != 'cancelled') {
        target = o;
        break;
      }
    }
    if (target == null) return;
    final updated = _jobPaymentProgress(target, deltaCents);
    if (updated == null) return;
    await _obligationRepo.save(updated);
    _cacheJobPaymentProgress(updated);
  }

  Obligation? _jobPaymentProgress(Obligation target, int deltaCents) {
    final paid = (target.paidCents + deltaCents).clamp(0, target.amountCents);
    if (paid == target.paidCents) return null;
    final status = paid >= target.amountCents
        ? 'paid'
        : paid > 0
            ? 'partial'
            : 'planned';
    return target.copyWith(
      paidCents: paid,
      status: status,
      updatedAt: DateTime.now(),
    );
  }

  void _cacheJobPaymentProgress(Obligation updated) {
    final idx = _obligations.indexWhere((o) => o.id == updated.id);
    if (idx == -1) {
      _obligations = [updated, ..._obligations];
    } else {
      _obligations[idx] = updated;
    }
  }

  Future<void> revertTransaction(String txId) async {
    final origin = _moneyTransactions.firstWhere(
      (t) => t.id == txId,
      orElse: () => throw Exception('Transaction not found'),
    );

    // Prevent duplicate reversal
    if (_moneyTransactions.any((t) => t.reversesId == txId)) {
      throw Exception('This transaction has already been reversed');
    }

    ensurePeriodOpen();

    final reversal = await addTransaction(
      accountId: origin.accountId,
      kind: origin.kind,
      direction: origin.direction == 'in' ? 'out' : 'in',
      amountCents: origin.amountCents,
      category: origin.category,
      note: 'Возврат: ${origin.note ?? 'Без комментария'}',
      clientId: origin.clientId,
      jobId: origin.jobId,
      shiftId: origin.shiftId,
      relatedTransactionId: origin.relatedTransactionId,
      reversesId: origin.id,
      obligationId: origin.isOrderPayment ? origin.obligationId : null,
    );

    try {
      await auditAction(
        action: 'money.transaction.revert',
        entity: 'money_transaction',
        entityId: origin.id,
        before: origin.toMap(),
        after: reversal.toMap(),
      );
    } catch (_) {}

    _intCache.clear();
    _balanceCache.clear();
    _earnedCache.clear();
    notifyListeners();
  }

  Future<void> attachReceipt(String transactionId, String sourcePath) async {
    // Path points to a file copied into this device's app documents; only the
    // path string is stored, so it stays device-local in backups/sync.
    ensurePeriodOpen();
    final source = File(sourcePath);
    final dir = await getApplicationDocumentsDirectory();
    final attachDir = Directory('${dir.path}/money_receipts');
    await attachDir.create(recursive: true);
    final base = source.uri.pathSegments.isEmpty
        ? 'file'
        : source.uri.pathSegments.last;
    final name = base.isEmpty ? 'receipt' : base;
    final unique = '${newId()}_$name';
    final dest = File('${attachDir.path}/$unique');
    await source.copy(dest.path);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _moneyTransactions.firstWhere(
      (t) => t.id == transactionId,
      orElse: () => MoneyTransaction(
        id: transactionId,
        accountId: '',
        kind: '',
        direction: '',
        amountCents: 0,
        createdAt: DateTime.now(),
      ),
    );
    await _appDatabase.database.update(
      'money_transactions',
      {'receipt_path': dest.path, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    _moneyTransactions = await _moneyTxRepo.getAll();
    try {
      await auditAction(
        action: 'money.transaction.receipt.attach',
        entity: 'money_transaction',
        entityId: transactionId,
        before: {'receipt_path': existing.receiptPath},
        after: {'receipt_path': dest.path},
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> removeReceipt(String transactionId) async {
    ensurePeriodOpen();
    final existing = _moneyTransactions.firstWhere(
      (t) => t.id == transactionId,
      orElse: () => MoneyTransaction(
        id: transactionId,
        accountId: '',
        kind: '',
        direction: '',
        amountCents: 0,
        createdAt: DateTime.now(),
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _appDatabase.database.update(
      'money_transactions',
      {'receipt_path': null, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [transactionId],
    );
    _moneyTransactions = await _moneyTxRepo.getAll();
    try {
      await auditAction(
        action: 'money.transaction.receipt.remove',
        entity: 'money_transaction',
        entityId: transactionId,
        before: {'receipt_path': existing.receiptPath},
        after: {'receipt_path': null},
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> transferBetweenAccounts(
    String fromAccountId,
    String toAccountId,
    int amountCents, {
    String? note,
  }) async {
    if (amountCents <= 0) throw ArgumentError('Сумма должна быть больше 0.');
    ensurePeriodOpen();
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Счета должны различаться.');
    }
    final from = await addTransaction(
      accountId: fromAccountId,
      kind: 'transfer',
      direction: 'out',
      amountCents: amountCents,
      category: 'Перевод',
      note: note,
      shiftId: openShift()?.id,
    );
    final to = await addTransaction(
      accountId: toAccountId,
      kind: 'transfer',
      direction: 'in',
      amountCents: amountCents,
      category: 'Перевод',
      note: note,
      relatedTransactionId: from.id,
      shiftId: openShift()?.id,
    );
    final linkedFrom = MoneyTransaction(
      id: from.id,
      accountId: from.accountId,
      kind: from.kind,
      direction: from.direction,
      amountCents: from.amountCents,
      category: from.category,
      note: from.note,
      clientId: null,
      jobId: null,
      shiftId: from.shiftId,
      relatedTransactionId: to.id,
      createdAt: from.createdAt,
      voided: from.voided,
    );
    await _moneyTxRepo.save(linkedFrom);
    _moneyTransactions = await _moneyTxRepo.getAll();
    try {
      await _appDatabase.audit(
        action: 'money.transfer',
        entity: 'account',
        after: {
          'from': fromAccountId,
          'to': toAccountId,
          'amountCents': amountCents,
          'fromTransactionId': from.id,
          'toTransactionId': to.id,
        },
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> voidTransaction(String id) async {
    final existing = _moneyTransactions.where((t) => t.id == id).toList();
    if (existing.isNotEmpty) ensurePeriodOpen(existing.first.createdAt);
    await _moneyTxRepo.voidTransaction(id);
    final idx = _moneyTransactions.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _moneyTransactions[idx] = MoneyTransaction.fromMap(
        _moneyTransactions[idx].toMap()..['voided'] = 1,
      );
      // easier: mark by recreating
    }
    // reload list cleanly
    _moneyTransactions = await _moneyTxRepo.getAll();
    notifyListeners();
  }

  int paidForJob(String jobId) => _intCache.putIfAbsent(
    'paid:$jobId',
    () => _moneyTransactions
        .where((t) => t.jobId == jobId)
        .fold(0, (s, t) => s + t.orderPaymentCents),
  );

  /// Себестоимость заказа по строкам.
  ///
  /// `jobs.cost_cents` — ручное число из старых сборок. Как только у заказа
  /// есть строки с себестоимостью, сумма по строкам точнее: цена каталога
  /// могла измениться после оформления. Если строк нет — возвращаем ручное
  /// значение, иначе старые заказы показывали бы нулевую себестоимость.
  int jobCostCents(String jobId) => _intCache.putIfAbsent('cost:$jobId', () {
    final job = _jobs.firstWhere(
      (j) => j.id == jobId,
      orElse: () => throw ArgumentError('Заказ $jobId не найден'),
    );
    final lines = _materials.where((m) => m.jobId == jobId);
    if (lines.isEmpty) return job.costCents;
    var total = 0;
    for (final line in lines) {
      total += (line.costAtOrderCents * line.quantity).round();
    }
    return total;
  });

  /// Маржа заказа: Σ(цена − скидка − снимок себестоимости) по строкам.
  ///
  /// Считается по строкам, а не как `price_cents - cost_cents`: у заказа без
  /// строк себестоимость введена вручную, и такая маржа была бы вымыслом.
  int jobMarginCents(String jobId) {
    final lines = jobLines(jobId);
    if (lines.isEmpty) {
      final job = _jobs.firstWhere((j) => j.id == jobId,
          orElse: () => throw ArgumentError('Заказ $jobId не найден'));
      return job.priceCents - job.costCents;
    }
    var margin = 0;
    for (final line in lines) {
      margin += line.marginCents;
    }
    return margin;
  }

  /// Порог низкой маржи (§Э1.3): 10% от цены заказа.
  static const double kLowMarginRatio = 0.10;

  /// Доля маржи в цене заказа (`null`, если считать нечего).
  ///
  /// Отрицательная маржа — тоже низкая: `0` означает «работаем в ноль», и
  /// это ровно тот случай, который мастер обязан заметить до отдачи заказа.
  double? jobMarginRatio(String jobId) {
    final job = jobById(jobId);
    if (job == null) return null;
    var price = job.priceCents;
    if (price <= 0) return null;
    if (jobLines(jobId).isNotEmpty) {
      var net = 0;
      for (final line in jobLines(jobId)) {
        net += line.totalCents - line.discountCents;
      }
      price = net;
      if (price <= 0) return null;
    }
    return jobMarginCents(jobId) / price;
  }

  /// Низкая маржа заказа — сигнал для «Сегодня» и карточки заказа (§Э1.3).
  ///
  /// Порог срабатывает только на непустом заказе: заказ без строк и цены не
  /// «убыточный», а незаполненный, и пилить его предупреждением нельзя.
  bool isLowMarginJob(String jobId) {
    final ratio = jobMarginRatio(jobId);
    return ratio != null && ratio < kLowMarginRatio;
  }

  /// Низкомаржинальные заказы, требующие пересмотра цен.
  ///
  /// Только `done`: раньше сигнал молча висел бы на заказе, который ещё в
  /// работе и цены в котором правятся штатно.
  List<Job> lowMarginDoneJobs() => _jobs
      .where(
        (j) =>
            !j.archived &&
            (j.status == JobStatus.done || j.status == JobStatus.closed) &&
            isLowMarginJob(j.id),
      )
      .toList();

  // ────────────────────────────────────────────────────────── Obligations
  // ──────────────────────────────────────────────────────────

  /// Синхронизирует обязательства заказа: Σ obligations(job) = priceCents.
  ///
  /// Если у заказа есть строки, сумма = Σ(totalCents). Если строк нет —
  /// `jobs.price_cents`. Создает одно обязательство `client_payment`.
  /// Если уже есть активные обязательства — не трогает.
  Future<void> syncJobObligations(String jobId) async {
    ensurePeriodOpen();
    final job = _jobs.firstWhere((j) => j.id == jobId,
        orElse: () => throw ArgumentError('Job $jobId not found'));
    final lines = jobLines(jobId);
    final totalCents = lines.isEmpty ? job.priceCents
        : lines.fold(0, (s, l) => s + l.totalCents);

    final existing = await _obligationRepo.forJob(jobId);
    final active = existing.where((o) => !o.isClosed).toList();
    if (active.isNotEmpty) {
      // Цена правится до первой оплаты: одно неоплаченное обязательство
      // подтягивается к новой сумме, частичные оплаты не трогаем.
      final untouched = active
          .where((o) => o.paidCents == 0 && o.kind == 'client_payment')
          .toList();
      if (active.length == 1 && untouched.length == 1) {
        final o = untouched.single;
        if (totalCents > 0 && o.amountCents != totalCents) {
          final updated = o.copyWith(
            amountCents: totalCents,
            dueAt: job.dueDate ?? o.dueAt,
            updatedAt: DateTime.now(),
          );
          await _obligationRepo.save(updated);
          final idx = _obligations.indexWhere((x) => x.id == o.id);
          if (idx != -1) {
            _obligations[idx] = updated;
            notifyListeners();
          }
        }
      }
      return;
    }

    if (totalCents <= 0) return;

    // Уже внесённые оплаты (kind=payment из старых версий) переносятся в
    // обязательство, иначе долг клиента вдруг вырос бы до полной цены.
    final paidBefore = paidForJob(jobId).clamp(0, totalCents);
    if (paidBefore >= totalCents) return; // заказ уже полностью оплачен

    final now = DateTime.now();
    final obl = Obligation(
      id: newId(),
      direction: 'receivable',
      kind: 'client_payment',
      counterpartyType: 'client',
      counterpartyId: job.clientId,
      jobId: jobId,
      title: 'Оплата заказа: ${job.title}',
      amountCents: totalCents,
      paidCents: paidBefore,
      dueAt: job.dueDate ?? now,
      status: paidBefore > 0 ? 'partial' : 'planned',
      createdAt: now,
      updatedAt: now,
    );
    await _obligationRepo.save(obl);
    _obligations = [obl, ..._obligations];
    notifyListeners();
  }

  /// Оплачивает обязательство частично или полностью.
  ///
  /// Создаёт `money_transactions` (`kind=sale`, direction='in') и
  /// обновляет `paid_cents` + `status` обязательства.
  Future<Obligation> payObligation(
    String obligationId, {
    required int amountCents,
    String? accountId,
    String? paymentMethod,
  }) async {
    ensurePeriodOpen();
    if (amountCents <= 0) throw ArgumentError('Сумма должна быть > 0');

    final idx = _obligations.indexWhere((o) => o.id == obligationId);
    if (idx == -1) throw ArgumentError('Obligation $obligationId not found');
    final existing = _obligations[idx];
    if (existing.isClosed) throw ArgumentError('Obligation is already closed');

    final applied = amountCents > existing.remainingCents
        ? existing.remainingCents
        : amountCents;
    final paidTotal = existing.paidCents + applied;
    final updated = existing.copyWith(
      paidCents: paidTotal,
      status: paidTotal >= existing.amountCents ? 'paid' : 'partial',
      paymentMethod: paymentMethod ?? existing.paymentMethod,
      updatedAt: DateTime.now(),
    );

    await _obligationRepo.save(updated);
    _obligations[idx] = updated;

    final acc =
        accountId ?? _accounts.firstWhere((a) => !a.archived).id;
    await addTransaction(
      accountId: acc,
      kind: existing.direction == 'receivable' ? 'sale' : 'expense',
      direction: existing.direction == 'receivable' ? 'in' : 'out',
      amountCents: applied,
      note: existing.title,
      clientId: existing.counterpartyType == 'client'
          ? existing.counterpartyId
          : null,
      jobId: existing.jobId,
      obligationId: obligationId,
      paymentMethod: paymentMethod ?? existing.paymentMethod,
    );

    notifyListeners();
    return updated;
  }

  /// Создает платёжное обязательство (кредиторка).
  Future<Obligation> createPayable({
    required String kind,
    required String title,
    required int amountCents,
    required DateTime dueAt,
    String? counterpartyType,
    String? counterpartyId,
    String? accountId,
    String? note,
  }) async {
    ensurePeriodOpen();
    if (amountCents <= 0) throw ArgumentError('Сумма должна быть > 0');

    final now = DateTime.now();
    final obl = Obligation(
      id: newId(),
      direction: 'payable',
      kind: kind,
      counterpartyType: counterpartyType,
      counterpartyId: counterpartyId,
      title: title,
      amountCents: amountCents,
      paidCents: 0,
      dueAt: dueAt,
      status: 'planned',
      accountId: accountId,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await _obligationRepo.save(obl);
    _obligations = [obl, ..._obligations];
    notifyListeners();
    return obl;
  }

  /// Активные обязательства к получению (дебиторка).
  List<Obligation> receivables() =>
      _obligations.where((o) => o.direction == 'receivable' && !o.isClosed)
          .toList();

  /// Активные обязательства к оплате (кредиторка).
  List<Obligation> payables() =>
      _obligations.where((o) => o.direction == 'payable' && !o.isClosed)
          .toList();

  /// Сумма дебиторки по заказу.
  int receivableForJob(String jobId) {
    return _obligations
        .where((o) => o.jobId == jobId && o.direction == 'receivable' && !o.isClosed)
        .fold(0, (s, o) => s + o.remainingCents);
  }

  /// Обязательства заказа (все, включая закрытые).
  List<Obligation> obligationsForJob(String jobId) =>
      _obligations.where((o) => o.jobId == jobId).toList();

  /// Активное обязательство оплаты заказа, если оно есть.
  Obligation? openJobPaymentObligation(String jobId) {
    for (final o in _obligations) {
      if (o.jobId == jobId &&
          o.direction == 'receivable' &&
          o.kind == 'client_payment' &&
          !o.isClosed) {
        return o;
      }
    }
    return null;
  }

  /// Сумма кредиторки по поставщику.
  int payableForSupplier(String supplierId) {
    return _obligations
        .where((o) => o.counterpartyId == supplierId &&
            o.counterpartyType == 'supplier' && !o.isClosed)
        .fold(0, (s, o) => s + o.remainingCents);
  }

  /// Платёжный календарь на N недель вперёд.
  ///
  /// Возвращает список дней: остаток на начало, поступления, платежи,
  /// остаток на конец, флаг разрыва.
  ///
  /// Старт — фактический баланс счетов; обязательства и регулярные платежи
  /// добавляются по дням их срока. Просроченные обязательства попадают в
  /// первый день: они «должны были случиться» уже сегодня.
  List<CashPlanDay> cashPlan({int weeks = 6}) {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final days = weeks * 7;

    // Σ ожидаемых сумм по дням: 0 — сегодня (включая просрочку), 1..days-1.
    final incoming = List<int>.filled(days, 0);
    final outgoing = List<int>.filled(days, 0);
    int slotFor(DateTime dueAt) {
      final d = DateTime(dueAt.year, dueAt.month, dueAt.day);
      final idx = d.difference(first).inDays;
      if (idx < 0) return 0; // просрочено — считаем сегодняшним днём
      return idx < days ? idx : -1; // за горизонтом — не учитываем
    }

    for (final obl in receivables()) {
      final idx = slotFor(obl.dueAt);
      if (idx != -1) incoming[idx] += obl.remainingCents;
    }
    for (final obl in payables()) {
      final idx = slotFor(obl.dueAt);
      if (idx != -1) outgoing[idx] += obl.remainingCents;
    }

    for (final payment in _recurringPayments.where((p) => p.active)) {
      final step = payment.intervalDays < 1 ? 1 : payment.intervalDays;
      var cursor = payment.nextDueAt;
      // Сдвигаем курсор к горизонту, а не перебираем все прошлые даты.
      if (cursor.isBefore(first)) {
        final missed = first.difference(cursor).inDays ~/ step;
        cursor = cursor.add(Duration(days: missed * step));
      }
      while (!cursor.isAfter(first.add(Duration(days: days - 1)))) {
        final idx = slotFor(cursor);
        if (idx != -1) {
          if (payment.direction == 'in') {
            incoming[idx] += payment.amountCents;
          } else {
            outgoing[idx] += payment.amountCents;
          }
        }
        final next = cursor.add(Duration(days: step));
        if (next.isAtSameMomentAs(cursor)) break;
        cursor = next;
      }
    }

    final result = <CashPlanDay>[];
    var cursor = totalBalanceCents();
    for (var i = 0; i < days; i++) {
      final start = cursor;
      cursor += incoming[i] - outgoing[i];
      result.add(
        CashPlanDay(
          date: first.add(Duration(days: i)),
          balanceStart: start,
          incoming: incoming[i],
          outgoing: outgoing[i],
          balanceEnd: cursor,
        ),
      );
    }
    return result;
  }

  /// Создаёт напоминание об оплате обязательства за N дней до срока.
  Future<ClientReminder> createPaymentReminder({
    required String obligationId,
    int daysBefore = 2,
  }) async {
    final obl = _obligations.firstWhere(
      (o) => o.id == obligationId,
      orElse: () => throw ArgumentError('Obligation $obligationId not found'),
    );
    if (obl.isClosed) throw ArgumentError('Obligation is already closed');

    final reminderDue = obl.dueAt.subtract(Duration(days: daysBefore));
    return createReminder(
      clientId: obl.counterpartyId ?? '',
      jobId: obl.jobId,
      type: 'payment_due',
      title: 'Оплата заказа: ${obl.title}',
      body: 'Сумма: ${money(obl.remainingCents)} · Срок: ${formatFullDate(obl.dueAt)}',
      dueAt: reminderDue,
    );
  }

  // ──────────────────────────────────────────────────────────

  /// Все обязательства (включая закрытые).
  List<Obligation> get obligations => List.unmodifiable(_obligations);

  /// Обязательство по ID.
  Obligation? obligationById(String id) {
    for (final o in _obligations) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Отменяет обязательство.
  Future<void> cancelObligation(String id) async {
    ensurePeriodOpen();
    final idx = _obligations.indexWhere((o) => o.id == id);
    if (idx == -1) return;
    final existing = _obligations[idx];
    if (existing.isClosed) return;
    final updated = existing.copyWith(status: 'cancelled', updatedAt: DateTime.now());
    await _obligationRepo.save(updated);
    _obligations[idx] = updated;
    notifyListeners();
  }

  /// Удаляет обязательство (перманентно).
  Future<void> deleteObligation(String id) async {
    ensurePeriodOpen();
    await _obligationRepo.delete(id);
    _obligations = _obligations.where((o) => o.id != id).toList();
    notifyListeners();
  }

  int clientDebtCents(String clientId) =>
      _intCache.putIfAbsent('debt:$clientId', () {
        final obligations = _obligations.where((o) =>
            o.direction == 'receivable' &&
            o.counterpartyType == 'client' &&
            o.counterpartyId == clientId &&
            !o.isClosed);
        if (obligations.isNotEmpty) {
          return obligations.fold(0, (s, o) => s + o.remainingCents);
        }
        // Fallback для заказов без obligations: Σ(price) − Σ(paid txns)
        final price = _jobs
            .where((j) => j.clientId == clientId && !j.archived)
            .fold(0, (s, j) => s + j.priceCents);
        final paid = _moneyTransactions
            .where((t) => !t.voided && t.clientId == clientId)
            .fold(0, (sum, t) {
              if (t.jobId != null) return sum + t.orderPaymentCents;
              return t.direction == 'in' ? sum + t.amountCents : sum;
            });
        final remaining = price - paid;
        return remaining > 0 ? remaining : 0;
      });

  // Inventory
  List<InventoryItem> lowStockItems() =>
      _inventoryItems.where((i) => i.lowStock).toList();

  Future<InventoryItem> createInventoryItem({
    required String name,
    String kind = 'good',
    String unit = 'шт',
    int sellPriceCents = 0,
    int costCents = 0,
    String category = '',
    bool trackStock = true,
    double stockQty = 0,
    double minQty = 0,
  }) async {
    final now = DateTime.now();
    final item = InventoryItem(
      id: newId(),
      name: name.trim(),
      kind: kind,
      unit: unit.trim().isEmpty ? 'шт' : unit.trim(),
      sellPriceCents: sellPriceCents,
      costCents: costCents,
      category: category.trim(),
      trackStock: trackStock,
      stockQty: stockQty,
      minQty: minQty,
      createdAt: now,
      updatedAt: now,
    );
    await _inventoryRepo.save(item);
    _inventoryItems = [..._inventoryItems, item];
    notifyListeners();
    return item;
  }

  Future<void> updateInventoryItem(InventoryItem item) async {
    final updated = item.copyWith(updatedAt: DateTime.now());
    await _inventoryRepo.save(updated);
    final idx = _inventoryItems.indexWhere((i) => i.id == updated.id);
    if (idx == -1) {
      _inventoryItems = [..._inventoryItems, updated];
    } else {
      _inventoryItems[idx] = updated;
    }
    notifyListeners();
  }

  Future<void> deleteInventoryItem(String id) async {
    await _inventoryRepo.delete(id);
    _inventoryItems = _inventoryItems.where((i) => i.id != id).toList();
    _stockMovements = _stockMovements.where((m) => m.itemId != id).toList();
    _compositionLines = _compositionLines.where((l) => l.itemId != id).toList();
    notifyListeners();
  }

  /// All composition (BOM) lines of an item: stock components and/or
  /// manual labor. Empty list if the item has no composition.
  List<InventoryCompositionLine> itemComposition(String itemId) =>
      _compositionLines.where((l) => l.itemId == itemId).toList();

  /// Total cost of the item's composition: sum(qty * price_cents).
  int compositionCostCents(String itemId) =>
      itemComposition(itemId).fold(0, (sum, l) => sum + l.totalCents);

  /// Replace the whole composition of [itemId] with [lines] and update the
  /// item's cost_cents to the composition total (via updateInventoryItem).
  /// Returns the new total in cents.
  Future<int> saveItemComposition(
    String itemId,
    List<InventoryCompositionLine> lines,
  ) async {
    final stored = lines.map((l) {
      if (l.id.isEmpty) {
        return l.copyWith(id: newId(), itemId: itemId);
      }
      return l.copyWith(itemId: itemId);
    }).toList();
    await _compositionRepo.replaceForItem(itemId, stored);
    _compositionLines = [
      ..._compositionLines.where((l) => l.itemId != itemId),
      ...stored,
    ];
    final total = stored.fold(0, (sum, l) => sum + l.totalCents);
    final idx = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (idx != -1) {
      await updateInventoryItem(
        _inventoryItems[idx].copyWith(costCents: total),
      );
    } else {
      notifyListeners();
    }
    return total;
  }

  Future<void> receiveStock({
    required String itemId,
    required double qty,
    int? unitPriceCents,
    String? note,
  }) async {
    final idx = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (idx == -1 || qty <= 0) return;
    final item = _inventoryItems[idx];
    // Цена поступления обновляет себестоимость: при нескольких поставках
    // берём взвешенную среднюю, чтобы маржа считалась по реальным деньгам.
    var costCents = item.costCents;
    final price = unitPriceCents ?? 0;
    if (price > 0) {
      final prevQty = item.stockQty > 0 ? item.stockQty : 0.0;
      final totalQty = prevQty + qty;
      costCents = totalQty <= 0
          ? price
          : ((item.costCents * prevQty + price * qty) / totalQty).round();
    }
    await adjustStock(
      itemId: itemId,
      delta: qty,
      type: 'in',
      note: note,
      refType: 'manual',
      unitCostCents: price > 0 ? price : item.costCents,
      costCentsAfter: costCents,
    );
  }

  Future<void> writeOffStock({
    required String itemId,
    required double qty,
    String? note,
    String? reason,
  }) async {
    if (qty <= 0) return;
    await adjustStock(
      itemId: itemId,
      delta: -qty,
      type: 'writeoff',
      note: note,
      reason: reason ?? 'other',
      refType: 'manual',
    );
  }

  /// Единственная точка изменения остатка позиции.
  ///
  /// До Э0 остаток правили в четырёх местах (`receiveStock`,
  /// `writeOffStock`, `createPurchase`, импорт), и каждое обязано было не
  /// забыть движение склада — забывало. Теперь остаток, движение и
  /// себестоимость пишутся здесь, а вызывающие передают только причину.
  ///
  /// [delta] положительна для прихода, отрицательна для расхода.
  /// [type] — `in` / `out` / `writeoff` / `adjust`.
  ///
  /// Под включённым `module_locations` (Э5) здесь же ведутся партии и
  /// остатки по точкам: приход заводит партию, расход списывает их в FEFO,
  /// после чего уровень позиции на локации пересчитывается от суммы партий.
  /// Пока флаг выключен, ни одна из новых таблиц не трогается — склад
  /// остаётся ровно таким, каким был до Э5 (§12.2).
  Future<void> adjustStock({
    required String itemId,
    required double delta,
    required String type,
    String? note,
    String? reason,
    String? refType,
    String? refId,
    String? locationId,
    int? unitCostCents,
    int? costCentsAfter,
    DateTime? expiresAt,
    String? purchaseId,
  }) async {
    if (delta == 0) return;
    final idx = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    final item = _inventoryItems[idx];
    final now = DateTime.now();
    // `copyWith` не принимает `null` как «оставить как было» для int:
    // передаём себестоимость только когда её действительно пересчитали.
    final updated = costCentsAfter == null
        ? item.copyWith(stockQty: item.stockQty + delta, updatedAt: now)
        : item.copyWith(
            stockQty: item.stockQty + delta,
            costCents: costCentsAfter,
            updatedAt: now,
          );
    await _inventoryRepo.save(updated);
    _inventoryItems[idx] = updated;

    final movement = StockMovement(
      id: newId(),
      itemId: itemId,
      type: type,
      qty: delta.abs(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      reason: reason,
      refType: refType,
      refId: refId,
      locationId: locationId,
      unitCostCents: unitCostCents ?? item.costCents,
      createdAt: now,
    );
    await _stockMovementRepo.save(movement);
    _stockMovements = [movement, ..._stockMovements];

    if (settings.locationsEnabled) {
      final locId = locationId ?? await _defaultLocationId();
      if (locId != null) {
        final cost = unitCostCents ?? item.costCents;
        if (delta > 0) {
          await _receiveBatch(
            itemId: itemId,
            locationId: locId,
            qty: delta,
            unitCostCents: cost,
            expiresAt: expiresAt,
            purchaseId: purchaseId,
            at: now,
          );
        } else {
          await _consumeBatches(
            itemId: itemId,
            locationId: locId,
            qty: -delta,
            at: now,
          );
        }
        await _reconcileLevel(itemId, locId, at: now);
      }
    }

    notifyListeners();
  }

  List<StockMovement> movementsForItem(String itemId) =>
      stockMovementsByItem(itemId);

  // ── Склад по точкам (Э5, §5.6) ────────────────────────────────────────

  /// Идемпотентный бэкфилл при первом включении `module_locations` (§12.2).
  ///
  /// Создаёт «Основной склад» и переносит на него текущие остатки: по каждой
  /// позиции с `stock_qty != 0` заводится бессрочная партия, уровни
  /// пересчитываются от партий. Повторный проход ничего не дублирует, поэтому
  /// вызов безопасен и из включения флага, и из `load()`.
  Future<StockLocation?> ensureDefaultLocation() async {
    final existing = await _locationRepo.defaultLocation();
    if (existing != null) {
      _locations = await _locationRepo.getAll();
      return existing;
    }

    final now = DateTime.now();
    final main = StockLocation(
      id: newId(),
      name: 'Основной склад',
      kind: 'warehouse',
      isDefault: true,
      createdAt: now,
      updatedAt: now,
    );
    await _locationRepo.save(main);

    // До Э5 остаток жил одним числом в `inventory_items.stock_qty`. Без
    // переноса в партию инвариант «остаток точки = Σ её партий» не выполнился
    // бы ни для одной позиции, и FEFO не нашёл бы что списывать.
    for (final item in _inventoryItems.where((i) => i.stockQty != 0)) {
      await _batchRepo.save(
        StockBatch(
          id: newId(),
          itemId: item.id,
          locationId: main.id,
          qty: item.stockQty,
          unitCostCents: item.costCents,
          note: 'Перенос остатка при включении точек',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    _locations = await _locationRepo.getAll();
    _batches = await _batchRepo.getAll();
    await _rebuildLevels();
    notifyListeners();
    return main;
  }

  /// Включает или выключает блок «Несколько точек».
  ///
  /// При включении сразу делает бэкфилл §12.2, иначе первый же приход ушёл бы
  /// в никуда. При выключении данные остаются в схеме (П8): флаг убирает
  /// интерфейс, а не учёт.
  Future<void> setLocationsEnabled(bool value) async {
    await settings.setLocationsEnabled(value);
    if (value) await ensureDefaultLocation();
    notifyListeners();
  }

  bool get locationsEnabled => settings.locationsEnabled;

  /// Id «Основного склада», создав его при необходимости.
  ///
  /// Нужен `adjustStock`: движение обязано попасть на какую-то точку, даже
  /// если флаг включили, а бэкфилл ещё не отработал.
  Future<String?> _defaultLocationId() async {
    final existing = _locations
        .where((l) => l.isDefault)
        .cast<StockLocation?>()
        .firstOrNull;
    if (existing != null) return existing.id;
    return (await ensureDefaultLocation())?.id;
  }

  StockLocation? locationById(String? id) {
    if (id == null) return null;
    for (final l in _locations) {
      if (l.id == id) return l;
    }
    return null;
  }

  String locationName(String? id) =>
      id == null ? 'Основной склад' : (locationById(id)?.name ?? '—');

  /// Название позиции по id; `null` → `—` для удалённой из каталога строки.
  String itemName(String? itemId) {
    if (itemId == null) return '—';
    for (final i in _inventoryItems) {
      if (i.id == itemId) return i.name;
    }
    return '—';
  }

  Future<StockLocation> createLocation({
    required String name,
    String kind = 'warehouse',
    String? note,
  }) async {
    ensurePeriodOpen();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Укажите название точки');
    final now = DateTime.now();
    final location = StockLocation(
      id: newId(),
      name: trimmed,
      kind: kind,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _locationRepo.save(location);
    _locations = await _locationRepo.getAll();
    await auditAction(
      action: 'location.create',
      entity: 'location',
      entityId: location.id,
      after: location.toMap(),
    );
    notifyListeners();
    return location;
  }

  Future<void> updateLocation(
    String id, {
    String? name,
    String? kind,
    String? note,
  }) async {
    ensurePeriodOpen();
    final existing = locationById(id);
    if (existing == null) return;
    final before = existing.toMap();
    final updated = existing.copyWith(
      name: name?.trim().isEmpty == true ? null : name,
      kind: kind,
      note: note?.trim().isEmpty == true ? null : note,
      updatedAt: DateTime.now(),
    );
    await _locationRepo.save(updated);
    final idx = _locations.indexWhere((l) => l.id == id);
    if (idx != -1) _locations[idx] = updated;
    await auditAction(
      action: 'location.update',
      entity: 'location',
      entityId: id,
      before: before,
      after: updated.toMap(),
    );
    notifyListeners();
  }

  /// Удаляет точку, только если на ней ничего не лежит.
  ///
  /// Остаток или партии означают, что удалять нечего некуда: вместо
  /// «переноса в никуда» показываем причину владельцу.
  Future<void> deleteLocation(String id) async {
    ensurePeriodOpen();
    final existing = locationById(id);
    if (existing == null) return;
    if (existing.isDefault) {
      throw ArgumentError('Основной склад удалить нельзя');
    }
    final hasStock = _batches.any((b) => b.locationId == id && b.qty > 0);
    if (hasStock) {
      throw ArgumentError('На точке есть остатки — сначала вывезите их');
    }
    await _locationRepo.delete(id);
    _locations = await _locationRepo.getAll();
    _stockLevels = _stockLevels.where((l) => l.locationId != id).toList();
    await auditAction(
      action: 'location.delete',
      entity: 'location',
      entityId: id,
      before: existing.toMap(),
    );
    notifyListeners();
  }

  /// Годные к списанию партии позиции, FEFO (ближайший срок — первым).
  ///
  /// Сортировка живит здесь, а не в вызывающем коде: иначе любой новый экран
  /// мог бы незаметно списать «не то» партию.
  Future<List<StockBatch>> stockBatches(
    String itemId, {
    String? locationId,
  }) async {
    final all = locationId == null
        ? await _batchRepo.forItem(itemId)
        : await _batchRepo.forItemAndLocation(itemId, locationId);
    return all;
  }

  /// Остаток позиции на точке (из `stock_levels`).
  double stockOnLocation(String itemId, String locationId) {
    final level = _stockLevels
        .where((l) => l.itemId == itemId && l.locationId == locationId)
        .cast<StockLevel?>()
        .firstOrNull;
    return level?.qty ?? 0;
  }

  /// Порог минимума позиции на точке; если строки нет — общий `min_qty`.
  ///
  /// `min_qty = 0` в `stock_levels` означает «на точке порог не задавали», а
  /// не «порог равен нулю»: иначе любой приход создал бы строку остатка с
  /// нулём и заглушил общий минимум позиции.
  double minQtyOnLocation(InventoryItem item, String locationId) {
    final level = _stockLevels
        .where((l) => l.itemId == item.id && l.locationId == locationId)
        .cast<StockLevel?>()
        .firstOrNull;
    final perLocation = level?.minQty ?? 0;
    return perLocation > 0 ? perLocation : item.minQty;
  }

  Future<void> setMinQtyOnLocation({
    required String itemId,
    required String locationId,
    required double minQty,
  }) async {
    ensurePeriodOpen();
    final now = DateTime.now();
    final existing = _stockLevels
        .where((l) => l.itemId == itemId && l.locationId == locationId)
        .cast<StockLevel?>()
        .firstOrNull;
    if (existing == null) {
      final level = StockLevel(
        id: newId(),
        itemId: itemId,
        locationId: locationId,
        qty: 0,
        minQty: minQty,
        createdAt: now,
        updatedAt: now,
      );
      await _locationRepo.saveLevel(level);
      _stockLevels = [..._stockLevels, level];
    } else {
      final updated = existing.copyWith(minQty: minQty, updatedAt: now);
      await _locationRepo.saveLevel(updated);
      final idx = _stockLevels.indexWhere((l) => l.id == existing.id);
      if (idx != -1) _stockLevels[idx] = updated;
    }
    notifyListeners();
  }

  /// Позиции на точке ниже порога — сырьё для «Сегодня» (Э9) и списка точки.
  List<({InventoryItem item, double qty, double minQty})> belowMinOnLocation(
    String locationId,
  ) {
    final result =
        <({InventoryItem item, double qty, double minQty})>[];
    for (final item in _inventoryItems.where(
      (i) => !i.archived && i.trackStock,
    )) {
      final qty = stockOnLocation(item.id, locationId);
      final min = minQtyOnLocation(item, locationId);
      if (min > 0 && qty < min) {
        result.add((item: item, qty: qty, minQty: min));
      }
    }
    return result;
  }

  /// Партии, истекающие в пределах [days], по всем точкам.
  List<StockBatch> expiringBatches({int days = 3, DateTime? at}) {
    final now = at ?? DateTime.now();
    final list = _batches
        .where((b) => b.qty > 0 && b.isExpiringSoonAt(now, days: days))
        .toList();
    return _sortedFefo(list);
  }

  /// Ближайший по сроку годный остаток позиции на всех точках.
  StockBatch? nearestBatch(String itemId, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final list = _batches
        .where((b) => b.itemId == itemId && b.qty > 0 && !b.isExpiredAt(now))
        .toList();
    final sorted = _sortedFefo(list);
    return sorted.isEmpty ? null : sorted.first;
  }

  /// Порядок FEFO: срок по возрастанию, партии без срока — в конец.
  ///
  /// SQLite сортирует `NULL` в `expires_at` первым при `ASC`, поэтому тот же
  /// порядок задан и в репозитории `(expires_at IS NULL)`. Держать его в двух
  /// местах нужно затем, чтобы списание из памяти и список из базы не
  /// расходились: несъедобное не должно списываться раньше творога.
  static List<StockBatch> _sortedFefo(List<StockBatch> source) {
    final sorted = List<StockBatch>.from(source)
      ..sort((a, b) {
        final ea = a.expiresAt;
        final eb = b.expiresAt;
        if (ea == null && eb != null) return 1;
        if (ea != null && eb == null) return -1;
        if (ea != null && eb != null) {
          final cmp = ea.compareTo(eb);
          if (cmp != 0) return cmp;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    return sorted;
  }

  /// Приход партии.
  ///
  /// Совпадение срока и себестоимости объединяет строки: партия на каждую
  /// пачку масла сделала бы список нечитаемым, а порядок FEFO от этого не
  /// меняется — его задаёт срок.
  Future<void> _receiveBatch({
    required String itemId,
    required String locationId,
    required double qty,
    required int unitCostCents,
    required DateTime at,
    DateTime? expiresAt,
    String? purchaseId,
  }) async {
    if (qty <= 0) return;
    final same = _batches
        .where(
          (b) =>
              b.itemId == itemId &&
              b.locationId == locationId &&
              b.qty > 0 &&
              b.unitCostCents == unitCostCents &&
              b.expiresAt == expiresAt,
        )
        .cast<StockBatch?>()
        .firstOrNull;
    if (same != null) {
      final updated = same.copyWith(qty: same.qty + qty, updatedAt: at);
      await _batchRepo.save(updated);
      final idx = _batches.indexWhere((b) => b.id == same.id);
      if (idx != -1) _batches[idx] = updated;
      return;
    }
    final batch = StockBatch(
      id: newId(),
      itemId: itemId,
      locationId: locationId,
      qty: qty,
      expiresAt: expiresAt,
      unitCostCents: unitCostCents,
      purchaseId: purchaseId,
      createdAt: at,
      updatedAt: at,
    );
    await _batchRepo.save(batch);
    _batches = [batch, ..._batches];
  }

  /// FEFO-списание: первым уходит то, у чего срок ближе.
  ///
  /// Движение склада пишет вызвавший `adjustStock`, здесь меняются только
  /// партии — иначе на один расход пришлось бы два движения. Истёкшие партии
  /// пропускаются: просрочку списывают отдельно (`writeOffStock` с
  /// `reason: 'expiry'`), иначе порча незаметно вошла бы в себестоимость.
  ///
  /// Нехватка — не ошибка: списываем сколько есть и возвращаем факт. `stock_qty`
  /// мог превысить сумму партий (правка остатка «на глаз»), а инвариант
  /// «уровень = Σ партий» важнее точности расхода.
  Future<double> _consumeBatches({
    required String itemId,
    required String locationId,
    required double qty,
    required DateTime at,
  }) async {
    if (qty <= 0) return 0;
    final queue = _sortedFefo(
      _batches
          .where(
            (b) =>
                b.itemId == itemId &&
                b.locationId == locationId &&
                b.qty > 0 &&
                !b.isExpiredAt(at),
          )
          .toList(),
    );
    double remaining = qty;
    for (final batch in queue) {
      if (remaining <= _qtyEps) break;
      final take = batch.qty <= remaining ? batch.qty : remaining;
      remaining -= take;
      final left = batch.qty - take;
      if (left <= _qtyEps) {
        await _batchRepo.softDelete(batch.id);
        _batches = _batches.where((b) => b.id != batch.id).toList();
      } else {
        final updated = batch.copyWith(qty: left, updatedAt: at);
        await _batchRepo.save(updated);
        final idx = _batches.indexWhere((b) => b.id == batch.id);
        if (idx != -1) _batches[idx] = updated;
      }
    }
    return qty - remaining;
  }

  /// Средняя себестоимость FEFO-выборки: сколько стоит списать [qty] с точки.
  ///
  /// Нужна перемещению, чтобы партия на новой точке унаследовала реальную
  /// стоимость, а не текущую среднюю по позиции.
  int _fefoCostCents({
    required String itemId,
    required String locationId,
    required double qty,
    required DateTime at,
  }) {
    final queue = _sortedFefo(
      _batches
          .where(
            (b) =>
                b.itemId == itemId &&
                b.locationId == locationId &&
                b.qty > 0 &&
                !b.isExpiredAt(at),
          )
          .toList(),
    );
    double remaining = qty;
    double cost = 0;
    double taken = 0;
    for (final batch in queue) {
      if (remaining <= _qtyEps) break;
      final take = batch.qty <= remaining ? batch.qty : remaining;
      remaining -= take;
      cost += take * batch.unitCostCents;
      taken += take;
    }
    if (taken <= _qtyEps) return 0;
    return (cost / taken).round();
  }

  /// Пересчёт строки остатка по сумме партий.
  ///
  /// `min_qty` не трогается: порог задаёт человек, а не расчёт.
  Future<void> _reconcileLevel(
    String itemId,
    String locationId, {
    required DateTime at,
  }) async {
    final total = _batches
        .where(
          (b) =>
              b.itemId == itemId && b.locationId == locationId && b.qty > 0,
        )
        .fold<double>(0, (sum, b) => sum + b.qty);
    final existing = _stockLevels
        .where((l) => l.itemId == itemId && l.locationId == locationId)
        .cast<StockLevel?>()
        .firstOrNull;
    if (existing == null) {
      // Пустую позицию не заводим: строка остатка нужна либо с количеством,
      // либо с заданным порогом.
      if (total <= _qtyEps) return;
      final level = StockLevel(
        id: newId(),
        itemId: itemId,
        locationId: locationId,
        qty: total,
        createdAt: at,
        updatedAt: at,
      );
      await _locationRepo.saveLevel(level);
      _stockLevels = [..._stockLevels, level];
      return;
    }
    if ((existing.qty - total).abs() <= _qtyEps) return;
    final updated = existing.copyWith(qty: total, updatedAt: at);
    await _locationRepo.saveLevel(updated);
    final idx = _stockLevels.indexWhere((l) => l.id == existing.id);
    if (idx != -1) _stockLevels[idx] = updated;
  }

  /// Полная пересборка уровней из партий.
  ///
  /// Используется бэкфиллом: уровни — производная, их дешевле пересчитать
  /// целиком, чем выводить частными случаями.
  Future<void> _rebuildLevels() async {
    final now = DateTime.now();
    final byPair = <String, double>{};
    for (final b in _batches.where((b) => b.qty > 0)) {
      final key = '${b.itemId}\u0000${b.locationId}';
      byPair[key] = (byPair[key] ?? 0) + b.qty;
    }
    final rebuilt = <StockLevel>[];
    for (final entry in byPair.entries) {
      final parts = entry.key.split('\u0000');
      final itemId = parts[0];
      final locationId = parts[1];
      final previous = _stockLevels
          .where((l) => l.itemId == itemId && l.locationId == locationId)
          .cast<StockLevel?>()
          .firstOrNull;
      final level = StockLevel(
        id: previous?.id ?? newId(),
        itemId: itemId,
        locationId: locationId,
        qty: entry.value,
        minQty: previous?.minQty ??
            _inventoryItems
                .firstWhere(
                  (i) => i.id == itemId,
                  orElse: () => _emptyItem(itemId),
                )
                .minQty,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      await _locationRepo.saveLevel(level);
      rebuilt.add(level);
    }
    // Остатков «из воздуха» не оставляем: строка без партий — ошибка учёта.
    for (final level in _stockLevels) {
      final key = '${level.itemId}\u0000${level.locationId}';
      if (byPair.containsKey(key)) continue;
      if (level.qty <= _qtyEps) continue;
      await _locationRepo.saveLevel(
        level.copyWith(qty: 0, updatedAt: now),
      );
      rebuilt.add(level.copyWith(qty: 0, updatedAt: now));
    }
    _stockLevels = rebuilt;
  }

  InventoryItem _emptyItem(String id) => InventoryItem(
    id: id,
    name: '—',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Допуск сравнения количеств: `qty` — `REAL`, точное равенство на нём
  /// держать нельзя (0.1 + 0.2 != 0.3).
  static const double _qtyEps = 0.0001;

  // ── Перемещения между точками ─────────────────────────────────────────

  /// Создаёт перемещение и сразу проводит его по остаткам.
  ///
  /// «План без движения» (§6.9) здесь не задерживается: перемещение — это
  /// перекладывание ящика, а не намерение на неделю. Статус `completed`
  /// ставится сразу, `planned` остаётся для документов, которые ещё могут
  /// отменить.
  Future<StockTransfer> createStockTransfer({
    required String fromLocationId,
    required String toLocationId,
    required List<Map<String, Object?>> lines,
    String? note,
  }) async {
    ensurePeriodOpen();
    if (fromLocationId == toLocationId) {
      throw ArgumentError('Точка отправления и получения совпадают');
    }
    final valid = <StockTransferLine>[];
    for (final line in lines) {
      final itemId = line['itemId'] as String? ?? '';
      final qty = (line['qty'] as num?)?.toDouble() ?? 0;
      if (itemId.isEmpty || qty <= 0) continue;
      valid.add(
        StockTransferLine(
          id: newId(),
          transferId: '',
          itemId: itemId,
          qty: qty,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (valid.isEmpty) throw ArgumentError('Добавьте хотя бы одну позицию');

    final now = DateTime.now();
    final transfer = StockTransfer(
      id: newId(),
      fromLocationId: fromLocationId,
      toLocationId: toLocationId,
      status: 'planned',
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _transferRepo.save(transfer);
    final withTransfer = valid
        .map((l) => l.copyWith(transferId: transfer.id))
        .toList();
    await _transferRepo.saveLines(withTransfer);
    _transfers = [transfer, ..._transfers];
    _transferLines = [..._transferLines, ...withTransfer];

    // Себестоимость берём до списания: после неё партии источника уже другие.
    for (final line in withTransfer) {
      final cost = _fefoCostCents(
        itemId: line.itemId,
        locationId: fromLocationId,
        qty: line.qty,
        at: now,
      );
      await adjustStock(
        itemId: line.itemId,
        delta: -line.qty,
        type: 'out',
        note: 'Перемещение → ${locationName(toLocationId)}',
        refType: 'transfer',
        refId: transfer.id,
        locationId: fromLocationId,
        unitCostCents: cost,
      );
      await adjustStock(
        itemId: line.itemId,
        delta: line.qty,
        type: 'in',
        note: 'Перемещение ← ${locationName(fromLocationId)}',
        refType: 'transfer',
        refId: transfer.id,
        locationId: toLocationId,
        unitCostCents: cost,
      );
    }

    final done = transfer.copyWith(status: 'completed', updatedAt: DateTime.now());
    await _transferRepo.save(done);
    final idx = _transfers.indexWhere((t) => t.id == transfer.id);
    if (idx != -1) _transfers[idx] = done;
    await auditAction(
      action: 'transfer.complete',
      entity: 'transfer',
      entityId: transfer.id,
      after: done.toMap(),
    );
    notifyListeners();
    return done;
  }

  List<StockTransferLine> transferLines(String transferId) =>
      _transferLines.where((l) => l.transferId == transferId).toList();

  // ── Приёмка закупки ───────────────────────────────────────────────────

  /// Принятые количества по строкам закупки (`itemId` → `receivedQty`).
  Map<String, double> receivedForPurchase(String purchaseId) {
    final result = <String, double>{};
    for (final line in linesForPurchase(purchaseId)) {
      final got = line.receivedQty;
      if (got != null) result[line.itemId] = got;
    }
    return result;
  }

  /// Приёмка с расхождениями (§5.6).
  ///
  /// [received] — сколько приняли по каждой позиции. Приход заводится партией
  /// со сроком (если его указали в [expiry]) и себестоимостью закупки, а долг
  /// поставщику уменьшается на недопоставку: `totalCents` пересчитывается по
  /// фактическому количеству, и `supplierDebtCents` сразу показывает новый долг.
  ///
  /// Повторная приёмка добавляет только разницу с уже принятым, поэтому
  /// «дослали остаток на следующий день» не удваивает склад.
  Future<void> receivePurchase({
    required String purchaseId,
    required Map<String, double> received,
    Map<String, DateTime> expiry = const {},
    String? locationId,
    String? note,
  }) async {
    ensurePeriodOpen();
    final purchase = await _purchaseRepo.byId(purchaseId);
    if (purchase == null) throw ArgumentError('Закупка не найдена');
    final lines = linesForPurchase(purchaseId);
    if (lines.isEmpty) throw ArgumentError('В закупке нет строк');

    final locId = locationId ?? await _defaultLocationId();
    final before = purchase.toMap();
    final now = DateTime.now();

    for (final line in lines) {
      final got = received[line.itemId];
      if (got == null) continue;
      if (got < 0) throw ArgumentError('Принятое количество не может быть меньше нуля');
      final already = line.receivedQty ?? 0;
      final delta = got - already;
      if (delta.abs() <= _qtyEps) continue;
      final updatedLine = line.copyWith(receivedQty: got);
      await _purchaseRepo.saveLine(updatedLine);
      final idx = _purchaseLines.indexWhere((l) => l.id == line.id);
      if (idx != -1) {
        _purchaseLines[idx] = updatedLine;
      } else {
        _purchaseLines = [..._purchaseLines, updatedLine];
      }
      if (delta <= 0 || locId == null) continue;
      // Приход идёт через adjustStock: он заводит и движение, и партию, и
      // уровень — иначе `stock_qty` и сумма партий разошлись бы сразу.
      final trimmedNote = note?.trim();
      await adjustStock(
        itemId: line.itemId,
        delta: delta,
        type: 'in',
        note: (trimmedNote == null || trimmedNote.isEmpty)
            ? 'Приёмка закупки'
            : trimmedNote,
        refType: 'purchase',
        refId: purchaseId,
        locationId: locId,
        unitCostCents: line.unitPriceCents,
        expiresAt: expiry[line.itemId],
        purchaseId: purchaseId,
      );
    }

    // Долг поставщику = сколько фактически приняли. Непринятые строки
    // считаются по заказанному: приёмка одной позиции не «прощает» остальные.
    int total = 0;
    for (final line in linesForPurchase(purchaseId)) {
      final qty = line.receivedQty ?? line.qty;
      total += (qty * line.unitPriceCents).round();
    }
    final updated = purchase.copyWith(
      receivedAt: now,
    ).copyTotal(total);
    await _purchaseRepo.save(updated);
    final pIdx = _purchases.indexWhere((p) => p.id == purchaseId);
    if (pIdx != -1) {
      _purchases[pIdx] = updated;
    } else {
      _purchases = [updated, ..._purchases];
    }

    await auditAction(
      action: 'purchase.receive',
      entity: 'purchase',
      entityId: purchaseId,
      before: before,
      after: updated.toMap(),
    );
    notifyListeners();
  }

  // ── План производства ─────────────────────────────────────────────────

  /// Потребность на день: Σ(BOM × план) − остаток, плюс всё, что ниже минимума.
  ///
  /// Считается по заказам с датой на [day] (плюс просроченные — их всё равно
  /// надо отдавать) и раскрывается через состав каталога. Возвращает только то,
  /// чего не хватает: «план на ноль» экрану не нужен.
  Future<List<ProductionNeed>> productionPlan(DateTime day) async {
    if (!settings.locationsEnabled) return const [];
    final locId = await _defaultLocationId();
    if (locId == null) return const [];

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final dueJobs = _jobs.where((j) {
      if (j.archived) return false;
      if (j.status == JobStatus.closed) return false;
      final due = j.dueDate;
      if (due == null) return false;
      return due.isBefore(dayEnd);
    }).toList();

    final need = <String, double>{};
    for (final job in dueJobs) {
      for (final mat in _materials.where((m) => m.jobId == job.id)) {
        final itemId = mat.itemId;
        if (itemId == null || itemId.isEmpty) continue;
        need[itemId] = (need[itemId] ?? 0) + mat.quantity;
      }
    }

    // Раскрытие состава: готовая позиция требует сырья по своей рецептуре.
    final expanded = <String, double>{};
    for (final entry in need.entries) {
      _expandComposition(entry.key, entry.value, expanded, 0);
    }

    final result = <ProductionNeed>[];
    for (final entry in expanded.entries) {
      final item = _inventoryItems
          .where((i) => i.id == entry.key)
          .cast<InventoryItem?>()
          .firstOrNull;
      if (item == null || item.archived) continue;
      final inStock = stockOnLocation(item.id, locId);
      final short = entry.value - inStock;
      if (short <= _qtyEps) continue;
      result.add(
        ProductionNeed(
          item: item,
          planQty: entry.value,
          inStock: inStock,
          short: short,
          reason: 'plan',
        ),
      );
    }

    // Всё, что ниже минимума, но не нужно сегодняшним заказам, — тоже план:
    // иначе «муки почти нет» всплывёт только тогда, когда станет поздно.
    final planned = result.map((r) => r.item.id).toSet();
    for (final gap in belowMinOnLocation(locId)) {
      if (planned.contains(gap.item.id)) continue;
      result.add(
        ProductionNeed(
          item: gap.item,
          planQty: gap.minQty,
          inStock: gap.qty,
          short: gap.minQty - gap.qty,
          reason: 'min',
        ),
      );
    }

    result.sort((a, b) => b.short.compareTo(a.short));
    return result;
  }

  /// Рекурсивно раскрывает состав позиции в [out], глубина ограничена:
  /// циклы в рецептуре (мука ← полуфабрикат ← мука) иначе не закончатся.
  void _expandComposition(
    String itemId,
    double qty,
    Map<String, double> out,
    int depth,
  ) {
    if (qty <= 0) return;
    if (depth >= 3) {
      out[itemId] = (out[itemId] ?? 0) + qty;
      return;
    }
    final components = _compositionLines
        .where((c) => c.itemId == itemId && !c.isLabor)
        .where((c) => (c.componentId ?? '').isNotEmpty)
        .toList();
    if (components.isEmpty) {
      out[itemId] = (out[itemId] ?? 0) + qty;
      return;
    }
    for (final c in components) {
      _expandComposition(c.componentId!, qty * c.qty, out, depth + 1);
    }
  }

  /// Черновик закупки недостающего сырья (кнопка «Заказать недостающее»).
  Future<Purchase?> createPurchaseFromPlan(
    List<ProductionNeed> plan, {
    String? supplierId,
  }) async {
    final lines = plan
        .where((n) => n.short > 0)
        .map(
          (n) => <String, Object?>{
            'itemId': n.item.id,
            'qty': n.short,
            'unitPriceCents': n.item.costCents,
          },
        )
        .toList();
    if (lines.isEmpty) return null;
    return createPurchase(supplierId: supplierId, lines: lines);
  }

  /// Предупреждение о загрузке: суммарная длительность этапов заказов на
  /// день больше [limitHours]. `lead_hours` для этого и добавлялся в v22.
  ///
  /// Этапы без заданной длительности считаются нулём: иначе владелец получал
  /// ложную «перегрузку» только потому, что не заполнил справочник.
  bool capacityWarning(DateTime day, {double limitHours = 8}) {
    final dayEnd = DateTime(day.year, day.month, day.day).add(
      const Duration(days: 1),
    );
    double hours = 0;
    for (final job in _jobs) {
      if (job.archived) continue;
      if (job.status == JobStatus.closed) continue;
      final due = job.dueDate;
      if (due == null || !due.isBefore(dayEnd)) continue;
      for (final stage in _stages.where(
        (s) => s.jobId == job.id && !s.done,
      )) {
        hours += stage.leadHours ?? 0;
      }
    }
    return hours > limitHours;
  }


  // Calculator state persistence (per job, JSON blob in jobs.calculator_state).
  final Map<String, String> _calculatorState = <String, String>{};
  final Map<String, Timer> _calculatorDebounce = <String, Timer>{};

  /// Last saved calculator state JSON for [jobId], or `null` if none.
  /// Reads in-memory value first (includes unsaved debounced changes), then DB.
  Future<String?> calculatorStateForJob(String jobId) async {
    final mem = _calculatorState[jobId];
    if (mem != null) return mem;
    return _appDatabase.getCalculatorState(jobId);
  }

  /// Debounced save of calculator state JSON for [jobId] (400 ms).
  /// Call [flushCalculatorState] to persist immediately (e.g. on close).
  void saveCalculatorState(String jobId, String json) {
    _calculatorState[jobId] = json;
    _calculatorDebounce[jobId]?.cancel();
    _calculatorDebounce[jobId] = Timer(
      const Duration(milliseconds: 400),
      () async {
        _calculatorDebounce.remove(jobId);
        final pending = _calculatorState.remove(jobId);
        if (pending != null) {
          await _appDatabase.saveCalculatorState(jobId, pending);
        }
      },
    );
  }

  /// Persist any unsaved calculator state for [jobId] immediately.
  Future<void> flushCalculatorState(String jobId) async {
    _calculatorDebounce[jobId]?.cancel();
    _calculatorDebounce.remove(jobId);
    final json = _calculatorState.remove(jobId);
    if (json != null) {
      await _appDatabase.saveCalculatorState(jobId, json);
    }
  }

  List<StockMovement> stockMovementsByItem(String itemId) {
    final list = _stockMovements.where((m) => m.itemId == itemId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<StockMovement> stockMovementsForItem(String itemId) =>
      _stockMovements.where((m) => m.itemId == itemId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // Booking
  BookingResource? defaultResource() =>
      _bookingResources.isEmpty ? null : _bookingResources.first;

  List<Appointment> appointmentsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _appointments
        .where(
          (a) =>
              a.startAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
              a.startAt.isBefore(end),
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<Appointment> createAppointment({
    required String title,
    DateTime? startAt,
    DateTime? endAt,
    String? clientId,
    String? objectId,
    String? resourceId,
    String? note,
  }) async {
    final now = DateTime.now();
    final s = startAt ?? now;
    final e = endAt ?? s.add(const Duration(hours: 1));
    final r = resourceId ?? defaultResource()?.id;
    final appt = Appointment(
      id: newId(),
      clientId: clientId,
      objectId: objectId,
      resourceId: r,
      title: title.trim(),
      startAt: s,
      endAt: e,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _validateAppointment(appt);
    await _appointmentRepo.save(appt);
    _appointments = [..._appointments, appt];
    try {
      await ReminderService.scheduleAppointmentReminder(
        appt.title,
        appt.startAt,
      );
    } catch (_) {}
    notifyListeners();
    return appt;
  }

  Future<void> updateAppointment(Appointment a) async {
    _validateAppointment(a);
    await ReminderService.cancelAppointmentReminder(a.id);
    final updated = a.copyWith(updatedAt: DateTime.now());
    await _appointmentRepo.save(updated);
    final idx = _appointments.indexWhere((x) => x.id == updated.id);
    if (idx == -1) {
      _appointments = [..._appointments, updated];
    } else {
      _appointments[idx] = updated;
    }
    if (updated.status == AppointmentStatus.scheduled ||
        updated.status == AppointmentStatus.confirmed) {
      await ReminderService.scheduleAppointmentReminder(updated.title, updated.startAt);
    }
    notifyListeners();
  }

  void _validateAppointment(Appointment appointment) {
    if (!appointment.endAt.isAfter(appointment.startAt)) {
      throw StateError('Время окончания должно быть позже времени начала.');
    }
    if (appointment.status != AppointmentStatus.scheduled &&
        appointment.status != AppointmentStatus.confirmed) {
      return;
    }
    final conflicts = _appointments.where((other) =>
        other.id != appointment.id &&
        other.resourceId == appointment.resourceId &&
        (other.status == AppointmentStatus.scheduled ||
            other.status == AppointmentStatus.confirmed) &&
        other.startAt.isBefore(appointment.endAt) &&
        appointment.startAt.isBefore(other.endAt));
    if (conflicts.isNotEmpty) {
      throw StateError('Ресурс уже занят в это время. Выберите другое время.');
    }
  }

  Future<void> deleteAppointment(String id) async {
    await ReminderService.cancelAppointmentReminder(id);
    await _appointmentRepo.delete(id);
    _appointments = _appointments.where((a) => a.id != id).toList();
    notifyListeners();
  }

  /// Меняет статус записи (канбан-перетаскивание, быстрая отметка).
  Future<void> setAppointmentStatus(String id, AppointmentStatus status) async {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final updated = _appointments[idx].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    _validateAppointment(updated);
    await ReminderService.cancelAppointmentReminder(id);
    await _appointmentRepo.save(updated);
    _appointments[idx] = updated;
    if (status == AppointmentStatus.scheduled ||
        status == AppointmentStatus.confirmed) {
      try {
        await ReminderService.scheduleAppointmentReminder(
          updated.title,
          updated.startAt,
        );
      } catch (_) {
        // reminders are best-effort
      }
    }
    notifyListeners();
  }

  // Unified events (записи + заказы в одном экране планирования)

  /// Объединённое событие «запись» + «заказ» за диапазон [start, end),
  /// отсортированное по времени. Заказы без срока не попадают в
  /// календарь; архивные заказы исключаются.
  List<UnifiedEvent> getEventsForRange(DateTime start, DateTime end) {
    final events = <UnifiedEvent>[];
    for (final a in _appointments) {
      if (!a.startAt.isBefore(start) && a.startAt.isBefore(end)) {
        events.add(UnifiedEvent.fromAppointment(a));
      }
    }
    for (final j in _jobs) {
      if (j.archived) continue;
      final t = j.dueDate ?? j.startedAt;
      if (t == null) continue;
      if (!t.isBefore(start) && t.isBefore(end)) {
        events.add(UnifiedEvent.fromJob(j));
      }
    }
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  /// Превращает запись в заказ: создаёт Job с тем же клиентом/объектом,
  /// сроком = старт записи и пометкой о происхождении; запись удаляется
  /// (вместе с её напоминанием). У записи без клиента конвертация
  /// невозможна — выбрасывается StateError.
  Future<void> convertAppointmentToJob(String appointmentId) async {
    final a = appointmentById(appointmentId);
    if (a == null) throw StateError('Запись не найдена');
    if (a.clientId == null) {
      throw StateError('У записи нет клиента — нечего привязывать заказ');
    }
    final now = DateTime.now();
    final job = Job(
      id: newId(),
      clientId: a.clientId!,
      objectId: a.objectId,
      title: a.title,
      status: a.status == AppointmentStatus.done
          ? JobStatus.done
          : JobStatus.nuevo,
      dueDate: a.startAt,
      note: a.note == null
          ? 'Из записи: ${a.startAt.toLocal()}'
          : 'Из записи: ${a.startAt.toLocal()} — ${a.note}',
      createdAt: now,
      updatedAt: now,
    );
    await _jobRepo.save(job);
    _jobs = [job, ..._jobs];
    await deleteAppointment(a.id); // снимает напоминание и удаляет запись
    notifyListeners();
  }

  /// Назначает заказу конкретное время: создаёт запись на слоте
  /// дедлайна заказа (или «сейчас + 1 час»), заказ остаётся на месте.
  /// Конфликт слота ресурса отклоняется существующей проверкой
  /// createAppointment (StateError).
  Future<Appointment> convertJobToAppointment(String jobId) async {
    final j = jobById(jobId);
    if (j == null) throw StateError('Заказ не найден');
    final start = j.dueDate ?? DateTime.now().add(const Duration(hours: 1));
    final end = start.add(const Duration(hours: 1));
    final note = [
      if ((j.note ?? '').isNotEmpty) j.note,
      'Из заказа «${j.title}»',
    ].join(' • ');
    return createAppointment(
      title: j.title,
      startAt: start,
      endAt: end,
      clientId: j.clientId,
      objectId: j.objectId,
      note: note,
    );
  }

  // Reminders
  List<ClientReminder> dueReminders() =>
      _reminders.where((r) => r.isDue).toList();
  List<ClientReminder> remindersForClient(String clientId) =>
      _reminders.where((r) => r.clientId == clientId).toList();

  Future<ClientReminder> createReminder({
    required String clientId,
    String? jobId,
    String type = 'manual',
    required String title,
    String? body,
    required DateTime dueAt,
  }) async {
    final r = ClientReminder(
      id: newId(),
      clientId: clientId,
      jobId: jobId,
      type: type,
      title: title.trim(),
      body: body?.trim().isEmpty == true ? null : body?.trim(),
      dueAt: dueAt,
      createdAt: DateTime.now(),
    );
    await _reminderRepo.save(r);
    _reminders = [..._reminders, r];
    notifyListeners();
    return r;
  }

  Future<void> setReminderStatus(String id, ReminderStatus status) async {
    final idx = _reminders.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    final updated = _reminders[idx].copyWith(status: status);
    await _reminderRepo.save(updated);
    _reminders[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteReminder(String id) async {
    await _reminderRepo.delete(id);
    _reminders = _reminders.where((r) => r.id != id).toList();
    notifyListeners();
  }

  // Auto-warranty reminder on job done could be added in setJobStatus, but keep manual for now.

  // Employees
  Employee? employeeById(String id) {
    for (final e in _employees) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<TimeEntry> timeEntriesForEmployee(String employeeId) =>
      _timeEntries.where((t) => t.employeeId == employeeId).toList();
  List<EmployeePayment> paymentsForEmployee(String employeeId) =>
      _employeePayments.where((p) => p.employeeId == employeeId).toList();

  Future<Employee> createEmployee({
    required String name,
    String role = 'employee',
    String payType = 'hourly',
    int rateCents = 0,
    double percent = 0,
  }) async {
    final now = DateTime.now();
    final e = Employee(
      id: newId(),
      name: name.trim(),
      role: role,
      payType: payType,
      rateCents: rateCents,
      percent: percent,
      createdAt: now,
    );
    await _employeeRepo.save(e);
    final firstCondition = PayCondition(
      id: newId(),
      employeeId: e.id,
      payType: payType,
      rateCents: rateCents,
      percent: percent,
      validFrom: _nextValidFrom(e.id, now),
      createdAt: now,
    );
    await _payConditionRepo.save(firstCondition);
    _payConditions = [..._payConditions, firstCondition];
    _payConditionCache.remove(e.id);
    _employees = [..._employees, e];
    notifyListeners();
    return e;
  }

  /// Следующая дата действия условия: строго позже последней у сотрудника,
  /// чтобы пакетные правки в одном ms не ломали UNIQUE (employee_id, valid_from).
  DateTime _nextValidFrom(String employeeId, DateTime at) {
    final existing = _payConditions
        .where((c) => c.employeeId == employeeId && c.deletedAt == null)
        .toList();
    if (existing.isEmpty) return at;
    final latest = existing.reduce(
      (a, b) => a.validFrom.isAfter(b.validFrom) ? a : b,
    );
    return at.isAfter(latest.validFrom) ? at : latest.validFrom.add(const Duration(milliseconds: 1));
  }

  Future<void> updateEmployee(Employee e) async {
    final now = DateTime.now();
    final existing = conditionsForEmployee(e.id);
    final current = existing.isEmpty
        ? null
        : existing.reduce((a, b) => a.validFrom.isAfter(b.validFrom) ? a : b);
    final changed = current == null ||
        current.payType != e.payType ||
        current.rateCents != e.rateCents ||
        current.percent != e.percent;
    await _employeeRepo.save(e);
    final idx = _employees.indexWhere((x) => x.id == e.id);
    if (idx == -1) {
      _employees = [..._employees, e];
    } else {
      _employees[idx] = e;
    }
    if (changed) {
      final newCondition = PayCondition(
        id: newId(),
        employeeId: e.id,
        payType: e.payType,
        rateCents: e.rateCents,
        percent: e.percent,
        validFrom: _nextValidFrom(e.id, now),
        createdAt: now,
      );
      await _payConditionRepo.save(newCondition);
      _payConditions = [..._payConditions, newCondition];
      _payConditionCache.remove(e.id);
    }
    notifyListeners();
  }

  Future<void> deleteEmployee(String id) async {
    await _employeeRepo.delete(id);
    _employees = _employees.where((e) => e.id != id).toList();
    _timeEntries = _timeEntries.where((t) => t.employeeId != id).toList();
    _employeePayments = _employeePayments
        .where((p) => p.employeeId != id)
        .toList();
    notifyListeners();
  }

  Future<TimeEntry> addTimeEntry({
    required String employeeId,
    String? jobId,
    required DateTime startedAt,
    DateTime? endedAt,
    int minutes = 0,
    String? note,
  }) async {
    final t = TimeEntry(
      id: newId(),
      employeeId: employeeId,
      jobId: jobId,
      startedAt: startedAt,
      endedAt: endedAt,
      minutes: minutes < 0 ? 0 : minutes,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now(),
    );
    await _timeEntryRepo.save(t);
    _timeEntries = [t, ..._timeEntries];
    notifyListeners();
    return t;
  }

  Future<void> deleteTimeEntry(String id) async {
    await _timeEntryRepo.delete(id);
    _timeEntries = _timeEntries.where((t) => t.id != id).toList();
    notifyListeners();
  }

  Future<EmployeePayment> addEmployeePayment({
    required String employeeId,
    required String type,
    required int amountCents,
    String? note,
  }) async {
    ensurePeriodOpen();
    final p = EmployeePayment(
      id: newId(),
      employeeId: employeeId,
      type: type,
      amountCents: amountCents < 0 ? 0 : amountCents,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: DateTime.now(),
    );
    await _paymentRepo.save(p);
    _employeePayments = [p, ..._employeePayments];

    // Платежи наличными отражаются в журнале денег и балансах счетов.
    final cashTypes = {'advance', 'payout'};
    if (cashTypes.contains(type) && _accounts.isNotEmpty) {
      final account = _accounts.firstWhere(
        (a) => !a.archived,
        orElse: () => _accounts.first,
      );
      final tx = MoneyTransaction(
        id: newId(),
        accountId: account.id,
        kind: 'employee_payment',
        direction: 'out',
        amountCents: amountCents < 0 ? 0 : amountCents,
        category: type == 'advance' ? 'Аванс сотруднику' : 'Выплата зарплаты',
        note: note?.trim().isEmpty == true ? p.note : note?.trim(),
        relatedTransactionId: p.id,
        createdAt: p.createdAt,
        shiftId: openShift()?.id,
      );
      await _moneyTxRepo.save(tx);
      _moneyTransactions = [tx, ..._moneyTransactions];
    }
    notifyListeners();
    return p;
  }

  Future<void> deleteEmployeePayment(String id) async {
    await _paymentRepo.delete(id);
    _employeePayments = _employeePayments.where((p) => p.id != id).toList();

    // Возвращаем связанные  транзакции.
    final linked = _moneyTransactions
        .where(
          (t) => t.kind == 'employee_payment' && t.relatedTransactionId == id,
        )
        .toList();
    for (final tx in linked) {
      await _moneyTxRepo.voidTransaction(tx.id);
      final idx = _moneyTransactions.indexWhere((t) => t.id == tx.id);
      if (idx != -1) {
        _moneyTransactions[idx] = MoneyTransaction.fromMap(
          _moneyTransactions[idx].toMap()..['voided'] = 1,
        );
      }
    }
    _moneyTransactions = await _moneyTxRepo.getAll();
    try {
      await _appDatabase.audit(action: 'employee_payment.delete');
    } catch (_) {}
    notifyListeners();
  }

  int earnedCents(String employeeId) {
    return _intCache.putIfAbsent('earned:$employeeId', () {
      final emp = employeeById(employeeId);
      if (emp == null) return 0;
      int earned = 0;
      // hourly time
      if (emp.payType == 'hourly' ||
          emp.payType == 'mixed' ||
          emp.payType == 'salary') {
        final mins = _timeEntries
            .where((t) => t.employeeId == employeeId)
            .fold(0, (s, t) => s + t.minutes);
        earned += (mins * emp.rateCents / 60).round();
      }
      // piece: fixed per completed job
      if (emp.payType == 'piece' || emp.payType == 'mixed') {
        final doneJobs = _jobs.where(
          (j) =>
              j.assigneeId == employeeId &&
              (j.status == JobStatus.done || j.status == JobStatus.closed) &&
              !j.archived,
        );
        if (emp.payType == 'piece') {
          earned += doneJobs.length * emp.rateCents;
        }
      }
      // percent of job price
      if (emp.payType == 'percent' || emp.payType == 'mixed') {
        final doneJobs = _jobs.where(
          (j) =>
              j.assigneeId == employeeId &&
              (j.status == JobStatus.done || j.status == JobStatus.closed) &&
              !j.archived,
        );
        final price = doneJobs.fold(0, (s, j) => s + j.priceCents);
        earned += (price * emp.percent / 100).round();
      }
      return earned;
    });
  }

  int employeeBalanceOwed(String employeeId) {
    return _balanceCache.putIfAbsent(employeeId, () {
      final earned = earnedCents(employeeId);
      final payments = _employeePayments.where(
        (p) => p.employeeId == employeeId,
      );
      final advances = payments
          .where((p) => p.type == 'advance')
          .fold(0, (s, p) => s + p.amountCents);
      final payouts = payments
          .where((p) => p.type == 'payout')
          .fold(0, (s, p) => s + p.amountCents);
      final bonuses = payments
          .where((p) => p.type == 'bonus')
          .fold(0, (s, p) => s + p.amountCents);
      final penalties = payments
          .where((p) => p.type == 'penalty')
          .fold(0, (s, p) => s + p.amountCents);
      return earned + bonuses - penalties - advances - payouts;
    });
  }

  // Excel/CSV import helpers: Finance and inventory only; backup format stays JSON.
  Future<int> importInventoryFromExcel() async {
    final rows = await BackupService.pickSpreadsheet();
    if (rows == null || rows.isEmpty) return 0;
    final header = rows.first.map(_norm).toList();
    final nameIdx = _col(header, ['name', 'название', 'наименование']);
    if (nameIdx < 0) return 0;
    final kindIdx = _col(header, ['kind', 'тип']);
    final unitIdx = _col(header, ['unit']);
    final sellIdx = _col(header, ['sell_price', 'sell_price_cents', 'price']);
    final costIdx = _col(header, ['cost_cents', 'cost']);
    final stockIdx = _col(header, ['stock', 'stock_qty', 'qty']);
    final minIdx = _col(header, ['min', 'min_qty', 'min stock']);
    final categoryIdx = _col(header, ['category', 'Категория']);
    final now = DateTime.now();
    final created = <InventoryItem>[];
    for (final raw in rows.skip(1)) {
      if (raw.length <= nameIdx) continue;
      final name = _str(raw, nameIdx);
      if (name.isEmpty) continue;
      final sellCents = _moneyCents(raw, sellIdx, 0);
      final costCents = _moneyCents(raw, costIdx, 0);
      final stockQty = _num(raw, stockIdx, 0);
      final minQty = _num(raw, minIdx, 0);
      final kindRaw = _str(raw, kindIdx);
      final kind = kindRaw == 'service' ? 'service' : 'good';
      final unit = _strDefault(raw, unitIdx, 'шт');
      final category = _str(raw, categoryIdx);
      final item = InventoryItem(
        id: newId(),
        name: name,
        kind: kind,
        unit: unit,
        sellPriceCents: sellCents,
        costCents: costCents,
        category: category,
        trackStock: true,
        stockQty: stockQty,
        minQty: minQty,
        archived: false,
        createdAt: now,
        updatedAt: now,
      );
      await _inventoryRepo.save(item);
      created.add(item);
    }
    if (created.isNotEmpty) {
      _inventoryItems = [...created, ..._inventoryItems];
      notifyListeners();
    }
    return created.length;
  }

  Future<int> importTransactionsFromExcel() async {
    final rows = await BackupService.pickSpreadsheet();
    if (rows == null || rows.isEmpty || _accounts.isEmpty) return 0;
    final header = rows.first.map(_norm).toList();
    final dateIdx = _col(header, ['date', 'Дата']);
    final accountIdx = _col(header, ['account', 'счёт', 'счет']);
    final directionIdx = _col(header, ['direction', 'Направление']);
    final amountIdx = _col(header, ['amount', 'amount_cents', 'сумма']);
    final categoryIdx = _col(header, ['category', 'Категория']);
    final noteIdx = _col(header, ['note', 'Примечание']);
    final kindIdx = _col(header, ['kind', 'тип']);
    if (amountIdx < 0) return 0;

    final created = <MoneyTransaction>[];
    for (final raw in rows.skip(1)) {
      final amount = _moneyCents(raw, amountIdx, -1);
      if (amount <= 0) continue;
      final accountName = accountIdx >= 0 ? _str(raw, accountIdx) : '';
      final account = accountName.isEmpty
          ? _accounts.firstWhere(
              (a) => !a.archived,
              orElse: () => _accounts.first,
            )
          : _accounts.firstWhere(
              (a) => a.name.toLowerCase() == accountName.toLowerCase(),
              orElse: () => _accounts.first,
            );
      final directionRaw = directionIdx >= 0
          ? _str(raw, directionIdx).toLowerCase()
          : '';
      final direction =
          directionRaw == 'out' ||
              directionRaw == 'expense' ||
              directionRaw == 'расход'
          ? 'out'
          : 'in';
      final kindRaw = kindIdx >= 0
          ? _str(raw, kindIdx).toLowerCase()
          : 'income';
      final kind = kindRaw.isEmpty
          ? (direction == 'in' ? 'income' : 'expense')
          : kindRaw;
      final note = noteIdx >= 0 ? _str(raw, noteIdx) : null;
      final category = categoryIdx >= 0 ? _str(raw, categoryIdx) : '';
      final parsedDate = dateIdx >= 0
          ? _parseImportDate(_str(raw, dateIdx))
          : null;
      final tx = MoneyTransaction(
        id: newId(),
        accountId: account.id,
        kind: kind,
        direction: direction,
        amountCents: amount,
        category: category,
        note: note,
        createdAt: parsedDate ?? DateTime.now(),
        shiftId: openShift()?.id,
      );
      await _moneyTxRepo.save(tx);
      created.add(tx);
    }
    if (created.isNotEmpty) {
      _moneyTransactions = [...created, ..._moneyTransactions];
      notifyListeners();
    }
    return created.length;
  }

  static String _norm(dynamic value) =>
      value?.toString().trim().toLowerCase() ?? '';

  static int _col(List<String> header, List<String> names) {
    for (final name in names) {
      final idx = header.indexWhere((h) => h == _norm(name));
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static String _str(List<dynamic> row, int idx) =>
      idx >= 0 && idx < row.length ? row[idx]?.toString().trim() ?? '' : '';

  static String _strDefault(List<dynamic> row, int idx, String fallback) {
    final v = _str(row, idx);
    return v.isEmpty ? fallback : v;
  }

  static int _moneyCents(List<dynamic> row, int idx, int fallback) {
    if (idx < 0 || idx >= row.length) return fallback;
    final raw =
        row[idx]?.toString().trim().replaceAll(' ', '').replaceAll(',', '.') ??
        '';
    final value = double.tryParse(raw);
    if (value == null) return fallback;
    return (value * 100).round();
  }

  static double _num(List<dynamic> row, int idx, double fallback) {
    if (idx < 0 || idx >= row.length) return fallback;
    final raw =
        row[idx]?.toString().trim().replaceAll(' ', '').replaceAll(',', '.') ??
        '';
    return double.tryParse(raw) ?? fallback;
  }

  static DateTime? _parseImportDate(String value) {
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    final parts = value.split('.');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  // backup
  Map<String, dynamic> backupData() {
    return {
      'format': 'masters-backup',
      'version': 10,
      'exported_at': DateTime.now().toIso8601String(),
      for (final mapping in kBackupTables)
        mapping.key: _tableRows(mapping.table),
    };
  }

  /// Данные таблицы для бэкапа. Если таблицы в базе ещё нет (старая схема),
  /// возвращаем пустой список — она просто не попадёт в JSON.
  List<Map<String, Object?>> _tableRows(String table) {
    switch (table) {
      case 'clients':
        return _clients.map((c) => c.toMap()).toList();
      case 'objects':
        return _objects.map((o) => o.toMap()).toList();
      case 'jobs':
        return _jobs.map((j) => j.toMap()).toList();
      case 'job_stages':
        return _stages.map((s) => s.toMap()).toList();
      case 'materials':
        return _materials.map((m) => m.toMap()).toList();
      case 'work_sessions':
        return _sessions.map((s) => s.toMap()).toList();
      case 'accounts':
        return _accounts.map((a) => a.toMap()).toList();
      case 'cash_shifts':
        return _shifts.map((s) => s.toMap()).toList();
      case 'money_transactions':
        return _moneyTransactions.map((t) => t.toMap()).toList();
      case 'inventory_items':
        return _inventoryItems.map((i) => i.toMap()).toList();
      case 'stock_movements':
        return _stockMovements.map((m) => m.toMap()).toList();
      case 'inventory_compositions':
        return _compositionLines.map((c) => c.toMap()).toList();
      case 'appointments':
        return _appointments.map((a) => a.toMap()).toList();
      case 'booking_resources':
        return _bookingResources.map((r) => r.toMap()).toList();
      case 'client_reminders':
        return _reminders.map((r) => r.toMap()).toList();
      case 'employees':
        return _employees.map((e) => e.toMap()).toList();
      case 'time_entries':
        return _timeEntries.map((t) => t.toMap()).toList();
      case 'employee_payments':
        return _employeePayments.map((p) => p.toMap()).toList();
      case 'suppliers':
        return _suppliers.map((s) => s.toMap()).toList();
      case 'purchases':
        return _purchases.map((p) => p.toMap()).toList();
      case 'purchase_lines':
        return _purchaseLines.map((l) => l.toMap()).toList();
      case 'recurring_payments':
        return _recurringPayments.map((p) => p.toMap()).toList();
      case 'payroll_periods':
        return _payrollPeriods.map((p) => p.toMap()).toList();
      case 'period_closures':
        return _closedPeriods.map((p) => p.toMap()).toList();
      case 'pay_conditions':
        return _payConditions.map((c) => c.toMap()).toList();
      case 'payslips':
        return _payslips.map((p) => p.toMap()).toList();
      case 'accrual_entries':
        return _accrualEntries.map((a) => a.toMap()).toList();
      default:
        // Таблица из реестра ещё не загружена в store (например, v22) —
        // возвращаем пустой список, чтобы не ломать формат.
        return <Map<String, Object?>>[];
    }
  }

  Future<void> restoreFromBackup(Map<String, dynamic> data) async {
    if (data['format'] != 'masters-backup') {
      throw const FormatException('Это не резервная копия Masters.');
    }
    final version = data['version'];
    if (version is! int || version > 10) {
      throw const FormatException('Неподдерживаемая версия копии.');
    }

    final restored = <String, List<Map<String, Object?>>>{};
    for (final mapping in kBackupTables) {
      final rows = data[mapping.key];
      if (rows is! List) continue;
      final list = <Map<String, Object?>>[];
      for (final item in rows) {
        if (item is Map) {
          list.add(Map<String, Object?>.from(item));
        }
      }
      restored[mapping.table] = list;
    }

    // Таблицы, которые реально существуют в базе.
    final existing = await _appDatabase.existingTables();

    await _appDatabase.database.transaction((txn) async {
      // Удаляем в обратном порядке: сначала дети, потом родители.
      for (final mapping in kBackupTables.reversed) {
        final table = mapping.table;
        if (!existing.contains(table)) continue;
        await txn.delete(table);
      }

      final batch = txn.batch();
      final idCache = <String, Set<String>>{};

      String? parentId(Map<String, Object?> row, String column) {
        final v = row[column];
        return v is String ? v : null;
      }

      bool parentExists(String table, String? id) {
        if (id == null || id.isEmpty) return true;
        final cache = idCache[table] ??= <String>{};
        if (cache.isEmpty) {
          final rows = restored[table] ?? <Map<String, Object?>>[];
          for (final r in rows) {
            final rid = r['id'];
            if (rid is String) cache.add(rid);
          }
        }
        return cache.contains(id);
      }

      for (final mapping in kBackupTables) {
        final table = mapping.table;
        if (!existing.contains(table)) continue;
        final rows = restored[table] ?? <Map<String, Object?>>[];
        for (final row in rows) {
          // Проверяем обязательные ссылки: если родителя нет в копии,
          // строку пропускаем, чтобы не получить «пустую» запись в UI.
          final deps = kTableDependencies[table];
          if (deps != null) {
            bool skip = false;
            for (final dep in deps) {
              final column = dep[0];
              final parentTable = dep[1];
              final id = parentId(row, column);
              if (id != null && !parentExists(parentTable, id)) {
                skip = true;
                break;
              }
            }
            if (skip) continue;
          }
          batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    });

    // Копия могла быть снята со старой сборки с уже испорченными строками —
    // лечим их до загрузки в память, иначе mojibake вернётся на экраны.
    await AppDatabase.repairStoredMojibake(_appDatabase.database);

    await load();
  }

  /// App-level integrity check, used on web where FK enforcement is off.
  Future<List<String>> checkDataIntegrity() async {
    return _appDatabase.integrityIssues();
  }

  Future<void> _reconcileEmployeePayments() async {
    const cashTypes = {'advance', 'payout'};
    bool changed = false;
    for (final payment in List<EmployeePayment>.from(_employeePayments)) {
      if (!cashTypes.contains(payment.type)) continue;
      final already = _moneyTransactions.any(
        (t) =>
            t.kind == 'employee_payment' &&
            !t.voided &&
            t.relatedTransactionId == payment.id,
      );
      if (already) continue;
      if (_accounts.isEmpty) continue;
      final account = _accounts.firstWhere(
        (a) => !a.archived,
        orElse: () => _accounts.first,
      );
      final tx = MoneyTransaction(
        id: newId(),
        accountId: account.id,
        kind: 'employee_payment',
        direction: 'out',
        amountCents: payment.amountCents,
        category: payment.type == 'advance'
            ? 'Аванс сотруднику'
            : 'Выплата зарплаты',
        note: payment.note,
        relatedTransactionId: payment.id,
        createdAt: payment.createdAt,
        shiftId: null,
      );
      await _moneyTxRepo.save(tx);
      _moneyTransactions = [tx, ..._moneyTransactions];
      changed = true;
    }
    if (!_loaded && changed) {
      // notify happens after load(); suppress extra flicker here.
    }
  }

  Future<BackupMergeResult> mergeFromBackup(
    Map<String, dynamic> data, {
    bool dryRun = false,
    Set<String>? applyConflictIds,
  }) async {
    if (data['format'] != 'masters-backup') {
      throw const FormatException('Это не копия Masters.');
    }
    final version = data['version'];
    if (version is! int || version > 10) {
      throw const FormatException('Неподдерживаемая версия копии.');
    }
    final result = await _appDatabase.mergeSnapshot(
      data,
      dryRun: dryRun,
      applyConflictIds: applyConflictIds,
    );
    if (!dryRun) await load();
    try {
      await auditAction(
        action: 'backup.merge',
        entity: 'backup',
        after: {'affected': result.affected},
      );
    } catch (_) {}
    return result;
  }

  Future<List<Map<String, Object?>>> auditEntries({int limit = 100}) async {
    return _appDatabase.auditLog(limit: limit);
  }

  Future<void> auditAction({
    required String action,
    String entity = 'app',
    String? entityId,
    Object? before,
    Object? after,
    String? deviceId,
  }) async {
    await _appDatabase.audit(
      action: action,
      entity: entity,
      entityId: entityId,
      before: before,
      after: after,
      deviceId: deviceId,
    );
  }

  Future<void> seedDemoData(String preset) async {
    if (!_loaded) {
      await load();
    }
    final hasRealAccounts =
        _accounts.any((a) => a.name != 'Наличные') || _accounts.length > 1;
    if (_clients.isNotEmpty || _jobs.isNotEmpty || hasRealAccounts) {
      return;
    }

    final ownerId = selfEmployee?.id;
    final cash = await createAccount(name: 'Касса', type: 'cash');
    final bank = await createAccount(name: 'Банк', type: 'bank');

    final autoClient = await createClient(
      name: 'Демо: Авто',
      phone: '+7 900 100-20-30',
      note: 'Постоянный клиент, всегда вовремя',
    );
    final homeClient = await createClient(
      name: 'Демо: Дом',
      phone: '+7 900 200-30-40',
      note: null,
    );
    final car = await createObject(
      clientId: autoClient.id,
      title: 'Автомобиль',
      address: 'г. Екатеринбург, гараж #3',
    );
    final apartment = await createObject(
      clientId: homeClient.id,
      title: 'Квартира',
      address: 'ул. Ленина, 42',
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    // Склад: 3 позиции, одна из них с низким остатком.
    final oil = await createInventoryItem(
      name: 'Масло моторное 5W-40',
      kind: 'good',
      unit: 'л',
      sellPriceCents: 120000,
      costCents: 80000,
      category: 'Расходники',
      trackStock: true,
      stockQty: 12,
      minQty: 3,
    );
    final pads = await createInventoryItem(
      name: 'Колодки тормозные передние',
      kind: 'good',
      unit: 'компл',
      sellPriceCents: 350000,
      costCents: 220000,
      category: 'Запчасти',
      trackStock: true,
      stockQty: 2,
      minQty: 3,
    );
    await createInventoryItem(
      name: 'Диагностика',
      kind: 'service',
      unit: 'шт',
      sellPriceCents: 150000,
      costCents: 0,
      category: 'Услуги',
      trackStock: false,
      stockQty: 0,
      minQty: 0,
    );

    // Заказы во всех колонках канбана.
    final jobNew = await createJob(
      clientId: autoClient.id,
      objectId: car.id,
      title: 'Демо: переобувка шин',
      status: JobStatus.nuevo,
      priority: JobPriority.high,
      priceCents: 500000,
      costCents: 150000,
      dueDate: today,
      assigneeId: ownerId,
      tags: 'шины, сезон',
    );
    final jobInProgress = await createJob(
      clientId: autoClient.id,
      objectId: car.id,
      title: 'Демо: замена колодок',
      status: JobStatus.inProgress,
      priority: JobPriority.medium,
      priceCents: 1200000,
      costCents: 320000,
      dueDate: today,
      assigneeId: ownerId,
      tags: null,
    );
    await createJob(
      clientId: homeClient.id,
      objectId: apartment.id,
      title: 'Демо: установка розеток',
      status: JobStatus.waitingParts,
      priority: JobPriority.low,
      priceCents: 800000,
      costCents: 210000,
      dueDate: tomorrow,
      assigneeId: ownerId,
      tags: 'электрика',
    );
    await createJob(
      clientId: autoClient.id,
      objectId: car.id,
      title: 'Демо: замена масла',
      status: JobStatus.done,
      priority: JobPriority.medium,
      priceCents: 350000,
      costCents: 90000,
      dueDate: yesterday,
      assigneeId: ownerId,
    );
    final jobClosed = await createJob(
      clientId: homeClient.id,
      title: 'Демо: консультация',
      status: JobStatus.closed,
      priceCents: 100000,
      costCents: 0,
      dueDate: yesterday.add(const Duration(days: -3)),
      assigneeId: ownerId,
    );
    // Keep reference so the demo seed records the closed job.
    if (jobClosed.id.isEmpty) {}
    await setJobPinned(jobInProgress.id, true);

    // Материалы и время к заказу.
    await addMaterial(
      jobId: jobInProgress.id,
      name: 'Колодки тормозные передние',
      quantity: 1,
      unit: 'компл',
      priceCents: 220000,
    );
    await startWorkSession(jobId: jobInProgress.id);
    final open = openWorkSession;
    if (open != null) {
      await stopWorkSession(open.id);
    }

    // Деньги и транзакции.
    await addTransaction(
      accountId: cash.id,
      kind: 'sale',
      direction: 'in',
      amountCents: 120000,
      category: 'Продажа',
      clientId: autoClient.id,
      jobId: jobInProgress.id,
    );
    await addTransaction(
      accountId: cash.id,
      kind: 'expense',
      direction: 'out',
      amountCents: 40000,
      category: 'Расходники',
    );
    await addTransaction(
      accountId: bank.id,
      kind: 'expense',
      direction: 'out',
      amountCents: 90000,
      category: 'Аренда',
      note: 'Склад за месяц',
    );
    await transferBetweenAccounts(cash.id, bank.id, 50000);

    // Смена кассы.
    await openCashShift(accountId: cash.id, openingCents: 20000);

    // Сотрудник, время и выплаты.
    final employee = await createEmployee(
      name: 'Иван',
      role: 'employee',
      payType: 'hourly',
      rateCents: 200000,
    );
    await addTimeEntry(
      employeeId: employee.id,
      jobId: jobInProgress.id,
      startedAt: today.add(const Duration(hours: 9)),
      endedAt: today.add(const Duration(hours: 11)),
      minutes: 120,
      note: 'Работа по заказу',
    );
    await addEmployeePayment(
      employeeId: employee.id,
      type: 'advance',
      amountCents: 100000,
      note: 'Аванс',
    );

    // Поставщик и закупка.
    final supplier = await createSupplier(
      name: 'Демо-поставщик',
      phone: '+7 900 300-40-50',
      note: 'Моторные масла и фильтры',
    );
    await createPurchase(
      supplierId: supplier.id,
      accountId: bank.id,
      paidCents: 300000,
      note: 'Закупка расходников',
      lines: [
        {'itemId': oil.id, 'qty': 5.0, 'unitPriceCents': 80000},
        {'itemId': pads.id, 'qty': 3.0, 'unitPriceCents': 220000},
      ],
    );

    // Регулярные платежи: один просроченный, один будущий.
    await createRecurringPayment(
      name: 'Аренда склада',
      direction: 'out',
      amountCents: 300000,
      category: 'Аренда',
      accountId: bank.id,
      intervalDays: 30,
      nextDueAt: today.subtract(const Duration(days: 2)),
    );
    await createRecurringPayment(
      name: 'Интернет',
      direction: 'out',
      amountCents: 99000,
      category: 'Связь',
      accountId: bank.id,
      intervalDays: 30,
      nextDueAt: today.add(const Duration(days: 10)),
    );

    // Запись в календаре.
    final resourceId = defaultResource()?.id;
    await createAppointment(
      title: 'Демо: замена масла — запись',
      startAt: tomorrow.add(const Duration(hours: 10)),
      endAt: tomorrow.add(const Duration(hours: 11)),
      clientId: autoClient.id,
      objectId: car.id,
      resourceId: resourceId,
      note: 'Не забыть проверить свечи',
    );

    // Напоминание.
    await createReminder(
      clientId: autoClient.id,
      jobId: jobNew.id,
      type: 'manual',
      title: 'Позвонить клиенту',
      body: 'Подтвердить время переобувки',
      dueAt: today.add(const Duration(hours: 2)),
    );

  }

  List<ClosedPeriod> get closedPeriods => List.unmodifiable(_closedPeriods);

  bool isPeriodClosed([DateTime? at]) {
    final date = at ?? DateTime.now();
    return _closedPeriods.any((period) => period.contains(date));
  }

  bool isPeriodOpen([DateTime? at]) => !isPeriodClosed(at);

  void ensurePeriodOpen([DateTime? at]) {
    if (isPeriodClosed(at ?? DateTime.now())) {
      throw StateError(
        'Указанный период закрыт. Измените дату или переоткройте период.',
      );
    }
  }

  Future<ClosedPeriod> closePeriod({
    DateTime? start,
    DateTime? end,
    String? note,
  }) async {
    final now = DateTime.now();
    final periodStart = start ?? DateTime(now.year, now.month, 1);
    final periodEnd =
        end ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    for (final existing in _closedPeriods) {
      if (periodStart.isBefore(existing.end) &&
          periodEnd.isAfter(existing.start)) {
        throw ArgumentError('Новый период пересекается с уже закрытым.');
      }
    }
    final closure = ClosedPeriod(
      id: newId(),
      start: periodStart,
      end: periodEnd,
      closedAt: now,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    await _appDatabase.insertPeriodClosure(closure.toMap());
    _closedPeriods = [closure, ..._closedPeriods];
    try {
      await auditAction(
        action: 'period.close',
        entity: 'period',
        entityId: closure.id,
        after: closure.toMap(),
      );
    } catch (_) {}
    notifyListeners();
    return closure;
  }

  Future<void> reopenPeriod(String id) async {
    final was = _closedPeriods.firstWhere((p) => p.id == id);
    await _appDatabase.deletePeriodClosure(id);
    _closedPeriods = _closedPeriods.where((p) => p.id != id).toList();
    try {
      await auditAction(
        action: 'period.reopen',
        entity: 'period',
        entityId: id,
        before: was.toMap(),
      );
    } catch (_) {}
    notifyListeners();
  }

  List<RecurringPayment> get recurringPayments =>
      List.unmodifiable(_recurringPayments);

  Future<void> _scheduleRecurringReminder() async {
    for (final payment in List<RecurringPayment>.from(_recurringPayments)) {
      try {
        await ReminderService.cancelRecurringReminder(payment.id);
      } catch (_) {}
      if (!payment.active) continue;
      try {
        await ReminderService.scheduleRecurringReminder(
          id: payment.id,
          title: payment.name,
          direction: payment.direction,
          dueAt: payment.nextDueAt,
          amountCents: payment.amountCents,
          accountName: payment.accountId == null
              ? null
              : accountById(payment.accountId!)?.name,
        );
      } catch (_) {}
    }
  }

  Future<void> rescheduleAllRecurringReminders() async {
    await _scheduleRecurringReminder();
  }

  Future<void> scheduleRecurringReminder() async {
    await _scheduleRecurringReminder();
  }

  Future<void> syncRecurringReminders() async {
    await _scheduleRecurringReminder();
  }

  Future<RecurringPayment> createRecurringPayment({
    required String name,
    String direction = 'out',
    required int amountCents,
    String category = '',
    String? accountId,
    int intervalDays = 30,
    DateTime? nextDueAt,
    String? note,
  }) async {
    ensurePeriodOpen();
    final now = DateTime.now();
    final payment = RecurringPayment(
      id: newId(),
      name: name.trim(),
      direction: direction,
      amountCents: amountCents < 0 ? 0 : amountCents,
      category: category.trim(),
      accountId: accountId,
      intervalDays: intervalDays < 1 ? 1 : intervalDays,
      nextDueAt:
          nextDueAt ??
          now.add(Duration(days: intervalDays < 1 ? 1 : intervalDays)),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _recurringRepo.save(payment);
    _recurringPayments = [payment, ..._recurringPayments];
    try {
      if (payment.active) {
        await ReminderService.scheduleRecurringReminder(
          id: payment.id,
          title: payment.name,
          direction: payment.direction,
          dueAt: payment.nextDueAt,
          amountCents: payment.amountCents,
          accountName: payment.accountId == null
              ? null
              : accountById(payment.accountId!)?.name,
        );
      } else {
        await ReminderService.cancelRecurringReminder(payment.id);
      }
    } catch (_) {}
    await auditAction(
      action: 'recurring_payment.create',
      entity: 'recurring_payment',
      entityId: payment.id,
      after: payment.toMap(),
    );
    notifyListeners();
    return payment;
  }

  Future<void> updateRecurringPayment(RecurringPayment payment) async {
    ensurePeriodOpen();
    final updated = payment.copyWith(updatedAt: DateTime.now());
    await _recurringRepo.save(updated);
    final idx = _recurringPayments.indexWhere((r) => r.id == updated.id);
    if (idx == -1) {
      _recurringPayments = [updated, ..._recurringPayments];
    } else {
      _recurringPayments[idx] = updated;
    }
    try {
      await ReminderService.cancelRecurringReminder(updated.id);
      if (updated.active) {
        await ReminderService.scheduleRecurringReminder(
          id: updated.id,
          title: updated.name,
          direction: updated.direction,
          dueAt: updated.nextDueAt,
          amountCents: updated.amountCents,
          accountName: updated.accountId == null
              ? null
              : accountById(updated.accountId!)?.name,
        );
      }
    } catch (_) {}
    await auditAction(
      action: 'recurring_payment.update',
      entity: 'recurring_payment',
      entityId: updated.id,
      after: updated.toMap(),
    );
    notifyListeners();
  }

  Future<void> deleteRecurringPayment(String id) async {
    ensurePeriodOpen();
    await _recurringRepo.delete(id);
    _recurringPayments = _recurringPayments.where((r) => r.id != id).toList();
    try {
      await ReminderService.cancelRecurringReminder(id);
    } catch (_) {}
    await auditAction(
      action: 'recurring_payment.delete',
      entity: 'recurring_payment',
      entityId: id,
    );
    notifyListeners();
  }

  /// Executes all recurring payments due on or before [now].
  Future<int> runDueRecurringPayments({DateTime? now}) async {
    final current = now ?? DateTime.now();
    int count = 0;
    for (final payment in List<RecurringPayment>.from(_recurringPayments)) {
      if (!payment.active || payment.nextDueAt.isAfter(current)) continue;
      try {
        ensurePeriodOpen(payment.nextDueAt);
      } catch (_) {
        continue;
      }
      final account = payment.accountId ?? storeDefaultAccountId();
      await addTransaction(
        accountId: account,
        kind: 'recurring',
        direction: payment.direction,
        amountCents: payment.amountCents,
        category: payment.category.isEmpty ? payment.name : payment.category,
        note: payment.note,
      );
      var next = payment.nextDueAt;
      while (!next.isAfter(current)) {
        next = next.add(
          Duration(days: payment.intervalDays < 1 ? 1 : payment.intervalDays),
        );
      }
      final updated = payment.copyWith(nextDueAt: next, updatedAt: current);
      await updateRecurringPayment(updated);
      try {
        await ReminderService.cancelRecurringReminder(updated.id);
        if (updated.active) {
          await ReminderService.scheduleRecurringReminder(
            id: updated.id,
            title: updated.name,
            direction: updated.direction,
            dueAt: updated.nextDueAt,
            amountCents: updated.amountCents,
            accountName: updated.accountId == null
                ? null
                : accountById(updated.accountId!)?.name,
          );
        }
      } catch (_) {}
      count++;
    }
    return count;
  }

  String storeDefaultAccountId() {
    final account = _accounts.firstWhere(
      (a) => !a.archived,
      orElse: () =>
          _accounts.isNotEmpty ? _accounts.first           : throw StateError('Нет счёта.'),
    );
    return account.id;
  }

  List<PayrollPeriod> get payrollPeriods => List.unmodifiable(_payrollPeriods);

  Future<PayrollPeriod> createPayrollPeriod({
    required String name,
    required DateTime startAt,
    required DateTime endAt,
    String? note,
  }) async {
    final now = DateTime.now();
    final period = PayrollPeriod(
      id: newId(),
      name: name.trim(),
      startAt: startAt,
      endAt: endAt,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _payrollRepo.save(period);
    _payrollPeriods = [period, ..._payrollPeriods];
    await auditAction(
      action: 'payroll_period.create',
      entity: 'payroll_period',
      entityId: period.id,
      after: period.toMap(),
    );
    notifyListeners();
    return period;
  }

  /// Строки начислений сотрудника (живые, без мягко удалённых).
  List<AccrualEntry> accrualEntriesForEmployee(String employeeId) {
    return _accrualEntries
        .where((e) => e.employeeId == employeeId && e.deletedAt == null)
        .toList();
  }

  /// Все условия оплаты (история изменений ставок).
  List<PayCondition> get payConditions => List.unmodifiable(_payConditions);

  /// Все ведомости (история версий).
  List<Payslip> get payslips => List.unmodifiable(_payslips);

  /// Условия оплаты сотрудника (все строки, включая мягко удалённые).
  List<PayCondition> conditionsForEmployee(String employeeId) {
    return _payConditionCache.putIfAbsent(employeeId, () {
      return _payConditions
          .where((c) => c.employeeId == employeeId)
          .toList();
    });
  }

  /// Ведомости по периоду (последние версии по сотруднику).
  List<Payslip> payslipsForPeriod(String periodId) {
    final byEmp = <String, Payslip>{};
    for (final s in _payslips) {
      if (s.periodId != periodId) continue;
      final cur = byEmp[s.employeeId];
      if (cur == null || s.version > cur.version) {
        byEmp[s.employeeId] = s;
      }
    }
    return byEmp.values.toList();
  }

  /// Все версии ведомостей периода, новые сверху (история пересчётов).
  List<Payslip> payslipHistoryForPeriod(String periodId) {
    final list = _payslips.where((s) => s.periodId == periodId).toList()
      ..sort((a, b) => b.version.compareTo(a.version));
    return list;
  }

  /// Все ведомости сотрудника (история версий).
  List<Payslip> payslipsForEmployee(String employeeId) {
    return _payslips
        .where((s) => s.employeeId == employeeId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Последняя ведомость сотрудника в периоде (или null).
  Payslip? latestPayslipFor(String periodId, String employeeId) {
    Payslip? best;
    for (final s in _payslips) {
      if (s.employeeId != employeeId || s.periodId != periodId) continue;
      if (best == null || s.version > best.version) best = s;
    }
    return best;
  }

  /// Строки начислений по ведомости (включая мягко удалённые при пересчёте).
  Future<List<AccrualEntry>> accrualEntriesForPayslip(String payslipId) async {
    final live = _accrualEntries
        .where((e) => e.payslipId == payslipId && e.deletedAt == null)
        .toList();
    if (live.isNotEmpty) return live;
    return _accrualEntryRepo.forPayslipIncludingDeleted(payslipId);
  }

  /// Условия оплаты сотрудника (все строки, включая мягко удалённые).

  /// Живой предпросмотр начислений по открытому периоду (не фиксирует данные).
  List<AccrualLine> previewAccrualLines(
    String employeeId,
    DateTime start,
    DateTime end,
  ) {
    final emp = employeeById(employeeId);
    if (emp == null) return const [];
    final endExclusive = periodEndExclusive(end);
    return buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditionsForEmployee(employeeId),
      timeEntries: _timeEntries
          .where((t) => t.employeeId == employeeId)
          .toList(),
      jobs: _jobs.where((j) => j.assigneeId == employeeId).toList(),
      defaultPayType: emp.payType,
    );
  }

  /// Сводка по периоду: одна строка на сотрудника (в_live_по_каждому_сотруднику).
  /// Закрытый период — по ведомостям, открытый — по движку вживую.
  List<Map<String, Object?>> payrollSummaryForPeriod(PayrollPeriod period) {
    final slips = payslipsForPeriod(period.id);
    if (slips.isNotEmpty) {
      return slips
          .map(
            (s) => <String, Object?>{
              'employee': employeeById(s.employeeId),
              'earned': s.accruedCents,
              'net': s.netCents,
              'bonus': s.bonusCents,
              'penalty': s.penaltyCents,
              'advance': s.advanceCents,
              'payout': s.payoutCents,
              'payslip': s,
            },
          )
          .toList();
    }
    // Открытый период: считаем вживую по каждому сотруднику.
    return _payrollSummaryLive(period.startAt, period.endAt);
  }

  /// Живая сводка по интервалу: тот же движок, что и у закрытия, поэтому
  /// предварительные суммы не расходятся с зафиксированными.
  List<Map<String, Object?>> _payrollSummaryLive(
    DateTime start,
    DateTime end,
  ) {
    final endExclusive = periodEndExclusive(end);
    final rows = <Map<String, Object?>>[];
    for (final emp in _employees.where((e) => !e.archived)) {
      final lines = buildAccrualLines(
        start: start,
        endExclusive: endExclusive,
        conditions: conditionsForEmployee(emp.id),
        timeEntries: _timeEntries
            .where((t) => t.employeeId == emp.id)
            .toList(),
        jobs: _jobs.where((j) => j.assigneeId == emp.id).toList(),
        defaultPayType: emp.payType,
      );
      final totals = paymentTotalsForPeriod(emp.id, start, end);
      final earned = lines.fold<int>(0, (s, l) => s + l.amountCents);
      final net = earned +
          (totals['bonus'] ?? 0) -
          (totals['penalty'] ?? 0) -
          (totals['advance'] ?? 0) -
          (totals['payout'] ?? 0);
      rows.add({
        'employee': emp,
        'earned': earned,
        'net': net,
        'bonus': totals['bonus'] ?? 0,
        'penalty': totals['penalty'] ?? 0,
        'advance': totals['advance'] ?? 0,
        'payout': totals['payout'] ?? 0,
        'payslip': null,
      });
    }
    return rows;
  }

  /// Подтверждение предварительной ведомости: статус → confirmed,
  /// сброс review_note, аудит сохраняет историю.
  Future<void> confirmPayslip(String payslipId) async {
    final slip = _payslips.firstWhere((s) => s.id == payslipId, orElse: () => throw ArgumentError('Ведомость не найдена'));
    if (slip.status == 'confirmed') return;
    final updated = slip.copyWith(
      status: 'confirmed',
      needsReview: false,
      reviewNote: null,
      updatedAt: DateTime.now(),
    );
    await _payslipRepo.save(updated);
    final idx = _payslips.indexWhere((s) => s.id == payslipId);
    if (idx != -1) _payslips[idx] = updated;
    await auditAction(
      action: 'payslip.confirm',
      entity: 'payslip',
      entityId: payslipId,
      before: slip.toMap(),
      after: updated.toMap(),
    );
    notifyListeners();
  }

  /// Подтвердить все предварительные ведомости периода.
  Future<int> confirmPreliminaryPayslips(String periodId) async {
    final slips = payslipsForPeriod(periodId).where((s) => s.status == 'preliminary').toList();
    for (final s in slips) {
      await confirmPayslip(s.id);
    }
    return slips.length;
  }

  /// Записи аудита по сущности (для отображения причины переоткрытия и т.п.).
  Future<List<Map<String, Object?>>> auditEntriesFor(
    String entity,
    String? entityId, {
    int limit = 50,
  }) async {
    final where = StringBuffer('entity = ?');
    final args = <Object?>[entity];
    if (entityId != null) {
      where.write(' AND entity_id = ?');
      args.add(entityId);
    }
    final rows = await _appDatabase.database.query(
      'audit_log',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'at DESC',
      limit: limit,
    );
    return rows;
  }

  Future<void> reopenPayrollPeriod(String id, {required String reason}) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Причина переоткрытия обязательна.');
    }
    final period = _payrollPeriods.firstWhere((p) => p.id == id);
    if (!period.isClosed) return;
    final now = DateTime.now();
    final updated = PayrollPeriod(
      id: period.id,
      name: period.name,
      startAt: period.startAt,
      endAt: period.endAt,
      note: period.note,
      closedAt: null,
      createdAt: period.createdAt,
      updatedAt: now,
    );
    await _appDatabase.database.transaction((txn) async {
      await _payrollRepo.save(updated, txn: txn);
      await _appDatabase.audit(
        action: 'payroll_period.reopen',
        entity: 'payroll_period',
        entityId: id,
        after: {'reason': trimmed, 'closedAt': period.closedAt?.millisecondsSinceEpoch},
        txn: txn,
      );
    });
    final idx = _payrollPeriods.indexWhere((p) => p.id == id);
    if (idx != -1) _payrollPeriods[idx] = updated;
    notifyListeners();
  }

  /// Закрытие периода: ведомости фиксируются одной транзакцией.
  /// Повторное закрытие возвращает уже сохранённый результат (идемпотентность).
  Future<List<Payslip>> closePayrollPeriod(String id, {DateTime? at}) async {
    final period = _payrollPeriods.firstWhere((p) => p.id == id);
    if (period.isClosed) {
      return await _payslipRepo.forPeriod(id);
    }
    final endExclusive = periodEndExclusive(period.endAt);
    final now = at ?? DateTime.now();
    final updated = PayrollPeriod(
      id: period.id,
      name: period.name,
      startAt: period.startAt,
      endAt: period.endAt,
      note: period.note,
      closedAt: now,
      createdAt: period.createdAt,
      updatedAt: now,
    );
    final employees = _employees.where((e) => !e.archived).toList();
    final created = <Payslip>[];
    final oldSlips = await _payslipRepo.forPeriodIds(id);
    await _appDatabase.database.transaction((txn) async {
        // При повторном закрытии (после переоткрытия) старые строки начислений
        // мягко удаляем ДО вставки новых: они остаются в расшифровке v1,
        // но освобождают уникальный ключ (source_kind, source_id, accrual_kind,
        // employee_id). Список ведомостей снят до транзакции, поэтому новые
        // строки под удаление не попадают.
        if (oldSlips.isNotEmpty) {
          await _accrualEntryRepo.softDeleteBoundToPayslips(
            oldSlips.map((s) => s.id).toList(),
            now,
            txn: txn,
          );
        }
        for (final emp in employees) {
          final lines = buildAccrualLines(
            start: period.startAt,
            endExclusive: endExclusive,
            conditions: conditionsForEmployee(emp.id),
            timeEntries: _timeEntries
                .where((t) => t.employeeId == emp.id)
                .toList(),
            jobs: _jobs
                .where((j) => j.assigneeId == emp.id)
                .toList(),
            defaultPayType: emp.payType,
          );
          final totals = paymentTotalsForPeriod(emp.id, period.startAt, period.endAt);
          final earned = lines.fold<int>(0, (s, l) => s + l.amountCents);
          final net = earned +
              (totals['bonus'] ?? 0) -
              (totals['penalty'] ?? 0) -
              (totals['advance'] ?? 0) -
              (totals['payout'] ?? 0);
          final needsReview = lines.any((l) => l.needsReview);
          final version = (await _payslipRepo.maxVersionFor(period.id, emp.id, txn: txn)) + 1;
          final slip = Payslip(
            id: newId(),
            periodId: period.id,
            employeeId: emp.id,
            version: version,
            status: needsReview ? 'preliminary' : 'confirmed',
            needsReview: needsReview,
            minutes: lines.fold<int>(0, (s, l) => s + l.minutes),
            accruedCents: earned,
            bonusCents: totals['bonus'] ?? 0,
            penaltyCents: totals['penalty'] ?? 0,
            advanceCents: totals['advance'] ?? 0,
            payoutCents: totals['payout'] ?? 0,
            netCents: net,
            reviewNote: needsReview
                ? 'Строки с фолбэком ставки или без условия — проверьте.'
                : null,
            frozenAt: now,
            createdAt: now,
          );
          await _payslipRepo.save(slip, txn: txn);
          created.add(slip);
          for (final line in lines) {
            final entry = AccrualEntry(
              id: newId(),
              payslipId: slip.id,
              employeeId: emp.id,
              sourceKind: line.sourceKind,
              sourceId: line.sourceId,
              accrualKind: line.accrualKind,
              payConditionId: line.payConditionId,
              rateCents: line.rateCents,
              minutes: line.minutes,
              basisPriceCents: line.basisPriceCents,
              percent: line.percent,
              amountCents: line.amountCents,
              needsReview: line.needsReview,
              payType: line.payType,
              occurredAt: line.occurredAt,
              createdAt: now,
            );
            final inserted = await _accrualEntryRepo.insertIgnore(entry, txn: txn);
            if (!inserted) {
              throw StateError('insertIgnore failed for ${entry.sourceKind}:${entry.sourceId}');
            }
          }
        }
        await _payrollRepo.save(updated, txn: txn);
        await _appDatabase.audit(
          action: 'payroll_period.close',
          entity: 'payroll_period',
          entityId: id,
          before: period.toMap(),
          after: updated.toMap(),
          txn: txn,
        );
      });
      final idx = _payrollPeriods.indexWhere((p) => p.id == id);
      if (idx != -1) _payrollPeriods[idx] = updated;
      _payslips = [..._payslips, ...created];
      _accrualEntries = await _accrualEntryRepo.getAllIncludingDeleted();
      notifyListeners();
      return created;
    }

  Future<void> deletePayrollPeriod(String id) async {
    await _payrollRepo.delete(id);
    _payrollPeriods = _payrollPeriods.where((p) => p.id != id).toList();
    await auditAction(
      action: 'payroll_period.delete',
      entity: 'payroll_period',
      entityId: id,
    );
    notifyListeners();
  }

  int earnedCentsForPeriod(String employeeId, DateTime start, DateTime end) {
    final emp = employeeById(employeeId);
    if (emp == null) return 0;
    int earned = 0;
    if (emp.payType == 'hourly' ||
        emp.payType == 'mixed' ||
        emp.payType == 'salary') {
      final mins = _timeEntries
          .where(
            (t) =>
                t.employeeId == employeeId &&
                !t.startedAt.isBefore(start) &&
                !t.startedAt.isAfter(end),
          )
          .fold(
            0,
            (s, t) =>
                s +
                (t.minutes > 0
                    ? t.minutes
                    : _durationMinutes(t.startedAt, t.endedAt)),
          );
      earned += (mins * emp.rateCents / 60).round();
    }
    if (emp.payType == 'piece' || emp.payType == 'mixed') {
      final doneJobs = _jobs.where(
        (j) =>
            j.assigneeId == employeeId &&
            (j.status == JobStatus.done || j.status == JobStatus.closed) &&
            !j.archived &&
            (j.finishedAt ?? j.updatedAt).isAfter(
              start.subtract(const Duration(seconds: 1)),
            ) &&
            !(j.finishedAt ?? j.updatedAt).isAfter(end),
      );
      if (emp.payType == 'piece') earned += doneJobs.length * emp.rateCents;
    }
    if (emp.payType == 'percent' || emp.payType == 'mixed') {
      final doneJobs = _jobs.where(
        (j) =>
            j.assigneeId == employeeId &&
            (j.status == JobStatus.done || j.status == JobStatus.closed) &&
            !j.archived &&
            (j.finishedAt ?? j.updatedAt).isAfter(
              start.subtract(const Duration(seconds: 1)),
            ) &&
            !(j.finishedAt ?? j.updatedAt).isAfter(end),
      );
      final price = doneJobs.fold(0, (s, j) => s + j.priceCents);
      earned += (price * emp.percent / 100).round();
    }
    return earned;
  }

  int _durationMinutes(DateTime start, DateTime? end) {
    if (end == null) return 0;
    return end.difference(start).inMinutes;
  }

  Map<String, int> paymentTotalsForPeriod(
    String employeeId,
    DateTime start,
    DateTime end,
  ) {
    int bonuses = 0;
    int penalties = 0;
    int advances = 0;
    int payouts = 0;
    for (final p in paymentsForEmployee(employeeId)) {
      if (p.createdAt.isBefore(start) || p.createdAt.isAfter(end)) continue;
      if (p.type == 'bonus') bonuses += p.amountCents;
      if (p.type == 'penalty') penalties += p.amountCents;
      if (p.type == 'advance') advances += p.amountCents;
      if (p.type == 'payout') payouts += p.amountCents;
    }
    return {
      'bonus': bonuses,
      'penalty': penalties,
      'advance': advances,
      'payout': payouts,
    };
  }

  List<Map<String, Object?>> payrollSummary(DateTime start, DateTime end) {
    return _payrollSummaryLive(start, end);
  }

  List<Supplier> get suppliers => List.unmodifiable(_suppliers);

  Supplier? supplierById(String? id) {
    if (id == null) return null;
    for (final s in _suppliers) {
      if (s.id == id) return s;
    }
    return null;
  }

  String supplierName(String? id) => supplierById(id)?.name ?? 'Поставщик';

  Future<Supplier> createSupplier({
    required String name,
    String phone = '',
    String? note,
  }) async {
    final now = DateTime.now();
    final supplier = Supplier(
      id: newId(),
      name: name.trim(),
      phone: phone.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _supplierRepo.save(supplier);
    _suppliers = [supplier, ..._suppliers];
    await auditAction(
      action: 'supplier.create',
      entity: 'supplier',
      entityId: supplier.id,
      after: supplier.toMap(),
    );
    notifyListeners();
    return supplier;
  }

  Future<void> deleteSupplier(String id) async {
    await _supplierRepo.delete(id);
    _suppliers = _suppliers.where((s) => s.id != id).toList();
    await auditAction(
      action: 'supplier.delete',
      entity: 'supplier',
      entityId: id,
    );
    notifyListeners();
  }

  Future<Purchase> createPurchase({
    String? supplierId,
    String? accountId,
    int paidCents = 0,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    final now = DateTime.now();
    final purchaseId = newId();
    int total = 0;
    final purchaseLines = <PurchaseLine>[];
    for (final line in lines) {
      final itemId = line['itemId'] as String?;
      final qty = (line['qty'] as num?)?.toDouble() ?? 0;
      final price = line['unitPriceCents'] as int? ?? 0;
      if (itemId == null || qty <= 0) continue;
      total += (qty * price).round();
      final pl = PurchaseLine(
        id: newId(),
        purchaseId: purchaseId,
        itemId: itemId,
        qty: qty,
        unitPriceCents: price,
      );
      purchaseLines.add(pl);
      // Под `module_locations` склад не трогаем: приход рождает приёмка
      // (§5.6), иначе недопоставка «пришла» бы на склад в полном объёме.
      if (!settings.locationsEnabled) {
        // add stock without changing item cost for existing prices
        await adjustStock(
          itemId: itemId,
          delta: qty,
          type: 'in',
          note: note?.trim().isEmpty == true ? 'Закупка' : note?.trim(),
          refType: 'purchase',
          refId: purchaseId,
          unitCostCents: price,
        );
      }
    }

    if (purchaseLines.isEmpty) {
      throw ArgumentError('Закупка не содержит строк.');
    }
    if (total <= 0) throw ArgumentError('Сумма закупки должна быть больше 0.');
    final purchase = Purchase(
      id: purchaseId,
      supplierId: supplierId,
      accountId: accountId,
      totalCents: total,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _purchaseRepo.save(purchase);
    for (final line in purchaseLines) {
      await _purchaseRepo.saveLine(line);
    }
    _purchases = [purchase, ..._purchases];
    _purchaseLines = [...purchaseLines, ..._purchaseLines];

    if (accountId != null && paidCents > 0) {
      await addTransaction(
        accountId: accountId,
        kind: 'purchase_payment',
        direction: 'out',
        amountCents: paidCents,
        category: 'Закупка у поставщика',
        note: purchase.note,
        relatedTransactionId: purchase.id,
      );
    }

    await auditAction(
      action: 'purchase.create',
      entity: 'purchase',
      entityId: purchase.id,
      after: purchase.toMap(),
    );
    notifyListeners();
    return purchase;
  }

  int supplierDebtCents(String? supplierId) {
    int total = 0;
    for (final p in _purchases) {
      if (supplierId != null && p.supplierId != supplierId) continue;
      total += p.totalCents;
    }
    int paid = 0;
    for (final transaction in _moneyTransactions) {
      if (transaction.voided || transaction.kind != 'purchase_payment') {
        continue;
      }
      if (supplierId != null) {
        final purchase = _purchases.firstWhere(
          (p) => p.id == transaction.relatedTransactionId,
          orElse: () => Purchase(
            id: '',
            supplierId: null,
            totalCents: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (purchase.supplierId != supplierId) continue;
      }
      paid += transaction.amountCents;
    }
    final debt = total - paid;
    return debt < 0 ? 0 : debt;
  }

  List<Purchase> purchasesForSupplier(String supplierId) =>
      _purchases.where((p) => p.supplierId == supplierId).toList();

  List<PurchaseLine> linesForPurchase(String purchaseId) =>
      _purchaseLines.where((l) => l.purchaseId == purchaseId).toList();

  Future<void> paySupplier({
    required String supplierId,
    required int amountCents,
    required String accountId,
    String? purchaseId,
    String? note,
  }) async {
    if (amountCents <= 0) return;
    await addTransaction(
      accountId: accountId,
      kind: 'purchase_payment',
      direction: 'out',
      amountCents: amountCents,
      category: 'Оплата поставщику',
      note: note,
      relatedTransactionId: purchaseId,
    );
    await auditAction(
      action: 'supplier_pay',
      entity: 'supplier',
      entityId: supplierId,
      after: {'amountCents': amountCents},
    );
    notifyListeners();
  }

  List<Map<String, Object?>> supplierSummary() {
    return _suppliers.map((supplier) {
      final purchases = purchasesForSupplier(supplier.id);
      return <String, Object?>{
        'supplier': supplier,
        'purchases': purchases,
        'debtCents': supplierDebtCents(supplier.id),
        'purchaseCount': purchases.length,
      };
    }).toList();
  }

  Future<List<JobAttachment>> attachmentsForJob(String jobId) async {
    final rows = await _appDatabase.database.query(
      'job_attachments',
      where: 'job_id = ? AND deleted_at IS NULL',
      whereArgs: [jobId],
      orderBy: 'created_at DESC',
    );
    return rows.map(JobAttachment.fromMap).toList();
  }

  Future<JobAttachment> addJobAttachment({
    required String jobId,
    required String sourcePath,
  }) async {
    ensurePeriodOpen();
    final source = File(sourcePath);
    final dir = await getApplicationDocumentsDirectory();
    final attachDir = Directory('${dir.path}/job_attachments');
    await attachDir.create(recursive: true);
    final base = source.uri.pathSegments.isEmpty
        ? 'file'
        : source.uri.pathSegments.last;
    final name = base.isEmpty ? 'attachment' : base;
    final unique = '${newId()}_$name';
    final dest = File('${attachDir.path}/$unique');
    await source.copy(dest.path);
    final now = DateTime.now();
    final attachment = JobAttachment(
      id: newId(),
      jobId: jobId,
      fileName: name,
      filePath: dest.path,
      createdAt: now,
    );
    await _appDatabase.database.insert(
      'job_attachments',
      attachment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await auditAction(
      action: 'job_attachment.create',
      entity: 'job_attachment',
      entityId: attachment.id,
      after: attachment.toMap(),
    );
    notifyListeners();
    return attachment;
  }

  Future<void> deleteJobAttachment(String id) async {
    ensurePeriodOpen();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _appDatabase.database.update(
      'job_attachments',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditAction(
      action: 'job_attachment.delete',
      entity: 'job_attachment',
      entityId: id,
    );
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────── Заявки и КП (Э3)

  /// Все заявки (включая отказ и конвертированные).
  List<Lead> get leads => List.unmodifiable(_leads);

  Lead? leadById(String id) {
    for (final l in _leads) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<Lead> leadsByStatus(String status) =>
      _leads.where((l) => l.status == status).toList();

  /// «Зависшие»: активные с наступившим следующим шагом, самые просроченные
  /// сверху (§Э3.1). Без запланированного шага заявка сюда не попадает.
  List<Lead> staleLeads({DateTime? now}) {
    final moment = now ?? DateTime.now();
    return _leads.where((l) => l.isStaleAt(moment)).toList()
      ..sort((a, b) => a.nextStepAt!.compareTo(b.nextStepAt!));
  }

  int get staleLeadsCount => staleLeads().length;

  Future<Lead> createLead({
    required String name,
    String phone = '',
    String? clientId,
    String source = 'other',
    String? request,
    int budgetCents = 0,
    DateTime? nextStepAt,
    String? note,
  }) async {
    final now = DateTime.now();
    final trimmed = name.trim();
    final lead = Lead(
      id: newId(),
      // Имя обязательно по схеме; если мастер заполнил только телефон,
      // заявка всё равно заводится и зовётся по номеру.
      name: trimmed.isEmpty ? phone.trim() : trimmed,
      phone: phone.trim(),
      clientId: clientId,
      source: source,
      request: _nullIfBlank(request),
      budgetCents: budgetCents,
      nextStepAt: nextStepAt,
      note: _nullIfBlank(note),
      createdAt: now,
      updatedAt: now,
    );
    await _leadRepo.save(lead);
    _leads = [lead, ..._leads];
    notifyListeners();
    return lead;
  }

  Future<void> updateLead(Lead lead) async {
    final updated = lead.copyWith(updatedAt: DateTime.now());
    await _leadRepo.save(updated);
    final index = _leads.indexWhere((l) => l.id == updated.id);
    if (index == -1) {
      _leads = [updated, ..._leads];
    } else {
      _leads[index] = updated;
    }
    notifyListeners();
  }

  /// Отказ по заявке: статус + причина, чтобы воронка показывала причины,
  /// а список — не мозолил глаза.
  Future<void> closeLead(String leadId, {required String reason}) async {
    final lead = leadById(leadId);
    if (lead == null || !lead.isActive) return;
    await updateLead(
      lead.copyWith(status: 'refused', closeReason: _nullIfBlank(reason)),
    );
  }

  /// Конверсия заявки в заказ (DoD §5.4): переносит клиента, сумму и срок.
  ///
  /// Если заявка не была связана с клиентом, заводим нового — иначе мастеру
  /// пришлось бы сначала идти в «Клиентов» и терять смысл одного действия.
  Future<Job> convertLeadToJob(
    String leadId, {
    required String title,
    int priceCents = 0,
    DateTime? dueAt,
  }) async {
    ensurePeriodOpen();
    final result = await _appDatabase.database.transaction((txn) async {
      final rows = await txn.query('leads', where: 'id = ? AND deleted_at IS NULL', whereArgs: [leadId]);
      if (rows.isEmpty) throw ArgumentError('Заявка $leadId не найдена');
      final lead = Lead.fromMap(rows.single);
      if (lead.convertedJobId != null) {
        final existing = await txn.query('jobs', where: 'id = ? AND deleted_at IS NULL', whereArgs: [lead.convertedJobId]);
        if (existing.isEmpty) throw StateError('Связанный заказ недоступен.');
        return (job: Job.fromMap(existing.single), client: null as Client?, lead: lead, obligation: null as Obligation?);
      }
      var clientId = lead.clientId;
      final clients = clientId == null ? [] : await txn.query('clients', columns: ['id'], where: 'id = ? AND deleted_at IS NULL', whereArgs: [clientId]);
      Client? client;
      final now = DateTime.now();
      if (clients.isEmpty) {
        client = Client(id: newId(), name: lead.name.trim(), phone: lead.phone.trim(), createdAt: now, updatedAt: now);
        clientId = client.id;
        await txn.insert('clients', client.toMap());
      }
      final job = Job(id: newId(), clientId: clientId!, title: title.trim().isEmpty ? (lead.request ?? lead.name) : title.trim(), priceCents: priceCents > 0 ? priceCents : lead.budgetCents, dueDate: dueAt, note: lead.request, leadId: lead.id, createdAt: now, updatedAt: now);
      await txn.insert('jobs', job.toMap());
      Obligation? obligation;
      if (job.priceCents > 0) {
        obligation = Obligation(id: newId(), direction: 'receivable', kind: 'client_payment', counterpartyType: 'client', counterpartyId: clientId, jobId: job.id, title: 'Оплата заказа: ${job.title}', amountCents: job.priceCents, dueAt: dueAt ?? now, createdAt: now, updatedAt: now);
        await txn.insert('obligations', obligation.toMap());
      }
      final updatedLead = lead.copyWith(status: 'converted', clientId: clientId, convertedJobId: job.id, updatedAt: now);
      await txn.update('leads', updatedLead.toMap(), where: 'id = ?', whereArgs: [leadId]);
      return (job: job, client: client, lead: updatedLead, obligation: obligation);
    });
    if (result.client != null && clientById(result.client!.id) == null) _clients = [result.client!, ..._clients];
    if (jobById(result.job.id) == null) _jobs = [result.job, ..._jobs];
    _leads = [for (final lead in _leads) if (lead.id == leadId) result.lead else lead];
    if (result.obligation != null) _obligations = [result.obligation!, ..._obligations];
    notifyListeners();
    return result.job;
  }

  /// Воронка: сколько заявок на каждом этапе и по каким источникам (§5.9).
  ({
    int total,
    int active,
    int stale,
    int converted,
    int refused,
    Map<String, int> bySource,
  })
  leadsFunnel() {
    final moment = DateTime.now();
    final bySource = <String, int>{};
    var stale = 0;
    for (final l in _leads) {
      bySource[l.source] = (bySource[l.source] ?? 0) + 1;
      if (l.isStaleAt(moment)) stale++;
    }
    int count(String status) => _leads.where((l) => l.status == status).length;
    return (
      total: _leads.length,
      active: count('active'),
      stale: stale,
      converted: count('converted'),
      refused: count('refused'),
      bySource: bySource,
    );
  }

  /// Доля конверсий, 0..1; пусто — 0, а не NaN.
  double get leadsConversionRate {
    final closed = _leads
        .where((l) => l.status == 'converted' || l.status == 'refused')
        .length;
    if (closed == 0) return 0;
    return _leads.where((l) => l.status == 'converted').length / closed;
  }

  Future<void> deleteLead(String leadId) async {
    await _leadRepo.softDelete(leadId);
    _leads = _leads.where((l) => l.id != leadId).toList();
    notifyListeners();
  }

  // --- КП: снимки (§12.4) ---

  List<Quote> get quotes => List.unmodifiable(_quotes);

  /// История КП заказа: новые ревизии сверху.
  List<Quote> quotesForJob(String jobId) =>
      _quotes.where((q) => q.jobId == jobId).toList()
        ..sort((a, b) => b.revision.compareTo(a.revision));

  List<Quote> quotesForLead(String leadId) =>
      _quotes.where((q) => q.leadId == leadId).toList()
        ..sort((a, b) => b.revision.compareTo(a.revision));

  Quote? quoteById(String id) {
    for (final q in _quotes) {
      if (q.id == id) return q;
    }
    return null;
  }

  /// Номер следующего КП: `КП-ГГГГ-NNN`, счётчик — по количеству снимков
  /// в этом году. Ревизия считается отдельно внутри номера.
  Future<({String number, int revision})> nextQuoteSlot({
    String? reuseNumber,
  }) async {
    final year = DateTime.now().year;
    if (reuseNumber != null) {
      return (
        number: reuseNumber,
        revision: await _quoteRepo.maxRevision(reuseNumber) + 1,
      );
    }
    final serial =
        _quotes
            .where(
              (q) => q.createdAt.year == year && q.number.startsWith('КП-$year'),
            )
            .map((q) => q.number)
            .toSet()
            .length +
        1;
    return (
      number: 'КП-$year-${serial.toString().padLeft(3, '0')}',
      revision: 1,
    );
  }

  /// Создаёт снимок КП по заказу: строки и итог фиксируются, дальнейшая
  /// правка заказа на этот PDF не влияет (§12.4).
  Future<Quote> saveQuoteSnapshot(
    String jobId, {
    String? leadId,
    String? reuseNumber,
    int validDays = 14,
  }) async {
    final job =
        jobById(jobId) ?? (throw ArgumentError('Заказ $jobId не найден'));
    final slot = await nextQuoteSlot(reuseNumber: reuseNumber);
    final lines = jobLines(jobId);
    final client = clientById(job.clientId);
    final now = DateTime.now();
    final totalCents = lines.isNotEmpty
        ? lines.fold<int>(0, (sum, l) => sum + l.totalCents)
        : job.priceCents;
    final snapshot = jsonEncode({
      'number': slot.number,
      'revision': slot.revision,
      'createdAt': now.millisecondsSinceEpoch,
      'clientName': client?.name ?? '',
      'clientPhone': client?.phone ?? '',
      'jobTitle': job.title,
      'validUntil': now.add(Duration(days: validDays)).millisecondsSinceEpoch,
      'totalCents': totalCents,
      'lines': [
        for (final l in lines)
          {
            'name': l.name,
            'quantity': l.quantity,
            'unit': l.unit,
            'priceCents': l.priceCents,
            'totalCents': l.totalCents,
          },
      ],
    });
    final quote = Quote(
      id: newId(),
      jobId: jobId,
      leadId: leadId ?? job.leadId,
      number: slot.number,
      revision: slot.revision,
      totalCents: totalCents,
      snapshotJson: snapshot,
      validUntil: now.add(Duration(days: validDays)),
      createdAt: now,
      updatedAt: now,
    );
    await _quoteRepo.save(quote);
    _quotes = [quote, ..._quotes];
    notifyListeners();
    return quote;
  }

  /// Путь к сохранённому PDF (UI складывает файл сам, store помнит, где он).
  Future<void> setQuotePdfPath(String quoteId, String path) async {
    final quote = quoteById(quoteId);
    if (quote == null) return;
    final updated = quote.copyWith(
      pdfPath: path,
      updatedAt: DateTime.now(),
    );
    await _quoteRepo.save(updated);
    final index = _quotes.indexWhere((q) => q.id == quoteId);
    if (index != -1) _quotes[index] = updated;
    notifyListeners();
  }

  Future<void> markQuoteSent(String quoteId) async {
    final quote = quoteById(quoteId);
    if (quote == null) return;
    final now = DateTime.now();
    final updated = quote.copyWith(
      sentAt: now,
      status: 'sent',
      updatedAt: now,
    );
    await _quoteRepo.save(updated);
    final index = _quotes.indexWhere((q) => q.id == quoteId);
    if (index != -1) _quotes[index] = updated;
    notifyListeners();
  }

  Future<void> setQuoteStatus(String quoteId, String status) async {
    final quote = quoteById(quoteId);
    if (quote == null) return;
    final updated = quote.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    await _quoteRepo.save(updated);
    final index = _quotes.indexWhere((q) => q.id == quoteId);
    if (index != -1) _quotes[index] = updated;
    notifyListeners();
  }

  /// Удаляет КП (soft-delete: снимок — доказательство согласованной цены,
  /// поэтому строка остаётся в базе и может быть восстановлена копией).
  Future<void> deleteQuote(String quoteId) async {
    ensurePeriodOpen();
    await _quoteRepo.softDelete(quoteId);
    _quotes = _quotes.where((q) => q.id != quoteId).toList();
    notifyListeners();
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  // --- Клиентские кредиты (депозиты, абонементы, сертификаты) (§5.5, Э4) ---

  List<ClientCredit> get credits => List.unmodifiable(_credits);

  List<ClientCredit> clientCredits(String clientId) =>
      _credits.where((c) => c.clientId == clientId && c.deletedAt == null).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  ClientCredit? clientCreditById(String id) =>
      _credits.where((c) => c.id == id && c.deletedAt == null).cast<ClientCredit?>().firstOrNull;

  /// История движений по кредитам из `audit_log` (§12.1: списания живут только здесь).
  List<CreditChange> get creditChanges => List.unmodifiable(_creditChanges);

  /// Движения конкретного кредита, от новых к старым.
  List<CreditChange> creditHistory(String creditId) =>
      _creditChanges.where((c) => c.entityId == creditId).toList();

  /// Активные обязательства перед клиентами: ещё не отработанные деньги (§12.1).
  int get clientCreditTotalCents => _credits
      .where((c) => c.deletedAt == null && c.isActive)
      .fold(0, (sum, c) => sum + c.remainingCents);

  Future<void> deleteClientCredit(String creditId) async {
    ensurePeriodOpen();
    await _creditRepo.softDelete(creditId);
    _credits = _credits.where((c) => c.id != creditId).toList();
    try {
      await _appDatabase.audit(
        action: 'credit.delete',
        entity: 'client_credit',
        entityId: creditId,
      );
    } catch (_) {}
    notifyListeners();
  }

  /// Топ позиционных имён клиента по частоте (§6.8): считает заказы, в которых
  /// позиция встречалась, а не строки — повтор в одном заказе не накручивает рейтинг.
  List<String> favoritePositions(String clientId, {int limit = 3}) {
    final clientJobIds = _jobs
        .where((j) => j.clientId == clientId && !j.archived)
        .map((j) => j.id)
        .toSet();
    if (clientJobIds.isEmpty) return const [];
    final catalogNames = {
      for (final item in _inventoryItems) item.id: item.name,
    };
    final jobsByPosition = <String, Set<String>>{};
    for (final line in _materials) {
      if (!clientJobIds.contains(line.jobId)) continue;
      final name = line.itemId == null
          ? line.name.trim()
          : (catalogNames[line.itemId] ?? line.name).trim();
      if (name.isEmpty) continue;
      (jobsByPosition[name] ??= <String>{}).add(line.jobId);
    }
    final ranked = jobsByPosition.entries.toList()
      ..sort((a, b) {
        final byJobs = b.value.length.compareTo(a.value.length);
        return byJobs != 0 ? byJobs : a.key.compareTo(b.key);
      });
    return ranked.take(limit).map((e) => e.key).toList();
  }

  /// Выручка, признанная списаниями кредитов за период `[from, to)`.
  int clientCreditRevenueCents(DateTime from, DateTime to) {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    return _creditChanges
        .where(
          (c) => c.action == 'credit.use' && c.at >= fromMs && c.at < toMs,
        )
        .fold(0, (sum, c) => sum + c.amountCents.abs());
  }

  /// Прирост обязательств перед клиентами за период `[from, to)`: Δ Σ `remaining_cents`.
  ///
  /// Возвраты (`credit.refund`) не входят: они уже учтены оттоком в
  /// `money_transactions`, иначе деньги вычлись бы дважды.
  int deferredDeltaCents(DateTime from, DateTime to) {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    return _creditChanges
        .where(
          (c) =>
              c.action != 'credit.refund' &&
              c.at >= fromMs &&
              c.at < toMs,
        )
        .fold(0, (sum, c) => sum + c.deltaCents);
  }

  /// Признанная выручка за период `[from, to)` (§12.1): поступления за вычетом
  /// возвратов по заказам и изменения отложенной выручки. Исключение верхней
  /// границы защищает от двойного учёта на стыке соседних периодов.
  int recognizedRevenueCents(DateTime from, DateTime to) {
    final netInflow = _moneyTransactions
        .where(
          (t) =>
              !t.voided &&
              (t.direction == 'in' || t.isOrderRefund) &&
              !t.createdAt.isBefore(from) &&
              t.createdAt.isBefore(to),
        )
        .fold(0, (sum, t) => sum + t.signedAmount);
    return netInflow - deferredDeltaCents(from, to);
  }

  /// Счёт для клиентских денег: первый неархивированный, иначе любой, иначе null.
  Account? get _creditAccount {
    if (_accounts.isEmpty) return null;
    return _accounts.where((a) => !a.archived).cast<Account?>().firstOrNull ?? _accounts.first;
  }

  Future<ClientCredit> createClientCredit({
    required String clientId,
    required String kind,
    required String title,
    required int amountCents,
    int? unitsTotal,
    DateTime? expiresAt,
    String? note,
  }) async {
    ensurePeriodOpen();
    final credit = ClientCredit(
      id: newId(),
      clientId: clientId,
      kind: kind,
      title: title.trim(),
      amountCents: amountCents,
      remainingCents: amountCents,
      unitsTotal: unitsTotal,
      unitsLeft: unitsTotal,
      expiresAt: expiresAt,
      status: 'active',
      note: _nullIfBlank(note),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _creditRepo.save(credit);
    _credits = [credit, ..._credits];

    // Деньги пришли (ДДС растёт).
    final account = _creditAccount;
    if (account != null) {
      final tx = MoneyTransaction(
        id: newId(),
        accountId: account.id,
        kind: 'income',
        direction: 'in',
        amountCents: amountCents,
        category: switch (kind) { 'pass' => 'Абонемент', 'certificate' => 'Сертификат', _ => 'Депозит' },
        clientId: clientId,
        note: _nullIfBlank(note),
        createdAt: DateTime.now(),
      );
      await _moneyTxRepo.save(tx);
      _moneyTransactions = [tx, ..._moneyTransactions];
    }

    // Аудит — единственный источник списаний (§12.1).
    final change = CreditChange(
      action: 'credit.create',
      entityId: credit.id,
      before: null,
      after: credit.toMap(),
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _creditChanges = [change, ..._creditChanges];
    try {
      await _appDatabase.audit(
        action: 'credit.create',
        entity: 'client_credit',
        entityId: credit.id,
        after: credit.toMap(),
      );
    } catch (_) {}

    notifyListeners();
    return credit;
  }

  /// Списывает средства кредита (оплата заказа / записи).
  ///
  /// НЕ создаёт `money_transactions`: денег второй раз не приходило (§12.1).
  /// Единственный след — запись в `audit_log`. Возвращает фактически списанную
  /// сумму: 0, если кредита нет, он истёк или остаток пуст.
  Future<int> useClientCredit({
    required String creditId,
    required int amountCents,
    String? jobId,
    int? units,
    String? note,
  }) async {
    ensurePeriodOpen();
    final credit = clientCreditById(creditId);
    if (credit == null || !credit.isActive) return 0;
    final used = amountCents.clamp(0, credit.remainingCents);
    if (used <= 0) return 0;

    final remaining = credit.remainingCents - used;
    final updated = credit.copyWith(
      remainingCents: remaining,
      unitsLeft: credit.unitsLeft == null
          ? null
          : (credit.unitsLeft! - (units ?? 1)).clamp(0, credit.unitsLeft!),
      status: remaining == 0 ? 'used' : credit.status,
      updatedAt: DateTime.now(),
    );
    await _creditRepo.save(updated);
    final idx = _credits.indexWhere((c) => c.id == creditId);
    if (idx != -1) {
      _credits[idx] = updated;
    } else {
      _credits = [updated, ..._credits];
    }
    _creditChanges = [
      CreditChange(
        action: 'credit.use',
        entityId: creditId,
        before: credit.toMap(),
        after: updated.toMap(),
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ..._creditChanges,
    ];

    // Списанный кредит — это оплата заказа: гасим обязательство перед клиентом,
    // иначе «оплачено» и «долг» расходятся (§5.5).
    if (jobId != null) {
      await _applyJobPaymentToObligation(jobId, used);
    }

    try {
      await _appDatabase.audit(
        action: 'credit.use',
        entity: 'client_credit',
        entityId: creditId,
        before: credit.toMap(),
        after: updated.toMap(),
      );
    } catch (_) {}

    notifyListeners();
    return used;
  }

  /// Возврат денег клиенту (например, остаток депозита).
  ///
  /// Создаёт `money_transactions` (`kind='refund'`, `direction='out'`).
  /// Одновременно уменьшает `remaining_cents`.
  Future<void> refundClientCredit({
    required String creditId,
    required int amountCents,
    String? note,
  }) async {
    ensurePeriodOpen();
    final credit = clientCreditById(creditId);
    if (credit == null) return;
    final refund = amountCents.clamp(0, credit.remainingCents);
    if (refund <= 0) return;

    final remaining = credit.remainingCents - refund;
    final updated = credit.copyWith(
      remainingCents: remaining,
      status: remaining == 0 ? 'refunded' : credit.status,
      updatedAt: DateTime.now(),
    );
    await _creditRepo.save(updated);
    final idx = _credits.indexWhere((c) => c.id == creditId);
    if (idx != -1) {
      _credits[idx] = updated;
    } else {
      _credits = [updated, ..._credits];
    }

    // Денег стало меньше на руках — это реальный отток, поэтому транзакция есть.
    final account = _creditAccount;
    if (account != null) {
      final tx = MoneyTransaction(
        id: newId(),
        accountId: account.id,
        kind: 'refund',
        direction: 'out',
        amountCents: refund,
        category: 'Возврат',
        clientId: credit.clientId,
        note: _nullIfBlank(note) ?? credit.title,
        createdAt: DateTime.now(),
      );
      await _moneyTxRepo.save(tx);
      _moneyTransactions = [tx, ..._moneyTransactions];
    }

    _creditChanges = [
      CreditChange(
        action: 'credit.refund',
        entityId: creditId,
        before: credit.toMap(),
        after: updated.toMap(),
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ..._creditChanges,
    ];

    try {
      await _appDatabase.audit(
        action: 'credit.refund',
        entity: 'client_credit',
        entityId: creditId,
        before: credit.toMap(),
        after: updated.toMap(),
      );
    } catch (_) {}

    notifyListeners();
  }

  /// Отмечает истёкшие кредиты (§12.1).
  ///
  /// Деньги остаются на балансе: срок — это списание обязательства, а не отток.
  Future<int> expireCredits() async {
    final now = DateTime.now();
    var expired = 0;
    for (final credit in _credits.where((c) => c.deletedAt == null && c.isExpiredAt(now)).toList()) {
      final updated = credit.copyWith(
        status: 'expired',
        updatedAt: now,
      );
      await _creditRepo.save(updated);
      final idx = _credits.indexWhere((c) => c.id == credit.id);
      if (idx != -1) {
        _credits[idx] = updated;
      } else {
        _credits = [updated, ..._credits];
      }
      _creditChanges = [
        CreditChange(
          action: 'credit.expire',
          entityId: credit.id,
          before: credit.toMap(),
          after: updated.toMap(),
          at: now.millisecondsSinceEpoch,
        ),
        ..._creditChanges,
      ];
      expired++;
      try {
        await _appDatabase.audit(
          action: 'credit.expire',
          entity: 'client_credit',
          entityId: credit.id,
          before: credit.toMap(),
          after: updated.toMap(),
        );
      } catch (_) {}
    }
    if (expired > 0) notifyListeners();
    return expired;
  }

  Future<void> clearAll() async {
    try {
      await _appDatabase.audit(action: 'data.clearAll');
    } catch (_) {}
    await _appDatabase.database.transaction((txn) async {
      // v24: `quotes` ссылается на заказы и заявки, `jobs` — на заявки,
      // поэтому снимки КП и заказы уходят раньше заявок.
      await txn.delete('quotes');
      await txn.delete('appointments');
      await txn.delete('booking_resources');
      await txn.delete('client_reminders');
      await txn.delete('employee_payments');
      await txn.delete('time_entries');
      await txn.delete('employees');
      await txn.delete('stock_movements');
      await txn.delete('inventory_items');
      await txn.delete('money_transactions');
      await txn.delete('cash_shifts');
      await txn.delete('accounts');
      await txn.delete('work_sessions');
      await txn.delete('materials');
      await txn.delete('job_stages');
      await txn.delete('jobs');
      await txn.delete('objects');
      await txn.delete('leads');
      await txn.delete('client_credits');
      await txn.delete('clients');
    });
    await load();
  }
}
