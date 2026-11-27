import '../data/models.dart';
import 'money_format.dart';

const Map<WorkRecurrence, String> kRecurrenceLabelsRu = {
  WorkRecurrence.none: 'Без повтора',
  WorkRecurrence.daily: 'Ежедневно',
  WorkRecurrence.weekly: 'Еженедельно',
  WorkRecurrence.biweekly: 'Раз в 2 недели',
  WorkRecurrence.monthly: 'Ежемесячно',
};

({int y, int m, int d})? _parseIsoParts(String? iso) {
  if (iso == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso)) {
    return null;
  }
  final parts = iso.split('-');
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return (y: y, m: m, d: d);
}

String _formatUtcDate(DateTime dt) {
  return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

String computeNextDueDate(
  String? currentIso,
  WorkRecurrence recurrence, [
  String? fallbackTodayIso,
]) {
  final fallback = fallbackTodayIso ?? todayIsoDate();
  final nowUtc = DateTime.now().toUtc();
  final base = _parseIsoParts(currentIso) ??
      _parseIsoParts(fallback) ??
      (y: nowUtc.year, m: nowUtc.month, d: nowUtc.day);

  switch (recurrence) {
    case WorkRecurrence.daily:
      return _formatUtcDate(DateTime.utc(base.y, base.m, base.d + 1));
    case WorkRecurrence.weekly:
      return _formatUtcDate(DateTime.utc(base.y, base.m, base.d + 7));
    case WorkRecurrence.biweekly:
      return _formatUtcDate(DateTime.utc(base.y, base.m, base.d + 14));
    case WorkRecurrence.monthly:
      final nextMonthZeroBased = base.m; // base.m is 1-based => next 0-based
      final targetYear = base.y + (nextMonthZeroBased ~/ 12);
      final normalizedMonth = (nextMonthZeroBased % 12) + 1;
      final lastDayOfTargetMonth =
          DateTime.utc(targetYear, normalizedMonth + 1, 0).day;
      final clampedDay =
          base.d < lastDayOfTargetMonth ? base.d : lastDayOfTargetMonth;
      return _formatUtcDate(
        DateTime.utc(targetYear, normalizedMonth, clampedDay),
      );
    case WorkRecurrence.none:
      return _formatUtcDate(DateTime.utc(base.y, base.m, base.d));
  }
}

class NextRecurringOccurrencePlan {
  const NextRecurringOccurrencePlan({
    required this.seriesId,
    required this.currentIndex,
    required this.nextIndex,
    required this.nextDueDate,
    required this.nextItem,
  });

  final String seriesId;
  final int currentIndex;
  final int nextIndex;
  final String nextDueDate;
  final WorkItem nextItem;
}

NextRecurringOccurrencePlan? planNextRecurringWorkItem(
  WorkItem completedItem,
  List<WorkItem> existingItems, [
  String? fallbackTodayIso,
]) {
  final rec = completedItem.recurrence;
  if (rec == WorkRecurrence.none) return null;

  final seriesId =
      (completedItem.seriesId != null && completedItem.seriesId!.isNotEmpty)
          ? completedItem.seriesId!
          : completedItem.id;
  final currentIndex = completedItem.occurrenceIndex ?? 1;
  final nextIndex = currentIndex + 1;

  final alreadyExists = existingItems.any(
    (w) =>
        ((w.seriesId != null && w.seriesId!.isNotEmpty) ? w.seriesId! : w.id) ==
            seriesId &&
        (w.occurrenceIndex ?? 1) == nextIndex,
  );
  if (alreadyExists) return null;

  final nextDue = computeNextDueDate(
    completedItem.dueDate,
    rec,
    fallbackTodayIso ?? todayIsoDate(),
  );

  final nextItem = WorkItem(
    id: newId('wi'),
    type: completedItem.type,
    sourceId: completedItem.sourceId,
    title: completedItem.title,
    dueDate: nextDue,
    priority: completedItem.priority,
    stage: WorkStage.queue,
    tags: List<String>.from(completedItem.tags),
    recurrence: rec,
    seriesId: seriesId,
    occurrenceIndex: nextIndex,
  );

  return NextRecurringOccurrencePlan(
    seriesId: seriesId,
    currentIndex: currentIndex,
    nextIndex: nextIndex,
    nextDueDate: nextDue,
    nextItem: nextItem,
  );
}
