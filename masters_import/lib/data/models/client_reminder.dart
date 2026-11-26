enum ReminderStatus {
  pending,
  done,
  cancelled;

  static ReminderStatus fromDb(String? v) => switch (v) {
        'done' => ReminderStatus.done,
        'cancelled' => ReminderStatus.cancelled,
        _ => ReminderStatus.pending,
      };
}

extension ReminderStatusLabel on ReminderStatus {
  String get label => switch (this) {
        ReminderStatus.pending => 'Ожидает',
        ReminderStatus.done => 'Выполнено',
        ReminderStatus.cancelled => 'Отменено',
      };
  String get dbValue => switch (this) {
        ReminderStatus.pending => 'pending',
        ReminderStatus.done => 'done',
        ReminderStatus.cancelled => 'cancelled',
      };
  static ReminderStatus fromDb(String? v) => switch (v) {
        'done' => ReminderStatus.done,
        'cancelled' => ReminderStatus.cancelled,
        _ => ReminderStatus.pending,
      };
}

class ClientReminder {
  const ClientReminder({
    required this.id,
    required this.clientId,
    this.jobId,
    this.type = 'manual',
    required this.title,
    this.body,
    required this.dueAt,
    this.status = ReminderStatus.pending,
    required this.createdAt,
  });

  final String id;
  final String clientId;
  final String? jobId;
  final String type;
  final String title;
  final String? body;
  final DateTime dueAt;
  final ReminderStatus status;
  final DateTime createdAt;

  bool get isDue => dueAt.isBefore(DateTime.now()) && status == ReminderStatus.pending;

  ClientReminder copyWith({
    Object? id = _unset,
    Object? clientId = _unset,
    Object? jobId = _unset,
    Object? type = _unset,
    Object? title = _unset,
    Object? body = _unset,
    Object? dueAt = _unset,
    Object? status = _unset,
    Object? createdAt = _unset,
  }) {
    return ClientReminder(
      id: id == _unset ? this.id : id as String,
      clientId: clientId == _unset ? this.clientId : clientId as String,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
      type: type == _unset ? this.type : type as String,
      title: title == _unset ? this.title : title as String,
      body: body == _unset ? this.body : body as String?,
      dueAt: dueAt == _unset ? this.dueAt : dueAt as DateTime,
      status: status == _unset ? this.status : status as ReminderStatus,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'client_id': clientId,
        'job_id': jobId,
        'type': type,
        'title': title,
        'body': body,
        'due_at': dueAt.millisecondsSinceEpoch,
        'status': status.dbValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ClientReminder.fromMap(Map<String, Object?> m) => ClientReminder(
        id: m['id'] as String,
        clientId: m['client_id'] as String,
        jobId: m['job_id'] as String?,
        type: m['type'] as String? ?? 'manual',
        title: m['title'] as String,
        body: m['body'] as String?,
        dueAt: DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int? ?? 0),
        status: ReminderStatus.fromDb(m['status'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );

  static const Object _unset = Object();
}
