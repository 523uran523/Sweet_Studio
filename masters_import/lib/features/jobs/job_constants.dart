import '../../data/models/job.dart';

/// Описание одной kanban-колонки на экране «Заказы».
///
/// Канбан-вид группирует статусы заказов в колонки. Константы вынесены из
/// jobs_screen.dart, чтобы экран заказов и экран настроек использовали один
/// и тот же список колонок (ключ → заголовок → статусы).
class KanbanColumnDef {
  const KanbanColumnDef({
    required this.key,
    required this.label,
    required this.statuses,
  });

  /// Ключ колонки, хранящийся в настройках (префы `kanban_columns`).
  final String key;

  /// Заголовок колонки, показываемый пользователю.
  final String label;

  /// Статусы заказов, попадающие в эту колонку.
  final List<JobStatus> statuses;
}

/// Все kanban-колонки экрана «Заказы» в порядке отображения.
/// Источник истины для соответствия статус → колонка.
const List<KanbanColumnDef> kanbanColumns = <KanbanColumnDef>[
  KanbanColumnDef(
    key: 'nuevo',
    label: 'Новая',
    statuses: <JobStatus>[JobStatus.nuevo],
  ),
  KanbanColumnDef(
    key: 'in_progress',
    label: 'В работе',
    statuses: <JobStatus>[JobStatus.inProgress, JobStatus.waitingParts],
  ),
  KanbanColumnDef(
    key: 'done',
    label: 'Готово',
    statuses: <JobStatus>[JobStatus.done, JobStatus.closed],
  ),
];

/// Все статусы заказов для выпадающего выбора смены статуса.
/// Общий источник — статусы kanban-колонок выше, в порядке колонок.
final List<JobStatus> jobStatuses = kanbanColumns
    .expand((col) => col.statuses)
    .toList();
