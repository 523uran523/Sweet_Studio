import 'package:flutter_test/flutter_test.dart';
import 'package:sweet_studio_personal/core/orders_core.dart';
import 'package:sweet_studio_personal/core/work_recurrence.dart';
import 'package:sweet_studio_personal/data/models.dart';

void main() {
  group('ordersCore parity', () {
    test('computes multi-item totals, summary title, and proportional recipe attribution', () {
      const items = [
        OrderItem(
          id: '1',
          recipeId: 'r1',
          recipeTitle: 'Торт «Ягодный»',
          qty: 1,
          weightGrams: 2000,
          priceCents: 600000,
          costCents: 300000,
        ),
        OrderItem(
          id: '2',
          recipeId: 'r2',
          recipeTitle: 'Капкейки',
          qty: 2,
          weightGrams: 500,
          priceCents: 150000,
          costCents: 60000,
        ),
      ];
      final totals = computeOrderItemsTotals(items);
      expect(totals.totalWeightGrams, 3000);
      expect(totals.basePriceCents, 900000);
      expect(totals.baseCostCents, 420000);
      expect(buildOrderSummaryTitle(items), 'Торт «Ягодный» + Капкейки ×2');

      const order = Order(
        id: 'o1',
        orderNumber: '№10',
        title: 'Торт «Ягодный» + Капкейки ×2',
        clientName: 'Анна',
        items: items,
        priceCents: 810000, // after 10% discount
        costCents: 420000,
        discountCents: 90000,
        createdAt: '2026-03-01',
      );
      final attr = attributeOrderToRecipes(order, const []);
      expect(attr.length, 2);
      expect(attr[0].revenueCents + attr[1].revenueCents, 810000);
      expect(attr[0].revenueCents, 540000);
      expect(attr[1].revenueCents, 270000);
    });
  });

  group('workRecurrence parity', () {
    test('clamps month-end dates properly across regular and leap February', () {
      expect(
        computeNextDueDate('2025-01-31', WorkRecurrence.monthly),
        '2025-02-28',
      );
      expect(
        computeNextDueDate('2024-01-31', WorkRecurrence.monthly),
        '2024-02-29',
      );
      expect(
        computeNextDueDate('2026-12-20', WorkRecurrence.biweekly),
        '2027-01-03',
      );
    });

    test('planNextRecurringWorkItem is idempotent for same series and occurrence index', () {
      const first = WorkItem(
        id: 'w1',
        type: WorkItemType.task,
        title: 'Чек-лист витрины',
        dueDate: '2026-03-10',
        stage: WorkStage.done,
        recurrence: WorkRecurrence.daily,
        seriesId: 'ser_1',
        occurrenceIndex: 1,
      );
      final plan1 = planNextRecurringWorkItem(first, [first]);
      expect(plan1, isNotNull);
      expect(plan1!.nextIndex, 2);
      expect(plan1.nextDueDate, '2026-03-11');

      final plan2 = planNextRecurringWorkItem(first, [first, plan1.nextItem]);
      expect(plan2, isNull);
    });
  });
}
