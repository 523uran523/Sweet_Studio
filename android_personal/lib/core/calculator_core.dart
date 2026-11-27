import '../data/models.dart';
import 'units.dart';

enum PricingMode { markup, targetMargin, fixedPrice }

class CalculatorInput {
  const CalculatorInput({
    required this.materialsCents,
    required this.laborHours,
    required this.laborRateCents,
    this.pieceworkCents = 0,
    this.otherCents = 0,
    this.overheadPercent = 0,
    this.overheadFixedCents = 0,
    this.marginPercent = 0,
    this.pricingMode = PricingMode.markup,
    this.targetMarginPercent = 30,
    this.fixedPriceCents = 0,
    this.packagingCents = 0,
    this.shippingCents = 0,
    this.storageCents = 0,
    this.returnShippingCents = 0,
    this.buyoutPercent = 100,
    this.commissionPercent = 0,
    this.advertisingPercent = 0,
    this.acquiringPercent = 0,
    this.finishedDefectPercent = 0,
  });

  final int materialsCents;
  final double laborHours;
  final int laborRateCents;
  final int pieceworkCents;
  final int otherCents;
  final double overheadPercent;
  final int overheadFixedCents;
  final double marginPercent;
  final PricingMode pricingMode;
  final double targetMarginPercent;
  final int fixedPriceCents;
  final int packagingCents;
  final int shippingCents;
  final int storageCents;
  final int returnShippingCents;
  final double buyoutPercent;
  final double commissionPercent;
  final double advertisingPercent;
  final double acquiringPercent;
  final double finishedDefectPercent;
}

