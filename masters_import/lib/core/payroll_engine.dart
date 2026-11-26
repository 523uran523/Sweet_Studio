/// Чистый движок начислений: даты условий на дату источника, полный
/// полуоткрытый интервал периода, никаких обращений к БД.
///
/// Используется в двух местах: сводка по открытому периоду (вживую, те же
/// правила) и закрытие периода (транзакционная вставка строк). Один код —
/// одно правило округления, деньги только в копейках.
library;

import '../data/models/job.dart';
import '../data/models/pay_condition.dart';
import '../data/models/time_entry.dart';
import 'payroll_calc.dart';

/// Одна вычисленная строка начисления. Без `id` и привязки к ведомости:
/// их присваивает закрытие периода при вставке.
class AccrualLine {
  const AccrualLine({
    required this.sourceKind,
    required this.sourceId,
    required this.accrualKind,
    required this.occurredAt,
    required this.minutes,
    required this.basisPriceCents,
    required this.rateCents,
    required this.percent,
    required this.payType,
    required this.amountCents,
    required this.needsReview,
    this.payConditionId,
  });

  final String sourceKind; // time_entry | job
  final String sourceId;
  final String accrualKind; // hourly | piece | percent
  final DateTime occurredAt;
  final int minutes;
  final int basisPriceCents;
  final int rateCents;
  final double percent;
  final String payType;
  final int amountCents;

  /// Условия, по которым считали. `null` — у сотрудника нет ни одной
  /// строки условий (строки создаются с needsReview).
  final String? payConditionId;

  /// Ставка на дату работы не найдена (ранняя работа до первой записи или
  /// фолбэк на самую раннюю запись) — мастеру нужно сверить строку.
  final bool needsReview;
}

/// Условия, действующие на момент [at]: последняя строка с
/// `valid_from <= at`. Если все строки позже [at] — самая ранняя
/// (историческая ставка отсутствует, отдаём её как фолбэк). Условий
/// нет совсем — `null`.
PayCondition? conditionOn(List<PayCondition> conditions, DateTime at) {
  if (conditions.isEmpty) return null;
  PayCondition? best;
  PayCondition? earliest;
  for (final c in conditions) {
    if (c.deletedAt != null) continue;
    if (earliest == null || c.validFrom.isBefore(earliest.validFrom)) {
      earliest = c;
    }
    if (!c.validFrom.isAfter(at)) {
      if (best == null || c.validFrom.isAfter(best.validFrom)) best = c;
    }
  }
  return best ?? earliest;
}

bool conditionIsFallback(List<PayCondition> conditions, DateTime at) {
  for (final c in conditions) {
    if (c.deletedAt != null) continue;
    if (!c.validFrom.isAfter(at)) return false;
  }
  return conditions.isNotEmpty;
}

int _entryMinutes(TimeEntry t) {
  if (t.minutes > 0) return t.minutes;
  final end = t.endedAt;
  if (end == null) return 0;
  final diff = end.difference(t.startedAt).inMinutes;
  return diff < 0 ? 0 : diff;
}

/// Собирает строки начислений сотрудника за полуоткрытый интервал
/// `[start, endExclusive)`.
///
/// Правила (те же, что в живой сводке v25, но с датированными условиями):
/// - почасовой/окладной/смешанный тип: минуты записей табеля в интервале;
/// - сдельный: один к одному на завершённый заказ (только тип `piece`);
/// - процентный: цена заказа × процент (типы `percent` и `mixed`);
/// - округление на уровне строки, деньги в копейках.
///
/// [defaultPayType] — тип оплаты из карточки, используется только когда у
/// сотрудника нет строк условий вообще (фолбэк, строка помечается
/// needsReview).
List<AccrualLine> buildAccrualLines({
  required DateTime start,
  required DateTime endExclusive,
  required List<PayCondition> conditions,
  required List<TimeEntry> timeEntries,
  required List<Job> jobs,
  required String defaultPayType,
}) {
  bool inRange(DateTime at) => !at.isBefore(start) && at.isBefore(endExclusive);

  final lines = <AccrualLine>[];
  final sorted = List<PayCondition>.of(conditions)
    ..sort((a, b) => a.validFrom.compareTo(b.validFrom));

  for (final t in timeEntries) {
    if (!inRange(t.startedAt)) continue;
    final condition = conditionOn(sorted, t.startedAt);
    final fallback = conditionIsFallback(sorted, t.startedAt);
    final payType = condition?.payType ?? defaultPayType;
    final hourlyLike =
        payType == 'hourly' || payType == 'mixed' || payType == 'salary';
    if (!hourlyLike) continue; // сдельщик и процентник за часы не начисляют
    final minutes = _entryMinutes(t);
    final rate = condition?.rateCents ?? 0;
    lines.add(
      AccrualLine(
        sourceKind: 'time_entry',
        sourceId: t.id,
        accrualKind: 'hourly',
        occurredAt: t.startedAt,
        minutes: minutes,
        basisPriceCents: 0,
        rateCents: rate,
        percent: 0,
        payType: payType,
        amountCents: hourlyAccrualCents(minutes, rate),
        needsReview: condition == null || fallback,
        payConditionId: condition?.id,
      ),
    );
  }

  for (final j in jobs) {
    if (j.status != JobStatus.done && j.status != JobStatus.closed) continue;
    if (j.archived) continue;
    final doneAt = j.finishedAt ?? j.updatedAt;
    if (!inRange(doneAt)) continue;
    final condition = conditionOn(sorted, doneAt);
    final fallback = conditionIsFallback(sorted, doneAt);
    final payType = condition?.payType ?? defaultPayType;
    final common = (
      sourceKind: 'job',
      sourceId: j.id,
      occurredAt: doneAt,
      basisPriceCents: j.priceCents,
      payType: payType,
      needsReview: condition == null || fallback,
      payConditionId: condition?.id,
    );
    if (payType == 'piece') {
      final rate = condition?.rateCents ?? 0;
      lines.add(
        AccrualLine(
          sourceKind: common.sourceKind,
          sourceId: common.sourceId,
          accrualKind: 'piece',
          occurredAt: common.occurredAt,
          minutes: 0,
          basisPriceCents: common.basisPriceCents,
          rateCents: rate,
          percent: 0,
          payType: payType,
          amountCents: rate,
          needsReview: common.needsReview,
          payConditionId: common.payConditionId,
        ),
      );
    }
    if (payType == 'percent' || payType == 'mixed') {
      final percent = condition?.percent ?? 0;
      lines.add(
        AccrualLine(
          sourceKind: common.sourceKind,
          sourceId: common.sourceId,
          accrualKind: 'percent',
          occurredAt: common.occurredAt,
          minutes: 0,
          basisPriceCents: common.basisPriceCents,
          rateCents: condition?.rateCents ?? 0,
          percent: percent,
          payType: payType,
          amountCents: percentAccrualCents(j.priceCents, percent),
          needsReview: common.needsReview,
          payConditionId: common.payConditionId,
        ),
      );
    }
  }

  return lines;
}
