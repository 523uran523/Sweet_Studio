class JobStage {
  const JobStage({
    required this.id,
    required this.jobId,
    required this.title,
    this.done = false,
    this.sortOrder = 0,
    this.leadHours,
  });

  final String id;
  final String jobId;
  final String title;
  final bool done;
  final double sortOrder;

  /// Плановая длительность этапа в часах (v22, для «Плана производства» §6.9).
  final double? leadHours;

  JobStage copyWith({
    Object? id = _unset,
    Object? jobId = _unset,
    Object? title = _unset,
    Object? done = _unset,
    Object? sortOrder = _unset,
    Object? leadHours = _unset,
  }) {
    return JobStage(
      id: id == _unset ? this.id : id as String,
      jobId: jobId == _unset ? this.jobId : jobId as String,
      title: title == _unset ? this.title : title as String,
      done: done == _unset ? this.done : done as bool,
      sortOrder: sortOrder == _unset ? this.sortOrder : sortOrder as double,
      leadHours: leadHours == _unset
          ? this.leadHours
          : (leadHours as num?)?.toDouble(),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'job_id': jobId,
    'title': title,
    'done': done ? 1 : 0,
    'sort_order': sortOrder,
    'lead_hours': leadHours,
  };

  factory JobStage.fromMap(Map<String, Object?> m) => JobStage(
    id: m['id'] as String,
    jobId: m['job_id'] as String,
    title: m['title'] as String,
    done: (m['done'] as int? ?? 0) == 1,
    sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
    leadHours: (m['lead_hours'] as num?)?.toDouble(),
  );

  static const Object _unset = Object();
}

class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.jobId,
    required this.name,
    this.quantity = 1,
    this.unit = 'шт',
    this.priceCents = 0,
    this.itemId,
    this.kind = 'work',
    this.costAtOrderCents = 0,
    this.discountCents = 0,
    required this.createdAt,
  });

  final String id;
  final String jobId;
  final String name;
  final double quantity;
  final String unit;

  /// Цена продажи строки.
  final int priceCents;

  /// Позиция каталога, из которой пришла строка (`null` — введена вручную).
  final String? itemId;

  /// work / good.
  final String kind;

  /// Снимок себестоимости на момент оформления заказа.
  ///
  /// Хранится в строке, а не читается из каталога: правка цены товара не
  /// должна переписывать маржу уже закрытых заказов.
  final int costAtOrderCents;

  final int discountCents;

  final DateTime createdAt;

  int get totalCents => (priceCents * quantity).round();

  int get costTotalCents => (costAtOrderCents * quantity).round();

  int get marginCents => totalCents - discountCents - costTotalCents;

  MaterialItem copyWith({
    Object? id = _unset,
    Object? jobId = _unset,
    Object? name = _unset,
    Object? quantity = _unset,
    Object? unit = _unset,
    Object? priceCents = _unset,
    Object? itemId = _unset,
    Object? kind = _unset,
    Object? costAtOrderCents = _unset,
    Object? discountCents = _unset,
    Object? createdAt = _unset,
  }) {
    return MaterialItem(
      id: id == _unset ? this.id : id as String,
      jobId: jobId == _unset ? this.jobId : jobId as String,
      name: name == _unset ? this.name : name as String,
      quantity: quantity == _unset ? this.quantity : quantity as double,
      unit: unit == _unset ? this.unit : unit as String,
      priceCents: priceCents == _unset ? this.priceCents : priceCents as int,
      itemId: itemId == _unset ? this.itemId : itemId as String?,
      kind: kind == _unset ? this.kind : kind as String,
      costAtOrderCents: costAtOrderCents == _unset
          ? this.costAtOrderCents
          : costAtOrderCents as int,
      discountCents: discountCents == _unset
          ? this.discountCents
          : discountCents as int,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'job_id': jobId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'price_cents': priceCents,
    'item_id': itemId,
    'kind': kind,
    'cost_at_order_cents': costAtOrderCents,
    'discount_cents': discountCents,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory MaterialItem.fromMap(Map<String, Object?> m) => MaterialItem(
    id: m['id'] as String,
    jobId: m['job_id'] as String,
    name: m['name'] as String,
    quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
    unit: m['unit'] as String? ?? 'шт',
    priceCents: m['price_cents'] as int? ?? 0,
    itemId: m['item_id'] as String?,
    kind: m['kind'] as String? ?? 'work',
    costAtOrderCents: (m['cost_at_order_cents'] as num?)?.toInt() ?? 0,
    discountCents: (m['discount_cents'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
  );

  static const Object _unset = Object();
}

class WorkSession {
  const WorkSession({
    required this.id,
    required this.jobId,
    required this.startedAt,
    this.endedAt,
    this.minutes = 0,
    this.pausedSeconds = 0,
    this.note,
  });

  final int id;
  final String? jobId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int minutes;
  final int pausedSeconds;
  final String? note;

  WorkSession copyWith({
    Object? id = _unset,
    Object? jobId = _unset,
    Object? startedAt = _unset,
    Object? endedAt = _unset,
    Object? minutes = _unset,
    Object? pausedSeconds = _unset,
    Object? note = _unset,
  }) {
    return WorkSession(
      id: id == _unset ? this.id : id as int,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
      startedAt: startedAt == _unset ? this.startedAt : startedAt as DateTime,
      endedAt: endedAt == _unset ? this.endedAt : endedAt as DateTime?,
      minutes: minutes == _unset ? this.minutes : minutes as int,
      pausedSeconds: pausedSeconds == _unset
          ? this.pausedSeconds
          : pausedSeconds as int,
      note: note == _unset ? this.note : note as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'job_id': jobId,
    'started_at': startedAt.millisecondsSinceEpoch,
    'ended_at': endedAt?.millisecondsSinceEpoch,
    'minutes': minutes,
    'paused_seconds': pausedSeconds,
    'note': note,
  };

  factory WorkSession.fromMap(Map<String, Object?> m) => WorkSession(
    id: m['id'] as int? ?? 0,
    jobId: m['job_id'] as String?,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      m['started_at'] as int? ?? 0,
    ),
    endedAt: m['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
    minutes: m['minutes'] as int? ?? 0,
    pausedSeconds: (m['paused_seconds'] as num?)?.toInt() ?? 0,
    note: m['note'] as String?,
  );

  static const Object _unset = Object();
}
