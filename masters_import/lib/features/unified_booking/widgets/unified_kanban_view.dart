import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui.dart';
import '../../../data/models/appointment.dart';
import '../../../data/models/job.dart';
import '../../../data/models/unified_event.dart';
import '../../../state/masters_store.dart';
import '../../../state/settings_controller.dart';
import '../../booking/appointment_detail_screen.dart';
import '../../jobs/job_constants.dart';
import '../../jobs/job_detail_screen.dart';
import '../unified_booking_screen.dart';

/// Kanban единого экрана: колонки статусов заказов, в них — и заказы,
/// и записи (по маппингу статусов записей в kanban-колонки).
class UnifiedKanbanView extends StatelessWidget {
  const UnifiedKanbanView({super.key, required this.actions});

  final UnifiedBookingActions actions;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final settings = context.watch<SettingsController>();
    final colors = context.colors;

    final events = <UnifiedEvent>[
      for (final a in store.appointments) UnifiedEvent.fromAppointment(a),
      for (final j in store.jobs.where((j) => !j.archived))
        UnifiedEvent.fromJob(j),
    ];

    final groups = <_KanbanGroup>[
      for (final col in kanbanColumns.where(
        (c) => settings.kanbanColumnEnabled(c.key),
      ))
        _KanbanGroup(
          key: col.key,
          label: col.label,
          jobStatuses: col.statuses,
          events: events.where((e) => e.kanbanKey == col.key).toList()
            ..sort(_eventOrder),
        ),
    ];

    final size = MediaQuery.of(context).size;
    final isWide = size.width > size.height;

