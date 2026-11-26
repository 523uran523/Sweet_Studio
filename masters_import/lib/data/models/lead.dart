/// Заявка: обращение, которое ещё не стало заказом (§5.4, Э3).
///
/// Смысл отдельной сущности в том, что у обращения есть следующий шаг и срок
/// на него. Пока заявка активна и срок наступил, она «зависла» — именно такие
/// теряют мастера, поэтому `isStale` вынесен в модель: и экран, и «Сегодня»
/// считают одинаково.
class Lead {
  Lead({
    required this.id,
    required this.name,
    this.phone = '',
    this.clientId,
    this.source = 'other',
    this.request,
    this.budgetCents = 0,
    this.status = 'active',
    this.nextStepAt,
    this.closeReason,
    this.convertedJobId,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;

  /// Имя contact-лица; после конверсии может быть заполнено из клиента.
  final String name;
  final String phone;

  /// Заполняется, когда заявка уже связана с заводским клиентом.
  final String? clientId;

  /// `whatsapp` / `avito` / `site` / `referral` / `other`.
  final String source;

  /// Своими словами, что просит клиент («торт на 15 кг, 20 ноября»).
  final String? request;
  final int budgetCents;

  /// `active` / `refused` / `converted`.
  final String status;

  /// Когда вернуться к клиенту. Пусто — шаг не запланирован, такая заявка
  /// в «Зависшие» не попадает: требовать напоминания не о чем.
  final DateTime? nextStepAt;

  /// Причина отказа (заполняется при `refused`).
  final String? closeReason;

  /// Заказ, выросший из заявки (заполняется при `converted`).
  final String? convertedJobId;

  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isActive => status == 'active';

  /// Просроченный следующий шаг → «Зависшие» (§Э3.1).
  bool isStaleAt(DateTime now) =>
      isActive && nextStepAt != null && nextStepAt!.isBefore(now);

  /// Сколько дней просрочен шаг; 0, если просрочки нет.
  int daysOverdue(DateTime now) {
    if (!isStaleAt(now)) return 0;
    return now.difference(nextStepAt!).inDays;
  }

  String get statusLabel => switch (status) {
    'refused' => 'Отказ',
    'converted' => 'Конвертирована',
    _ => isStaleAt(DateTime.now()) ? 'Зависла' : 'Активна',
  };

  String get sourceLabel => switch (source) {
    'whatsapp' => 'WhatsApp',
    'avito' => 'Авито',
    'site' => 'Сайт',
    'referral' => 'Сарафан',
    _ => 'Другое',
  };

  Lead copyWith({
    Object? name = _unset,
    Object? phone = _unset,
    Object? clientId = _unset,
    Object? source = _unset,
    Object? request = _unset,
    Object? budgetCents = _unset,
    Object? status = _unset,
    Object? nextStepAt = _unset,
    Object? closeReason = _unset,
    Object? convertedJobId = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return Lead(
      id: id,
      name: name == _unset ? this.name : name as String,
      phone: phone == _unset ? this.phone : phone as String,
      clientId: clientId == _unset ? this.clientId : clientId as String?,
      source: source == _unset ? this.source : source as String,
      request: request == _unset ? this.request : request as String?,
      budgetCents: budgetCents == _unset
          ? this.budgetCents
          : budgetCents as int,
      status: status == _unset ? this.status : status as String,
      nextStepAt: nextStepAt == _unset
          ? this.nextStepAt
          : nextStepAt as DateTime?,
      closeReason: closeReason == _unset
          ? this.closeReason
          : closeReason as String?,
      convertedJobId: convertedJobId == _unset
          ? this.convertedJobId
          : convertedJobId as String?,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'client_id': clientId,
    'source': source,
    'request': request,
    'budget_cents': budgetCents,
    'status': status,
    'next_step_at': nextStepAt?.millisecondsSinceEpoch,
    'close_reason': closeReason,
    'converted_job_id': convertedJobId,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory Lead.fromMap(Map<String, Object?> m) => Lead(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    clientId: m['client_id'] as String?,
    source: m['source'] as String? ?? 'other',
    request: m['request'] as String?,
    budgetCents: (m['budget_cents'] as num?)?.toInt() ?? 0,
    status: m['status'] as String? ?? 'active',
    nextStepAt: m['next_step_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['next_step_at'] as num).toInt()),
    closeReason: m['close_reason'] as String?,
    convertedJobId: m['converted_job_id'] as String?,
    note: m['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updated_at'] as num?)?.toInt() ??
          (m['created_at'] as num?)?.toInt() ??
          0,
    ),
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['deleted_at'] as num).toInt()),
    deviceId: m['device_id'] as String?,
  );

  static const Object _unset = Object();
}

/// Источник заявки и порядок чипов в UI (там же, где `kPaymentMethods`).
const List<String> kLeadSources = <String>[
  'whatsapp',
  'avito',
  'site',
  'referral',
  'other',
];

String leadSourceLabel(String source) => switch (source) {
  'whatsapp' => 'WhatsApp',
  'avito' => 'Авито',
  'site' => 'Сайт',
  'referral' => 'Сарафан',
  _ => 'Другое',
};
