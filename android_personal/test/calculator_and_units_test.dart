import 'package:flutter_test/flutter_test.dart';
import 'package:sweet_studio_personal/core/calculator_core.dart';
import 'package:sweet_studio_personal/core/units.dart';
import 'package:sweet_studio_personal/data/models.dart';

void main() {
  group('units parity', () {
    test('converts compatible mass and volume units accurately', () {
      expect(convertQty(1.5, 'кг', 'г'), closeTo(1500, 1e-6));
      expect(convertQty(250, 'мл', 'л'), closeTo(0.25, 1e-6));
      expect(convertQty(500, 'г', 'мл'), isNull);
    });

    test('density-gated mass<->volume conversion requires positive density', () {
      expect(convertQtyWithDensity(500, 'мл', 'г'), isNull);
      expect(
        convertQtyWithDensity(100, 'мл', 'г', densityGPerMl: 1.03),
        closeTo(103, 1e-6),
      );
      expect(
        convertQtyWithDensity(206, 'г', 'мл', densityGPerMl: 1.03),
        closeTo(200, 1e-6),
      );
    });
  });

  group('calculatorCore parity', () {
    test('computes resource lines and loss-adjusted effective quantity', () {
      final eff = effectiveQuantity(180, 10);
      expect(eff, closeTo(200, 1e-6));
      expect(effectiveQuantity(100, 100), isNull);

      final lineCost = resourceLineTotalCents(
        qty: 250,
        qtyUnit: 'г',
        priceCents: 185000, // 1850 ₽ за кг
        priceUnit: 'за кг',
      );
      expect(lineCost, 46250);

      final per100 = resourceLineTotalCents(
        qty: 300,
        qtyUnit: 'г',
        priceCents: 12000, // 120 ₽ за 100 г
        priceUnit: 'за 100 г',
      );
      expect(per100, 36000);
    });

    test('computes markup, targetMargin, breakEven, and guards invalid fee/margin sums', () {
      final markupTotals = computeCalculatorTotals(
        const CalculatorInput(
          materialsCents: 100000,
          laborHours: 2,
          laborRateCents: 50000,
          overheadPercent: 10,
          marginPercent: 50,
          packagingCents: 15000,
        ),
      );
      // base = 1000 + 1000 = 2000₽; overhead = 200₽; prod = 2200₽; pkg = 150₽; costsBeforeFees = 2350₽
      // price = 2350 * 1.5 = 3525₽ (352500 kop)
      expect(markupTotals.productionCostCents, 220000);
      expect(markupTotals.priceCents, 352500);
      expect(markupTotals.validPrice, isTrue);

      final invalidTarget = computeCalculatorTotals(
        const CalculatorInput(
          materialsCents: 100000,
          laborHours: 1,
          laborRateCents: 50000,
          pricingMode: PricingMode.targetMargin,
          targetMarginPercent: 85,
          commissionPercent: 20,
        ),
      );
      expect(invalidTarget.validPrice, isFalse);
      expect(invalidTarget.priceCents, 0);
    });

    test('netCashTotals nets income, expense, transfers and reversals accurately', () {
      const txs = [
        MoneyTransaction(
          id: 't1',
          kind: TransactionKind.income,
          category: 'Оплата',
          amountCents: 500000,
          accountId: 'a1',
          accountName: 'Карта',
          occurredAt: '2026-03-01',
        ),
        MoneyTransaction(
          id: 't2',
          kind: TransactionKind.expense,
          category: 'Закупка',
          amountCents: 120000,
          accountId: 'a1',
          accountName: 'Карта',
          occurredAt: '2026-03-02',
        ),
        MoneyTransaction(
          id: 't3',
          kind: TransactionKind.reversal,
          category: 'Сторно',
          amountCents: 120000,
          accountId: 'a1',
          accountName: 'Карта',
          reversesId: 't2',
          occurredAt: '2026-03-02',
        ),
        MoneyTransaction(
          id: 't4',
          kind: TransactionKind.transfer,
          category: 'Перевод',
          amountCents: 100000,
          accountId: 'a1',
          accountName: 'Карта → Наличные',
          occurredAt: '2026-03-03',
        ),
      ];
      final res = netCashTotals(txs);
      expect(res.incomeCents, 500000);
      expect(res.expenseCents, 0);
      expect(res.netCents, 500000);
      expect(res.reversedIds, contains('t2'));
    });

    test('wouldCreateSubRecipeCycle detects direct and indirect cycles', () {
      const rA = Recipe(
        id: 'A',
        title: 'A',
        category: 'Торты',
        yieldGrams: 1000,
        costCents: 100,
        recommendedPriceCents: 200,
        ingredients: [
          RecipeIngredientLine(
            subRecipeId: 'B',
            name: 'B',
            qty: 100,
            unit: 'г',
            priceCents: 100,
            priceUnit: 'за кг',
          ),
        ],
      );
      const rB = Recipe(
        id: 'B',
        title: 'B',
        category: 'Полуфабрикаты',
        yieldGrams: 500,
        costCents: 100,
        recommendedPriceCents: 200,
      );
      expect(
        wouldCreateSubRecipeCycle(
          parentRecipeId: 'A',
          candidateSubRecipeId: 'A',
          allRecipes: [rA, rB],
        ),
        isTrue,
      );
      expect(
        wouldCreateSubRecipeCycle(
          parentRecipeId: 'B',
          candidateSubRecipeId: 'A',
          allRecipes: [rA, rB],
        ),
        isTrue,
      );
      expect(
        wouldCreateSubRecipeCycle(
          parentRecipeId: 'A',
          candidateSubRecipeId: 'B',
          allRecipes: [rA, rB],
        ),
        isFalse,
      );
    });
  });
}
