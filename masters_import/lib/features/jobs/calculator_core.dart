import '../../core/units.dart';

enum PricingMode { markup, targetMargin, fixedPrice }

/// Итоги калькулятора: материалы + работа + прочие расходы,
/// накладные процентом от базы, маржа процентом от себестоимости.
class CalculatorTotals {
  const CalculatorTotals({
    required this.materialsCents,
    required this.laborCents,
    required this.otherCents,
    required this.overheadCents,
    required this.costCents,
    required this.priceCents,
    this.validPrice = true,
    this.productionCostCents = 0,
    this.sellingCostCents = 0,
    this.pieceworkCents = 0,
    this.finishedDefectCents = 0,
    this.finishedDefectValid = true,
    this.storageCents = 0,
    this.returnShippingCents = 0,
    this.buyoutPercent = 100,
    this.effectiveShippingCents = 0,
    this.buyoutValid = true,
    this.breakEvenCents,
    this.roiPercent,
  });

  final int materialsCents;
  final int laborCents;
  final int otherCents;
  final int overheadCents;
  final int costCents;
  final int priceCents;
  final bool validPrice;
  final int productionCostCents;
  final int sellingCostCents;
  final int pieceworkCents;
  final int finishedDefectCents;
  final bool finishedDefectValid;
  final int storageCents;
  final int returnShippingCents;
  final double buyoutPercent;
  final int effectiveShippingCents;
  final bool buyoutValid;

  /// Оценка безубыточной цены продажи: затраты до процентных расходов,
  /// делённые на (1 − доля процентов), округлённые вверх до целого цента.
  ///
  /// null — если состояние расчёта некорректно (комиссии, цена, выкуп, брак).
  final int? breakEvenCents;

  /// Рентабельность инвестиций, %: прибыль / полная себестоимость × 100.
  ///
  /// null — если себестоимость равна нулю или состояние расчёта некорректно.
  final double? roiPercent;

  int get baseCents => materialsCents + laborCents + otherCents;

  int get marginCents => priceCents - costCents;
}

/// Стоимость строки ресурса: количество в своей единице × цена за свою
/// единицу, приведённые к общей базовой мере.
int resourceLineTotalCents({
  required double qty,
  required String qtyUnit,
  required int priceCents,
  required String priceUnit,
}) {
  if (qty <= 0 || priceCents == 0) return 0;
  final priceBase = priceBaseOf(priceUnit);
  if (priceBase <= 0) return 0;
  final total = qty * qtyBaseOf(qtyUnit) / priceBase * priceCents;
  if (!total.isFinite) return 0;
  return total.round();
}

