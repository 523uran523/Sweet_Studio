import 'appointment.dart';
import 'job.dart';

/// Тип события в едином экране планирования.
enum UnifiedEventKind { appointment, job }

/// Модель-адаптер, сводящая «записи» (appointments) и «заказы» (jobs)
/// в единый список для календаря/канбана. Данные остаются в родных
/// таблицах — здесь только маппинг в общее знаменательное представление.
class UnifiedEvent {
  const UnifiedEvent({
    required this.id,
    required this.kind,
    this.clientId,
    this.objectId,
    this.resourceId,
    required this.title,
    required this.startTime,
    this.endTime,
    required this.statusLabel,
    required this.kanbanKey,
    this.note,
    this.job,
    this.appointment,
  });

  final String id;
  final UnifiedEventKind kind;
  final String? clientId;
  final String? objectId;
  final String? resourceId;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final String statusLabel;

  /// Ключ kanban-колонки (см. `kanbanColumns` в job_constants.dart):
  /// `nuevo`, `in_progress`, `done`.
  final String kanbanKey;

  final String? note;

  /// Родной объект, если это заказ.
  final Job? job;

  /// Родной объект, если это запись.
  final Appointment? appointment;

  bool get isJob => kind == UnifiedEventKind.job;
  bool get isAppointment => kind == UnifiedEventKind.appointment;

  /// Сокрыть ли событие в активном календаре (история: закрытые заказы).
  bool get isClosed =>
      kind == UnifiedEventKind.job &&
      job != null &&
      job!.status == JobStatus.closed;

  factory UnifiedEvent.fromJob(Job j) {
    return UnifiedEvent(
      id: j.id,
      kind: UnifiedEventKind.job,
      clientId: j.clientId,
      objectId: j.objectId,
      title: j.title,
      startTime: j.dueDate ?? j.startedAt ?? j.createdAt,
      endTime: j.finishedAt,
      statusLabel: j.status.label,
      kanbanKey: jobKanbanKey(j.status),
      note: j.note,
      job: j,
    );
  }

  factory UnifiedEvent.fromAppointment(Appointment a) {
    return UnifiedEvent(
      id: a.id,
      kind: UnifiedEventKind.appointment,
      clientId: a.clientId,
      objectId: a.objectId,
      resourceId: a.resourceId,
      title: a.title,
      startTime: a.startAt,
      endTime: a.endAt,
      statusLabel: a.status.label,
      kanbanKey: appointmentKanbanKey(a.status),
      note: a.note,
      appointment: a,
    );
  }

  /// Статусы заказов → kanban-колонки. Совпадает с группировкой
  /// `kanbanColumns` (жирные колонки: nuevo / в работе / готово).
  static String jobKanbanKey(JobStatus status) => switch (status) {
    JobStatus.nuevo => 'nuevo',
    JobStatus.inProgress => 'in_progress',
    JobStatus.waitingParts => 'in_progress',
    JobStatus.done => 'done',
    JobStatus.closed => 'done',
  };

  /// Статусы записей → kanban-колонки: запланировано → «Новая»,
  /// подтверждено → «В работе», выполнено/отменено/не пришёл → «Готово».
  static String appointmentKanbanKey(AppointmentStatus status) =>
      switch (status) {
        AppointmentStatus.scheduled => 'nuevo',
        AppointmentStatus.confirmed => 'in_progress',
        AppointmentStatus.done => 'done',
        AppointmentStatus.cancelled => 'done',
        AppointmentStatus.noShow => 'done',
      };

  /// Состояние записи, в которое переводится канбан-колонка.
  static AppointmentStatus appointmentStatusForColumn(String columnKey) =>
      switch (columnKey) {
        'nuevo' => AppointmentStatus.scheduled,
        'in_progress' => AppointmentStatus.confirmed,
        _ => AppointmentStatus.done,
      };
}
