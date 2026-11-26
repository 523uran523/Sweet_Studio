import 'package:flutter_test/flutter_test.dart';
import 'package:masters/features/jobs/calculator_core.dart';

void main() {
  CalculatorTotals calculate({
    PricingMode mode = PricingMode.markup,
    double target = 30,
    int fixed = 0,
    int cost = 10000,
    int shipping = 0,
    int returnShipping = 0,
    int storage = 0,
    double buyout = 100,
    double overheadPercent = 0,
    int overheadFixed = 0,
    double margin = 30,
    double commission = 0,
    double advertising = 0,
    double acquiring = 0,
    double defect = 0,
  }) => computeCalculatorTotals(
    materialsCents: cost,
    laborHours: 0,
    laborRateCents: 0,
    otherCents: 0,
    overheadPercent: overheadPercent,
    overheadFixedCents: overheadFixed,
    marginPercent: margin,
    pricingMode: mode,
    targetMarginPercent: target,
    fixedPriceCents: fixed,
    shippingCents: shipping,
    storageCents: storage,
    returnShippingCents: returnShipping,
    buyoutPercent: buyout,
    commissionPercent: commission,
    advertisingPercent: advertising,
    acquiringPercent: acquiring,
    finishedDefectPercent: defect,
  );

  test('legacy markup remains based on cost', () {
    expect(calculate().priceCents, 13000);
  });

  test('fixed overhead defaults to zero and preserves legacy cost', () {
    final result = calculate(cost: 10000);
    expect(result.overheadCents, 0);
    expect(result.productionCostCents, 10000);
    expect(result.costCents, 10000);
  });

  test('fixed overhead is added once alongside percent overhead', () {
    final result = computeCalculatorTotals(
      materialsCents: 10000,
      laborHours: 0,
      laborRateCents: 0,
      otherCents: 0,
      overheadPercent: 10,
      overheadFixedCents: 500,
      marginPercent: 0,
    );
    expect(result.overheadCents, 1500);
    expect(result.productionCostCents, 11500);
    expect(result.costCents, 11500);
  });

  test('negative fixed overhead is clamped to zero', () {
    final result = calculate(overheadPercent: 10, overheadFixed: -500);
    expect(result.overheadCents, 1000);
    expect(result.productionCostCents, 11000);
  });

  test('target margin is a share of price', () {
    final result = calculate(mode: PricingMode.targetMargin, target: 20);
    expect(result.priceCents, 12500);
    expect(result.marginCents, 2500);
    expect(
      calculate(mode: PricingMode.targetMargin, target: 30, cost: 1).priceCents,
      2,
    );
    expect(
      calculate(mode: PricingMode.targetMargin, target: 100).validPrice,
      isFalse,
    );
  });

  test('fixed price shows the actual loss', () {
    final result = calculate(mode: PricingMode.fixedPrice, fixed: 8000);
    expect(result.priceCents, 8000);
    expect(result.marginCents, -2000);
  });

  test('sales costs are included in price and profit', () {
    CalculatorTotals result(PricingMode mode, {double target = 20}) =>
        computeCalculatorTotals(
          materialsCents: 10000,
          laborHours: 0,
          laborRateCents: 0,
          otherCents: 0,
          overheadPercent: 0,
          marginPercent: 25,
          pricingMode: mode,
          targetMarginPercent: target,
          fixedPriceCents: 20000,
          packagingCents: 1000,
          shippingCents: 1000,
          commissionPercent: 10,
          advertisingPercent: 5,
          acquiringPercent: 5,
        );
    final markup = result(PricingMode.markup);
    expect(markup.priceCents, 18750);
    expect(markup.productionCostCents, 10000);
    expect(markup.sellingCostCents, 5750);
    expect(markup.marginCents, 3000);
    final margin = result(PricingMode.targetMargin);
    expect(margin.priceCents, 20000);
    expect(margin.marginCents, 4000);
    expect(result(PricingMode.fixedPrice).marginCents, 4000);
    expect(result(PricingMode.targetMargin, target: 80).validPrice, isFalse);
  });

  test('forecast defaults preserve shipping in selling cost', () {
    final result = calculate(shipping: 1000);
    expect(result.buyoutValid, isTrue);
    expect(result.buyoutPercent, 100);
    expect(result.storageCents, 0);
    expect(result.returnShippingCents, 0);
    expect(result.effectiveShippingCents, 1000);
    expect(result.sellingCostCents, 1000);
  });

  test('buyout forecast grosses up delivery and return shipping', () {
    final result = calculate(
      shipping: 100,
      returnShipping: 20,
      buyout: 50.0,
    );
    expect(result.effectiveShippingCents, 220);
    expect(result.sellingCostCents, 220);
  });

  test('storage is added to forecast selling cost', () {
    final result = calculate(
      shipping: 100,
      returnShipping: 20,
      buyout: 50.0,
      storage: 75,
    );
    expect(result.effectiveShippingCents, 220);
    expect(result.storageCents, 75);
    expect(result.sellingCostCents, 295);
    expect(result.costCents, 10295);
  });

  test('invalid buyout forecast disables pricing', () {
    for (final buyout in <double>[
      0.0,
      -1.0,
      101.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final result = calculate(buyout: buyout);
      expect(result.buyoutValid, isFalse, reason: '$buyout');
      expect(result.effectiveShippingCents, 0, reason: '$buyout');
      expect(result.validPrice, isFalse, reason: '$buyout');
    }
  });

  test('rounded commission does not reduce target margin', () {
    final result = computeCalculatorTotals(
      materialsCents: 1,
      laborHours: 0,
      laborRateCents: 0,
      otherCents: 0,
      overheadPercent: 0,
      marginPercent: 0,
      pricingMode: PricingMode.targetMargin,
      targetMarginPercent: 34,
      commissionPercent: 17,
    );
    expect(
      result.marginCents * 100,
      greaterThanOrEqualTo(result.priceCents * 34),
    );
  });

  test('finished defect increases direct cost and preserves overhead base', () {
    CalculatorTotals result(double defect) => computeCalculatorTotals(
      materialsCents: 10000,
      laborHours: 0,
      laborRateCents: 0,
      otherCents: 0,
      overheadPercent: 10,
      marginPercent: 0,
      finishedDefectPercent: defect,
    );
    expect(result(0).productionCostCents, 11000);
    expect(result(0).finishedDefectCents, 0);
    expect(result(10).finishedDefectCents, 1112);
    expect(result(10).overheadCents, 1000);
    expect(result(10).productionCostCents, 12112);
    expect(result(100).validPrice, isFalse);
    expect(result(-1).validPrice, isFalse);
    expect(result(double.nan).validPrice, isFalse);
    expect(result(double.infinity).validPrice, isFalse);
  });

  test('piecework is added to labor and the cost base', () {
    final result = computeCalculatorTotals(
      materialsCents: 1000,
      laborHours: 1,
      laborRateCents: 500,
      pieceworkCents: 500,
      otherCents: 0,
      overheadPercent: 10,
      marginPercent: 0,
    );
    expect(result.pieceworkCents, 500);
    expect(result.laborCents, 1000);
    expect(result.baseCents, 2000);
    expect(result.overheadCents, 200);
    expect(result.productionCostCents, 2200);
  });

  test('piecework defaults to zero and preserves legacy labor', () {
    final withDefault = computeCalculatorTotals(
      materialsCents: 1000,
      laborHours: 1,
      laborRateCents: 500,
      otherCents: 0,
      overheadPercent: 10,
      marginPercent: 0,
    );
    expect(withDefault.pieceworkCents, 0);
    expect(withDefault.laborCents, 500);
    expect(withDefault.baseCents, 1500);
    expect(withDefault.overheadCents, 150);
    expect(withDefault.productionCostCents, 1650);

    final negative = computeCalculatorTotals(
      materialsCents: 1000,
      laborHours: 1,
      laborRateCents: 500,
      pieceworkCents: -100,
      otherCents: 0,
      overheadPercent: 10,
      marginPercent: 0,
    );
    expect(negative.pieceworkCents, 0);
    expect(negative.laborCents, 500);
    expect(negative.productionCostCents, 1650);
  });

  group('break-even and ROI', () {
    test('break-even equals cost with no fees', () {
      expect(calculate().breakEvenCents, 10000);
      expect(calculate().priceCents, 13000);
    });

    test('break-even grosses up percentage fees and rounds up', () {
      // 10000 / (1 - 0.10) = 11111.11... -> 11112.
      expect(calculate(commission: 10).breakEvenCents, 11112);
      // Fees add up: 10% + 5% = 15%, 10000 / 0.85 = 11764.7... -> 11765.
      expect(calculate(commission: 10, acquiring: 5).breakEvenCents, 11765);
    });

    test('break-even rounds up to the next whole cent', () {
      // 1 / (1 - 0.10) = 1.111... -> 2 cents.
      expect(calculate(cost: 1, commission: 10).breakEvenCents, 2);
    });

    test('ROI is profit divided by total cost times 100', () {
      final result = calculate();
      expect(result.priceCents, 13000);
      expect(result.costCents, 10000);
      expect(result.roiPercent, closeTo(30, 1e-9));
    });

    test('ROI is null when total cost is zero', () {
      final result = calculate(cost: 0);
      expect(result.costCents, 0);
      expect(result.breakEvenCents, 0);
      expect(result.roiPercent, isNull);
    });

    test('invalid fee, buyout, defect or price yields no estimates', () {
      final badFee = calculate(commission: 100);
      expect(badFee.validPrice, isFalse);
      expect(badFee.breakEvenCents, isNull);
      expect(badFee.roiPercent, isNull);

      final badBuyout = calculate(buyout: 0);
      expect(badBuyout.validPrice, isFalse);
      expect(badBuyout.breakEvenCents, isNull);
      expect(badBuyout.roiPercent, isNull);

      final badDefect = calculate(defect: 100);
      expect(badDefect.validPrice, isFalse);
      expect(badDefect.breakEvenCents, isNull);
      expect(badDefect.roiPercent, isNull);

      final badMargin = calculate(mode: PricingMode.targetMargin, target: 100);
      expect(badMargin.validPrice, isFalse);
      expect(badMargin.breakEvenCents, isNull);
      expect(badMargin.roiPercent, isNull);
    });
  });

  group('effectiveQuantity', () {
    test('no loss keeps the net quantity', () {
      expect(effectiveQuantity(qtyText: '1', lossText: '0'), 1.0);
      expect(effectiveQuantity(qtyText: '2.5', lossText: '0'), 2.5);
    });

    test('20% loss grosses up 1 to 1.25', () {
      expect(
        effectiveQuantity(qtyText: '1', lossText: '20'),
        closeTo(1.25, 1e-9),
      );
      expect(effectiveQuantity(qtyText: '2', lossText: '50'), 4.0);
    });

    test('invalid loss or quantity returns null', () {
      expect(effectiveQuantity(qtyText: '1', lossText: '100'), isNull);
      expect(effectiveQuantity(qtyText: '1', lossText: '-5'), isNull);
      expect(effectiveQuantity(qtyText: '1', lossText: 'NaN'), isNull);
      expect(effectiveQuantity(qtyText: '1', lossText: 'Infinity'), isNull);
      expect(effectiveQuantity(qtyText: '1', lossText: ''), isNull);
      expect(effectiveQuantity(qtyText: '', lossText: '10'), isNull);
      expect(effectiveQuantity(qtyText: 'NaN', lossText: '10'), isNull);
    });
  });
}
