enum AppointmentStatus {
  scheduled,
  confirmed,
  done,
  cancelled,
  noShow;

  static AppointmentStatus fromDb(String? value) => switch (value) {
        'confirmed' => AppointmentStatus.confirmed,
        'done' => AppointmentStatus.done,
        'cancelled' => AppointmentStatus.cancelled,
        'no_show' => AppointmentStatus.noShow,
        _ => AppointmentStatus.scheduled,
      };
}

extension AppointmentStatusLabel on AppointmentStatus {
  String get label => switch (this) {
        AppointmentStatus.scheduled => 'Запланировано',
        AppointmentStatus.confirmed => 'Подтверждено',
        AppointmentStatus.done => 'Выполнено',
        AppointmentStatus.cancelled => 'Отменено',
        AppointmentStatus.noShow => 'Не пришёл',
      };
  String get dbValue => switch (this) {
        AppointmentStatus.scheduled => 'scheduled',
        AppointmentStatus.confirmed => 'confirmed',
        AppointmentStatus.done => 'done',
        AppointmentStatus.cancelled => 'cancelled',
        AppointmentStatus.noShow => 'no_show',
      };
  static AppointmentStatus fromDb(String? value) => switch (value) {
        'confirmed' => AppointmentStatus.confirmed,
        'done' => AppointmentStatus.done,
        'cancelled' => AppointmentStatus.cancelled,
        'no_show' => AppointmentStatus.noShow,
        _ => AppointmentStatus.scheduled,
      };
}

class Appointment {
  const Appointment({
    required this.id,
    this.clientId,
    this.objectId,
    this.resourceId,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.status = AppointmentStatus.scheduled,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? clientId;
  final String? objectId;
  final String? resourceId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final AppointmentStatus status;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  Appointment copyWith({
    Object? id = _unset,
    Object? clientId = _unset,
    Object? objectId = _unset,
    Object? resourceId = _unset,
    Object? title = _unset,
    Object? startAt = _unset,
    Object? endAt = _unset,
    Object? status = _unset,
    Object? note = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return Appointment(
      id: id == _unset ? this.id : id as String,
      clientId: clientId == _unset ? this.clientId : clientId as String?,
      objectId: objectId == _unset ? this.objectId : objectId as String?,
      resourceId: resourceId == _unset ? this.resourceId : resourceId as String?,
      title: title == _unset ? this.title : title as String,
      startAt: startAt == _unset ? this.startAt : startAt as DateTime,
      endAt: endAt == _unset ? this.endAt : endAt as DateTime,
      status: status == _unset ? this.status : status as AppointmentStatus,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'client_id': clientId,
        'object_id': objectId,
        'resource_id': resourceId,
        'title': title,
        'start_at': startAt.millisecondsSinceEpoch,
        'end_at': endAt.millisecondsSinceEpoch,
        'status': status.dbValue,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Appointment.fromMap(Map<String, Object?> m) => Appointment(
        id: m['id'] as String,
        clientId: m['client_id'] as String?,
        objectId: m['object_id'] as String?,
        resourceId: m['resource_id'] as String?,
        title: m['title'] as String,
        startAt: DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int? ?? 0),
        endAt: DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int? ?? 0),
        status: AppointmentStatus.fromDb(m['status'] as String?),
        note: m['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? 0),
      );

  static const Object _unset = Object();
}