class CalculatorTotals {
  const CalculatorTotals({
    required this.materialsCents,
    required this.laborCents,
    required this.otherCents,
    required this.overheadCents,
    required this.costCents,
    required this.priceCents,
    required this.validPrice,
    required this.productionCostCents,
    required this.sellingCostCents,
    required this.pieceworkCents,
    required this.finishedDefectCents,
    required this.finishedDefectValid,
    required this.storageCents,
    required this.returnShippingCents,
    required this.buyoutPercent,
    required this.effectiveShippingCents,
    required this.buyoutValid,
    required this.breakEvenCents,
    required this.roiPercent,
    required this.baseCents,
    required this.marginCents,
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
  final int? breakEvenCents;
  final double? roiPercent;
  final int baseCents;
  final int marginCents;
}

int resourceLineTotalCents({
  required double qty,
  required String qtyUnit,
  required int priceCents,
  required String priceUnit,
}) {
  if (qty <= 0 || priceCents == 0) return 0;
  final priceBase = priceBaseOf(priceUnit);
  if (priceBase <= 0) return 0;
  final total = ((qty * qtyBaseOf(qtyUnit)) / priceBase) * priceCents;
  if (!total.isFinite) return 0;
  return total.round();
}

double? effectiveQuantity(double qty, double lossPercent) {
  if (!qty.isFinite || qty < 0) return null;
  if (!lossPercent.isFinite || lossPercent < 0 || lossPercent >= 100) {
    return null;
  }
  final effective = (qty * 100) / (100 - lossPercent);
  return effective.isFinite ? effective : null;
}

CalculatorTotals computeCalculatorTotals(CalculatorInput input) {
  final hours = input.laborHours.isFinite && input.laborHours > 0
      ? input.laborHours
      : 0.0;
  final rate = input.laborRateCents < 0 ? 0 : input.laborRateCents;
  final piecework = input.pieceworkCents < 0 ? 0 : input.pieceworkCents;
  final labor = (hours * rate).round() + piecework;
  final other = input.otherCents < 0 ? 0 : input.otherCents;
  final base = input.materialsCents + labor + other;

  final defectValid = input.finishedDefectPercent.isFinite &&
      input.finishedDefectPercent >= 0 &&
      input.finishedDefectPercent < 100;
  final defectCost = defectValid && input.finishedDefectPercent > 0
      ? (base / (1 - input.finishedDefectPercent / 100)).ceil() - base
      : 0;

  final overheadPct = input.overheadPercent.isFinite && input.overheadPercent > 0
      ? input.overheadPercent
      : 0.0;
  final overheadFixed =
      input.overheadFixedCents < 0 ? 0 : input.overheadFixedCents;
  final overhead = ((base * overheadPct) / 100).round() + overheadFixed;
  final productionCost = base + defectCost + overhead;

  final storage = input.storageCents < 0 ? 0 : input.storageCents;
  final returnCost =
      input.returnShippingCents < 0 ? 0 : input.returnShippingCents;
  final buyoutValid = input.buyoutPercent.isFinite &&
      input.buyoutPercent > 0 &&
      input.buyoutPercent <= 100;
  final buyoutRate = buyoutValid ? input.buyoutPercent / 100 : 1.0;
  final shipping = input.shippingCents < 0 ? 0 : input.shippingCents;
  final effectiveShippingRaw = buyoutValid
      ? (shipping + returnCost * (1 - buyoutRate)) / buyoutRate
      : 0.0;
  final effectiveShipping =
      effectiveShippingRaw.isFinite ? effectiveShippingRaw.ceil() : 0;

  final pkg = input.packagingCents < 0 ? 0 : input.packagingCents;
  final fixedCosts = pkg + effectiveShipping + storage;
  final costsBeforeFees = productionCost + fixedCosts;

  final percentages = [
    input.commissionPercent,
    input.advertisingPercent,
    input.acquiringPercent,
  ];
  final validFees = percentages.every((v) => v.isFinite && v >= 0) &&
      percentages.fold<double>(0, (s, v) => s + v) < 100;
  final feeRate = validFees
      ? percentages.fold<double>(0, (s, v) => s + v) / 100
      : 0.0;

  final marginPct = input.marginPercent.isFinite ? input.marginPercent : 0.0;
  final validMargin = input.pricingMode != PricingMode.targetMargin ||
      (input.targetMarginPercent.isFinite &&
          input.targetMarginPercent >= 0 &&
          input.targetMarginPercent / 100 + feeRate < 1);

  final validPrice = validFees && validMargin && defectValid && buyoutValid;

  int raw = 0;
  if (input.pricingMode == PricingMode.markup) {
    raw = validFees
        ? ((costsBeforeFees * (1 + marginPct / 100)) / (1 - feeRate)).round()
        : 0;
  } else if (input.pricingMode == PricingMode.targetMargin) {
    raw = validPrice
        ? (costsBeforeFees / (1 - feeRate - input.targetMarginPercent / 100))
            .ceil()
        : 0;
  } else {
    raw = input.fixedPriceCents;
  }

  var price = raw < 0 ? 0 : raw;
  if (input.pricingMode == PricingMode.targetMargin &&
      validPrice &&
      feeRate > 0) {
    final fee = (price * feeRate).round();
    final shortfall =
        costsBeforeFees + fee + (price * input.targetMarginPercent) / 100 - price;
    if (shortfall > 0) {
      price += ((shortfall + 0.5) /
              (1 - feeRate - input.targetMarginPercent / 100))
          .ceil();
    }
  }

  final fees = (price * feeRate).round();
  final sellingCosts = fixedCosts + fees;
  final totalCost = productionCost + sellingCosts;
  final breakEvenCents = validPrice && feeRate < 1
      ? (costsBeforeFees / (1 - feeRate)).ceil()
      : null;
  final roiPercent = validPrice && totalCost > 0
      ? ((price - totalCost) / totalCost) * 100
      : null;

  return CalculatorTotals(
    materialsCents: input.materialsCents,
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
    buyoutPercent: input.buyoutPercent,
    effectiveShippingCents: effectiveShipping,
    buyoutValid: buyoutValid,
    breakEvenCents: breakEvenCents,
    roiPercent: roiPercent,
    baseCents: base,
    marginCents: price - totalCost,
  );
}

class CashTotalsResult {
  const CashTotalsResult({
    required this.incomeCents,
    required this.expenseCents,
    required this.netCents,
    required this.reversedIds,
  });

  final int incomeCents;
  final int expenseCents;
  final int netCents;
  final Set<String> reversedIds;
}

CashTotalsResult netCashTotals(List<MoneyTransaction> transactions) {
  final txMap = <String, MoneyTransaction>{};
  final reversedIds = <String>{};
  for (final t in transactions) {
    txMap[t.id] = t;
    if (t.kind == TransactionKind.reversal && t.reversesId != null) {
      reversedIds.add(t.reversesId!);
    }
  }

  var incomeCents = 0;
  var expenseCents = 0;
  for (final t in transactions) {
    if (t.kind == TransactionKind.income) {
      incomeCents += t.amountCents;
    } else if (t.kind == TransactionKind.expense) {
      expenseCents += t.amountCents;
    } else if (t.kind == TransactionKind.reversal) {
      final orig = t.reversesId != null ? txMap[t.reversesId!] : null;
      if (orig?.kind == TransactionKind.expense) {
        expenseCents -= t.amountCents;
      } else {
        incomeCents -= t.amountCents;
      }
    }
  }

  return CashTotalsResult(
    incomeCents: incomeCents,
    expenseCents: expenseCents,
    netCents: incomeCents - expenseCents,
    reversedIds: reversedIds,
  );
}

/// Checks if adding [candidateSubRecipeId] inside [parentRecipeId] would form a cycle.
bool wouldCreateSubRecipeCycle({
  required String parentRecipeId,
  required String candidateSubRecipeId,
  required List<Recipe> allRecipes,
}) {
  if (parentRecipeId.isEmpty || candidateSubRecipeId.isEmpty) return false;
  if (parentRecipeId == candidateSubRecipeId) return true;

  final byId = <String, Recipe>{for (final r in allRecipes) r.id: r};
  final visited = <String>{};
  final queue = <String>[candidateSubRecipeId];

  while (queue.isNotEmpty) {
    final cur = queue.removeAt(0);
    if (cur == parentRecipeId) return true;
    if (!visited.add(cur)) continue;
    final rec = byId[cur];
    if (rec == null) continue;
    for (final line in rec.ingredients) {
      if (line.subRecipeId != null && line.subRecipeId!.isNotEmpty) {
        queue.add(line.subRecipeId!);
      }
    }
  }
  return false;
}