double? _parseNumber(String text) {
  final trimmed = text.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

/// Эффективное (брутто) количество с учётом технологических потерь.
///
/// Формула: net / (1 - loss / 100), где [lossText] — процент потерь.
/// Возвращает null, если количество или процент не являются конечными
/// числами, текст пуст, либо процент потерь вне диапазона [0, 100).
double? effectiveQuantity({
  required String qtyText,
  required String lossText,
}) {
  final qty = _parseNumber(qtyText);
  final loss = _parseNumber(lossText);
  if (qty == null || loss == null) return null;
  if (!qty.isFinite || qty < 0) return null;
  if (!loss.isFinite || loss < 0 || loss >= 100) return null;
  final effective = qty * 100 / (100 - loss);
  if (!effective.isFinite) return null;
  return effective;
}

/// Прогноз логистики на одну успешную продажу: доставка с учётом
/// возвратов и хранение включаются в расходы на продажу.
CalculatorTotals computeCalculatorTotals({
  required int materialsCents,
  required double laborHours,
  required int laborRateCents,
  int pieceworkCents = 0,
  required int otherCents,
  required double overheadPercent,
  int overheadFixedCents = 0,
  required double marginPercent,
  PricingMode pricingMode = PricingMode.markup,
  double targetMarginPercent = 30,
  int fixedPriceCents = 0,
  int packagingCents = 0,
  int shippingCents = 0,
  int storageCents = 0,
  int returnShippingCents = 0,
  double buyoutPercent = 100,
  double commissionPercent = 0,
  double advertisingPercent = 0,
  double acquiringPercent = 0,
  double finishedDefectPercent = 0,
}) {
  final hours = laborHours.isFinite && laborHours > 0 ? laborHours : 0.0;
  final rate = laborRateCents < 0 ? 0 : laborRateCents;
  final piecework = pieceworkCents < 0 ? 0 : pieceworkCents;
  final labor = (hours * rate).round() + piecework;
  final other = otherCents < 0 ? 0 : otherCents;
  final base = materialsCents + labor + other;
  final defectValid = finishedDefectPercent.isFinite &&
      finishedDefectPercent >= 0 &&
      finishedDefectPercent < 100;
  final defectCost = defectValid && finishedDefectPercent > 0
      ? (base / (1 - finishedDefectPercent / 100)).ceil() - base
      : 0;
  final overheadPct = overheadPercent.isFinite && overheadPercent > 0
      ? overheadPercent
      : 0.0;
  final overheadFixed = overheadFixedCents < 0 ? 0 : overheadFixedCents;
  final overhead = (base * overheadPct / 100).round() + overheadFixed;
  final productionCost = base + defectCost + overhead;
  final storage = storageCents < 0 ? 0 : storageCents;
  final returnCost = returnShippingCents < 0 ? 0 : returnShippingCents;
  final buyoutValid = buyoutPercent.isFinite &&
      buyoutPercent > 0 &&
      buyoutPercent <= 100;
  final buyoutRate = buyoutValid ? buyoutPercent / 100 : 1.0;
  final effectiveShippingRaw = buyoutValid
      ? ((shippingCents < 0 ? 0 : shippingCents) +
              returnCost * (1 - buyoutRate)) /
          buyoutRate
      : 0.0;
  final effectiveShipping =
      effectiveShippingRaw.isFinite ? effectiveShippingRaw.ceil() : 0;
  final fixedCosts = (packagingCents < 0 ? 0 : packagingCents) +
      effectiveShipping +
      storage;
  final costsBeforeFees = productionCost + fixedCosts;
  final percentages = [commissionPercent, advertisingPercent, acquiringPercent];
  final validFees = percentages.every((value) => value.isFinite && value >= 0) &&
      percentages.fold<double>(0, (sum, value) => sum + value) < 100;
  final feeRate = validFees ? percentages.fold<double>(0, (sum, value) => sum + value) / 100 : 0;
  final marginPct = marginPercent.isFinite ? marginPercent : 0.0;
  final validMargin = pricingMode != PricingMode.targetMargin ||
      (targetMarginPercent.isFinite && targetMarginPercent >= 0 &&
          targetMarginPercent / 100 + feeRate < 1);
  final validPrice = validFees && validMargin && defectValid && buyoutValid;
  final raw = switch (pricingMode) {
    PricingMode.markup => validFees
        ? (costsBeforeFees * (1 + marginPct / 100) / (1 - feeRate)).round()
        : 0,
    PricingMode.targetMargin => validPrice
        ? (costsBeforeFees / (1 - feeRate - targetMarginPercent / 100)).ceil()
        : 0,
    PricingMode.fixedPrice => fixedPriceCents,
  };
  var price = raw < 0 ? 0 : raw;
  if (pricingMode == PricingMode.targetMargin && validPrice && feeRate > 0) {
    final fee = (price * feeRate).round();
    final shortfall = costsBeforeFees + fee + price * targetMarginPercent / 100 - price;
    if (shortfall > 0) {
      price += ((shortfall + 0.5) / (1 - feeRate - targetMarginPercent / 100)).ceil();
    }
  }
  final fees = (price * feeRate).round();
  final sellingCosts = fixedCosts + fees;
  final totalCost = productionCost + sellingCosts;
  final breakEvenCents = validPrice && feeRate < 1
      ? (costsBeforeFees / (1 - feeRate)).ceil()
      : null;
  final roiPercent =
      validPrice && totalCost > 0 ? (price - totalCost) / totalCost * 100 : null;
  return CalculatorTotals(
    materialsCents: materialsCents,
    laborCents: labor,
    otherCents: other,
    overheadCents: overhead,
    costCents: totalCost,
    priceCents: price,
    validPrice: validPrice,
    productionCostCents: productionCost,
    sellingCostCents: sellingCosts,
    pieceworkCents: piecework,
    finishedDefectCents: defectCost,
    finishedDefectValid: defectValid,
    storageCents: storage,
    returnShippingCents: returnCost,
    buyoutPercent: buyoutPercent,
    effectiveShippingCents: effectiveShipping,
    buyoutValid: buyoutValid,
    breakEvenCents: breakEvenCents,
    roiPercent: roiPercent,
  );
}
