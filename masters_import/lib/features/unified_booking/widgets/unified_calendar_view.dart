import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui.dart';
import '../../../core/utils/app_utils.dart';
import '../../../data/models/appointment.dart';
import '../../../data/models/job.dart';
import '../../../data/models/unified_event.dart';
import '../../../state/masters_store.dart';
import '../../jobs/job_detail_screen.dart';
import '../unified_booking_screen.dart';

/// Календарь единого экрана: сетка месяца с точками записей/заказов
/// и список событий дня. Закрытые заказы не показываются в списке дня.
class UnifiedCalendarView extends StatefulWidget {
  const UnifiedCalendarView({super.key, required this.actions});

  final UnifiedBookingActions actions;

  @override
  State<UnifiedCalendarView> createState() => _UnifiedCalendarViewState();
}

class _UnifiedCalendarViewState extends State<UnifiedCalendarView> {
  late DateTime _selectedDay = DateTime.now();
  late DateTime _calendarMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  DateTime get _monthStart =>
      DateTime(_calendarMonth.year, _calendarMonth.month, 1);

  void _shiftMonth(int delta) {
    setState(
      () => _calendarMonth = DateTime(
        _calendarMonth.year,
        _calendarMonth.month + delta,
        1,
      ),
    );
  }

  List<DateTime?> _cells() {
    final month = _monthStart;
    final firstWeekday = month.weekday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(month.year, month.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;

    // Активные события месяца (без закрытых заказов — они только история).
    final monthEvents = store
        .getEventsForRange(
          _monthStart,
          DateTime(_monthStart.year, _monthStart.month + 1, 1),
        )
        .where((e) => !e.isClosed)
        .toList();
    final apptDays = <int>{};
    final jobDays = <int>{};
    for (final e in monthEvents) {
      if (e.isAppointment) {
        apptDays.add(e.startTime.day);
      } else {
        jobDays.add(e.startTime.day);
      }
    }

    final dayStart = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final dayEvents = store
        .getEventsForRange(dayStart, dayStart.add(const Duration(days: 1)))
        .where((e) => !e.isClosed)
        .toList();

    final today = DateTime.now();
    final cells = _cells();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                onPressed: () => _shiftMonth(-1),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  size: 19,
                  semanticLabel: 'Предыдущий месяц',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _monthLabel(_monthStart),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 4),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                onPressed: () => _shiftMonth(1),
                child: const Icon(
                  CupertinoIcons.chevron_right,
                  size: 19,
                  semanticLabel: 'Следующий месяц',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
          child: Row(
            children: [
              for (var i = 0; i < kWeekdayShort.length; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      kWeekdayShort[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiaryLabel,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.92,
            ),
            itemCount: cells.length,
            itemBuilder: (context, index) {
              final day = cells[index];
              if (day == null) return const SizedBox.shrink();
              final isToday =
                  day.year == today.year &&
                  day.month == today.month &&
                  day.day == today.day;
              final isSelected =
                  day.year == _selectedDay.year &&
                  day.month == _selectedDay.month &&
                  day.day == _selectedDay.day;
              final isWeekend = day.weekday >= DateTime.saturday;
              final hasAppts = apptDays.contains(day.day);
              final hasJobs = jobDays.contains(day.day);
              return GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: Container(
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.tint(colors.accent, 0.14)
                        : (isToday ? colors.tint(colors.accent, 0.07) : null),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? colors.accent : colors.separator,
                      width: isSelected ? 1.2 : 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday
                              ? colors.accent
                              : (isWeekend
                                    ? colors.secondaryLabel
                                    : colors.label),
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (hasAppts || hasJobs)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          height: 6,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasAppts) _dot(colors, colors.accent),
                              if (hasJobs) ...[
                                if (hasAppts) const SizedBox(width: 3),
                                _dot(colors, colors.orange),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dayLabel(_selectedDay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (dayEvents.isNotEmpty)
                Pill(
                  '${dayEvents.length} ${eventsWord(dayEvents.length)}',
                  color: colors.accent,
                ),
            ],
          ),
        ),
        Expanded(
          child: dayEvents.isEmpty
              ? EmptyState(
                  title: 'Событий нет',
                  message: 'На этот день нет записей и заказов.',
                  art: Icon(
                    CupertinoIcons.calendar,
                    size: 36,
                    color: colors.tertiaryLabel,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 72),
                  itemCount: dayEvents.length,
                  itemBuilder: (context, index) {
                    final event = dayEvents[index];
                    return event.isAppointment
                        ? _AppointmentDayCard(
                            event: event,
                            store: store,
                            actions: widget.actions,
                          )
                        : _JobDayCard(
                            event: event,
                            store: store,
                            actions: widget.actions,
                          );
                  },
                ),
        ),
      ],
    );
  }

  Widget _dot(AppColors colors, Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// «ноябрь 2026» — месяц строчными, как принято в русской дате.
  String _monthLabel(DateTime month) {
    final label = DateFormat('LLLL yyyy', 'ru').format(month);
    return label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
  }

  /// «4 ноября, среда» — день недели рядом с датой, чтобы не заглядывать
  /// в календарь за ориентацией.
  String _dayLabel(DateTime day) {
    final date = DateFormat('d MMMM', 'ru').format(day);
    final dateCapitalized = date.isEmpty
        ? date
        : date[0].toUpperCase() + date.substring(1);
    return '$dateCapitalized, ${kWeekdayFull[day.weekday - 1]}';
  }
}

/// Сокращённые названия дней недели, начиная с понедельника
/// (в русском календаре неделя начинается с понедельника).
const List<String> kWeekdayShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

const List<String> kWeekdayFull = [
  'понедельник',
  'вторник',
  'среда',
  'четверг',
  'пятница',
  'суббота',
  'воскресенье',
];

class _AppointmentDayCard extends StatelessWidget {
  const _AppointmentDayCard({
    required this.event,
    required this.store,
    required this.actions,
  });

  final UnifiedEvent event;
  final MastersStore store;
  final UnifiedBookingActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final a = event.appointment!;
    final client = a.clientId == null ? null : store.clientById(a.clientId!);
    String? resource;
    if (a.resourceId != null) {
      for (final r in store.bookingResources) {
        if (r.id == a.resourceId) {
          resource = r.name;
          break;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(a.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(CupertinoIcons.delete, color: colors.red),
        ),
        confirmDismiss: (_) => showAppConfirm(
          context,
          title: 'Удалить запись?',
          message: a.title,
          destructive: true,
          confirmLabel: 'Удалить',
        ),
        onDismissed: (_) => store.deleteAppointment(a.id),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 36,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      // События из колонки «Готово» — перечёркнуты.
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: event.kanbanKey == 'done'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${DateFormat('HH:mm', 'ru').format(a.startAt)}–${DateFormat('HH:mm', 'ru').format(a.endAt)}${client != null ? ' • ${client.name}' : ''}${resource != null ? ' • $resource' : ''}',
                      style: TextStyle(
                        color: colors.secondaryLabel,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (a.status != AppointmentStatus.scheduled)
                      Pill(event.statusLabel, color: colors.tertiaryLabel),
                  ],
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => store.setAppointmentStatus(
                  a.id,
                  a.status == AppointmentStatus.done
                      ? AppointmentStatus.scheduled
                      : AppointmentStatus.done,
                ),
                child: Icon(
                  CupertinoIcons.checkmark_circle,
                  size: 20,
                  color: a.status == AppointmentStatus.done
                      ? colors.green
                      : colors.tertiaryLabel,
                  semanticLabel: 'Выполнено',
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => actions.convertAppointmentToJob(a.id),
                child: Icon(
                  CupertinoIcons.forward,
                  size: 18,
                  color: colors.accent,
                  semanticLabel: 'Сделать заказом',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobDayCard extends StatelessWidget {
  const _JobDayCard({
    required this.event,
    required this.store,
    required this.actions,
  });

  final UnifiedEvent event;
  final MastersStore store;
  final UnifiedBookingActions actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final j = event.job!;
    final client = store.clientById(j.clientId);
    final deadline = j.dueDate ?? j.startedAt!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    j.title,
                    // События из колонки «Готово» — перечёркнуты.
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: event.kanbanKey == 'done'
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Дедлайн: ${DateFormat('d MMM HH:mm', 'ru').format(deadline)}${client != null ? ' • ${client.name}' : ''}',
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (j.status != JobStatus.nuevo)
                    Pill(event.statusLabel, color: colors.tertiaryLabel),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => actions.convertJobToAppointment(j.id),
              child: const Icon(
                CupertinoIcons.calendar_badge_plus,
                size: 20,
                semanticLabel: 'Создать запись',
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => JobDetailScreen(jobId: j.id),
                ),
              ),
              child: Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.tertiaryLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