    Widget buildColumn(_KanbanGroup group, double? width) {
      return DragTarget<_KanbanEventDrag>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) async {
          try {
            await _drop(details.data, group, store);
          } on StateError catch (error) {
            if (context.mounted) {
              await showAppAlert(context, title: 'Проверьте запись', message: error.message);
            }
          }
        },
        builder: (context, candidateData, rejectedData) {
          final highlight = candidateData.isNotEmpty;
          final tint = _columnColor(colors, group.key);
          return Container(
            width: width,
            margin: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(9, 5, 7, 5),
                  decoration: BoxDecoration(
                    color: highlight ? colors.tint(tint, 0.18) : colors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: tint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Pill('${group.events.length}', color: tint),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: group.events.isEmpty
                      ? Center(
                          child: Text(
                            'Событий нет',
                            style: TextStyle(
                              color: colors.tertiaryLabel,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: group.events.length,
                          itemBuilder: (context, i) {
                            final event = group.events[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _UnifiedKanbanCard(
                                event: event,
                                store: store,
                                actions: actions,
                                onTapJob: () => Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        JobDetailScreen(jobId: event.id),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in groups)
              Expanded(child: buildColumn(group, null)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 72),
      children: [
        for (final group in groups) ...[
          SizedBox(height: 260, child: buildColumn(group, double.infinity)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Color _columnColor(AppColors colors, String key) {
    return switch (key) {
      'done' => colors.green,
      'in_progress' => colors.orange,
      _ => colors.accent,
    };
  }

  /// Порядок внутри колонки: записи раньше заказов, у записей — по
  /// времени начала, у заказов — закреплённые выше, потом по обновлению.
  int _eventOrder(UnifiedEvent a, UnifiedEvent b) {
    if (a.isAppointment && b.isAppointment) {
      return a.startTime.compareTo(b.startTime);
    }
    if (a.isAppointment != b.isAppointment) {
      return a.isAppointment ? -1 : 1;
    }
    final aj = a.job!;
    final bj = b.job!;
    if (aj.pinned != bj.pinned) return aj.pinned ? -1 : 1;
    return bj.updatedAt.compareTo(aj.updatedAt);
  }

  Future<void> _drop(
    _KanbanEventDrag drag,
    _KanbanGroup group,
    MastersStore store,
  ) async {
    if (drag.kind == UnifiedEventKind.job) {
      await store.setJobStatus(drag.id, group.jobStatuses.first);
    } else {
      await store.setAppointmentStatus(
        drag.id,
        UnifiedEvent.appointmentStatusForColumn(group.key),
      );
    }
  }
}

class _KanbanGroup {
  const _KanbanGroup({
    required this.key,
    required this.label,
    required this.jobStatuses,
    required this.events,
  });

  final String key;
  final String label;
  final List<JobStatus> jobStatuses;
  final List<UnifiedEvent> events;
}

class _KanbanEventDrag {
  const _KanbanEventDrag(this.kind, this.id);

  final UnifiedEventKind kind;
  final String id;
}

class _UnifiedKanbanCard extends StatelessWidget {
  const _UnifiedKanbanCard({
    required this.event,
    required this.store,
    required this.actions,
    required this.onTapJob,
  });

  final UnifiedEvent event;
  final MastersStore store;
  final UnifiedBookingActions actions;
  final VoidCallback onTapJob;

  String? _resourceName() {
    final id = event.resourceId;
    if (id == null) return null;
    for (final r in store.bookingResources) {
      if (r.id == id) return r.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final client = event.clientId == null
        ? null
        : store.clientById(event.clientId!);
    final isJob = event.isJob;

    final subLine = StringBuffer();
    if (isJob) {
      final j = event.job!;
      if (j.dueDate != null) {
        subLine
          ..write('Срок: ')
          ..write(DateFormat('d MMM HH:mm', 'ru').format(j.dueDate!));
      }
    } else {
      final a = event.appointment!;
      subLine
        ..write(DateFormat('HH:mm', 'ru').format(a.startAt))
        ..write('–')
        ..write(DateFormat('HH:mm', 'ru').format(a.endAt));
      final resource = _resourceName();
      if (resource != null) subLine.write(' • $resource');
    }
    if (client != null) subLine.write(' • ${client.name}');

    return LongPressDraggable<_KanbanEventDrag>(
      data: _KanbanEventDrag(event.kind, event.id),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 260,
          child: _cardBody(colors, subLine.toString()),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _cardBody(colors, subLine.toString()),
      ),
      child: GestureDetector(
        onTap: isJob
            ? onTapJob
            : () => _appointmentMenu(
                context,
                event,
                client?.name ?? 'Без клиента',
              ),
        child: _cardBody(colors, subLine.toString()),
      ),
    );
  }

  Widget _cardBody(AppColors colors, String subLine) {
    final color = event.isJob ? colors.orange : colors.accent;
    final isDone = event.kanbanKey == 'done';
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  // В колонке «Готово» название перечёркнуто.
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subLine,
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Pill(
                      event.isJob ? 'Заказ' : 'Запись',
                      color: color,
                      icon: event.isJob
                          ? CupertinoIcons.doc_text
                          : CupertinoIcons.calendar,
                    ),
                    Pill(event.statusLabel, color: colors.tertiaryLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _appointmentMenu(
    BuildContext context,
    UnifiedEvent event,
    String clientName,
  ) async {
    final a = event.appointment!;
    final resource = _resourceName() ?? '—';
    final choice = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: Text(event.title),
        message: Text(
          '${DateFormat('d MMM HH:mm', 'ru').format(a.startAt)} • $clientName • $resource • ${event.statusLabel}',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('open'),
            child: const Text('Открыть запись'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('done'),
            child: Text(
              a.status == AppointmentStatus.done
                  ? 'Вернуть в план'
                  : 'Отметить выполненной',
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('job'),
            child: const Text('Сделать заказом'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(dialogContext).pop('delete'),
          child: const Text('Удалить'),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'open':
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => AppointmentDetailScreen(appointmentId: a.id),
          ),
        );
      case 'done':
        try {
          await store.setAppointmentStatus(
            a.id,
            a.status == AppointmentStatus.done
                ? AppointmentStatus.scheduled
                : AppointmentStatus.done,
          );
        } on StateError catch (error) {
          if (context.mounted) {
            await showAppAlert(context, title: 'Проверьте запись', message: error.message);
          }
        }
      case 'job':
        actions.convertAppointmentToJob(a.id);
      case 'delete':
        final ok = await showAppConfirm(
          context,
          title: 'Удалить запись?',
          message: a.title,
          destructive: true,
          confirmLabel: 'Удалить',
        );
        if (ok && context.mounted) store.deleteAppointment(a.id);
    }
  }
}
