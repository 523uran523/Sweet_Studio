enum JobStatus {
  nuevo,
  inProgress,
  waitingParts,
  done,
  closed;

  static JobStatus fromDb(String? value) => switch (value) {
    'in_progress' => JobStatus.inProgress,
    'waiting_parts' => JobStatus.waitingParts,
    'done' => JobStatus.done,
    'closed' => JobStatus.closed,
    _ => JobStatus.nuevo,
  };
}

extension JobStatusLabel on JobStatus {
  String get label => switch (this) {
    JobStatus.nuevo => 'Новый',
    JobStatus.inProgress => 'В работе',
    JobStatus.waitingParts => 'Ждёт детали',
    JobStatus.done => 'Готово',
    JobStatus.closed => 'Закрыто',
  };
  String get dbValue => switch (this) {
    JobStatus.nuevo => 'new',
    JobStatus.inProgress => 'in_progress',
    JobStatus.waitingParts => 'waiting_parts',
    JobStatus.done => 'done',
    JobStatus.closed => 'closed',
  };
  static JobStatus fromDb(String? value) => switch (value) {
    'in_progress' => JobStatus.inProgress,
    'waiting_parts' => JobStatus.waitingParts,
    'done' => JobStatus.done,
    'closed' => JobStatus.closed,
    _ => JobStatus.nuevo,
  };
}

enum JobPriority {
  low,
  medium,
  high;

  static JobPriority fromDb(String? value) => switch (value) {
    'low' => JobPriority.low,
    'high' => JobPriority.high,
    _ => JobPriority.medium,
  };
}

extension JobPriorityLabel on JobPriority {
  String get label => switch (this) {
    JobPriority.low => 'Низкий',
    JobPriority.medium => 'Средний',
    JobPriority.high => 'Высокий',
  };
  String get dbValue => switch (this) {
    JobPriority.low => 'low',
    JobPriority.medium => 'medium',
    JobPriority.high => 'high',
  };
  static JobPriority fromDb(String? value) => switch (value) {
    'low' => JobPriority.low,
    'high' => JobPriority.high,
    _ => JobPriority.medium,
  };
}

class Job {
  const Job({
    required this.id,
    required this.clientId,
    this.objectId,
    required this.title,
    this.status = JobStatus.nuevo,
    this.priority = JobPriority.medium,
    this.priceCents = 0,
    this.costCents = 0,
    this.dueDate,
    this.startedAt,
    this.finishedAt,
    this.note,
    this.archived = false,
    this.pinned = false,
    this.assigneeId,
    this.tags,
    this.leadId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String clientId;
  final String? objectId;
  final String title;
  final JobStatus status;
  final JobPriority priority;
  final int priceCents;
  final int costCents;
  final DateTime? dueDate;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? note;
  final bool archived;
  final bool pinned;
  final String? assigneeId;
  final String? tags;

  /// Заявка, из которой вырос заказ (Э3). Нужна, чтобы в карточке заказа
  /// видеть источник обращения и не считать конверсию вручную.
  final String? leadId;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get price => priceCents / 100.0;
  double get cost => costCents / 100.0;
  int get marginCents => priceCents - costCents;

  Job copyWith({
    Object? id = _unset,
    Object? clientId = _unset,
    Object? objectId = _unset,
    Object? title = _unset,
    Object? status = _unset,
    Object? priority = _unset,
    Object? priceCents = _unset,
    Object? costCents = _unset,
    Object? dueDate = _unset,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
    Object? note = _unset,
    Object? archived = _unset,
    Object? pinned = _unset,
    Object? assigneeId = _unset,
    Object? tags = _unset,
    Object? leadId = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return Job(
      id: id == _unset ? this.id : id as String,
      clientId: clientId == _unset ? this.clientId : clientId as String,
      objectId: objectId == _unset ? this.objectId : objectId as String?,
      title: title == _unset ? this.title : title as String,
      status: status == _unset ? this.status : status as JobStatus,
      priority: priority == _unset ? this.priority : priority as JobPriority,
      priceCents: priceCents == _unset ? this.priceCents : priceCents as int,
      costCents: costCents == _unset ? this.costCents : costCents as int,
      dueDate: dueDate == _unset ? this.dueDate : dueDate as DateTime?,
      startedAt: startedAt == _unset ? this.startedAt : startedAt as DateTime?,
      finishedAt: finishedAt == _unset
          ? this.finishedAt
          : finishedAt as DateTime?,
      note: note == _unset ? this.note : note as String?,
      archived: archived == _unset ? this.archived : archived as bool,
      pinned: pinned == _unset ? this.pinned : pinned as bool,
      assigneeId: assigneeId == _unset
          ? this.assigneeId
          : assigneeId as String?,
      tags: tags == _unset ? this.tags : tags as String?,
      leadId: leadId == _unset ? this.leadId : leadId as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'client_id': clientId,
    'object_id': objectId,
    'title': title,
    'status': status.dbValue,
    'priority': priority.dbValue,
    'price_cents': priceCents,
    'cost_cents': costCents,
    'due_date': dueDate?.millisecondsSinceEpoch,
    'started_at': startedAt?.millisecondsSinceEpoch,
    'finished_at': finishedAt?.millisecondsSinceEpoch,
    'note': note,
    'archived': archived ? 1 : 0,
    'pinned': pinned ? 1 : 0,
    'assignee_id': assigneeId,
    // Колонка tags — NOT NULL DEFAULT '': UPDATE с NULL уронит ограничение,
    // поэтому пустые теги всегда пишутся пустой строкой.
    'tags': tags ?? '',
    'lead_id': leadId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Job.fromMap(Map<String, Object?> m) => Job(
    id: m['id'] as String,
    clientId: m['client_id'] as String,
    objectId: m['object_id'] as String?,
    title: m['title'] as String,
    status: JobStatus.fromDb(m['status'] as String?),
    priority: JobPriority.fromDb(m['priority'] as String?),
    priceCents: m['price_cents'] as int? ?? 0,
    costCents: m['cost_cents'] as int? ?? 0,
    dueDate: m['due_date'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
    startedAt: m['started_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
    finishedAt: m['finished_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['finished_at'] as int),
    note: m['note'] as String?,
    archived: (m['archived'] as int? ?? 0) == 1,
    pinned:
        (m['pinned'] == true) ||
        ((m['pinned'] is num) && (m['pinned'] as num) != 0),
    assigneeId: m['assignee_id'] as String?,
    tags: m['tags'] as String?,
    leadId: m['lead_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      m['updated_at'] as int? ?? 0,
    ),
  );

  static const Object _unset = Object();
}
