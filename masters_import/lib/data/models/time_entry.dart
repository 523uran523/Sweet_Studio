class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.employeeId,
    this.jobId,
    required this.startedAt,
    this.endedAt,
    this.minutes = 0,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String employeeId;
  final String? jobId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int minutes;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'job_id': jobId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'minutes': minutes,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TimeEntry.fromMap(Map<String, Object?> m) => TimeEntry(
        id: m['id'] as String,
        employeeId: m['employee_id'] as String,
        jobId: m['job_id'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int? ?? 0),
        endedAt: m['ended_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        minutes: m['minutes'] as int? ?? 0,
        note: m['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );

  static const Object _unset = Object();

  TimeEntry copyWith({
    Object? id = _unset,
    Object? employeeId = _unset,
    Object? jobId = _unset,
    Object? startedAt = _unset,
    Object? endedAt = _unset,
    Object? minutes = _unset,
    Object? note = _unset,
  }) {
    return TimeEntry(
      id: id == _unset ? this.id : id as String,
      employeeId: employeeId == _unset ? this.employeeId : employeeId as String,
      jobId:
          jobId == _unset
              ? this.jobId
              : (jobId == null ? null : jobId as String),
      startedAt: startedAt == _unset ? this.startedAt : startedAt as DateTime,
      endedAt:
          endedAt == _unset
              ? this.endedAt
              : (endedAt == null ? null : endedAt as DateTime),
      minutes: minutes == _unset ? this.minutes : minutes as int,
      note: note == _unset ? this.note : (note == null ? null : note as String),
      createdAt: createdAt,
    );
  }
}

class EmployeePayment {
  const EmployeePayment({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.amountCents,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String employeeId;
  final String type; // advance, bonus, penalty, payout
  final int amountCents;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'type': type,
        'amount_cents': amountCents,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory EmployeePayment.fromMap(Map<String, Object?> m) => EmployeePayment(
        id: m['id'] as String,
        employeeId: m['employee_id'] as String,
        type: m['type'] as String,
        amountCents: m['amount_cents'] as int? ?? 0,
        note: m['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );
}
