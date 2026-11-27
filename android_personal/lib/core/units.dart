enum UnitFamily {
  count,
  mass,
  volume,
  length,
  area,
  time,
  energy,
  other,
}

const List<String> kQtyUnits = [
  'шт',
  'г',
  'мг',
  'кг',
  'мл',
  'л',
  'см',
  'мм',
  'м',
  'см²',
  'дм²',
  'м²',
  'сек',
  'мин',
  'ч',
  'кВт·ч',
  'упак',
];

const List<String> kPriceUnits = [
  'за шт',
  'за г',
  'за 100 г',
  'за мг',
  'за кг',
  'за мл',
  'за л',
  'за см',
  'за мм',
  'за м',
  'за см²',
  'за дм²',
  'за м²',
  'за сек',
  'за мин',
  'за ч',
  'за кВт·ч',
  'за упак',
  'за услугу',
];

UnitFamily unitFamily(String unit) {
  switch (unit.trim().toLowerCase()) {
    case 'шт':
    case 'упак':
    case 'услуга':
      return UnitFamily.count;
    case 'г':
    case 'мг':
    case 'кг':
      return UnitFamily.mass;
    case 'мл':
    case 'л':
      return UnitFamily.volume;
    case 'см':
    case 'мм':
    case 'м':
      return UnitFamily.length;
    case 'см²':
    case 'см2':
    case 'дм²':
    case 'дм2':
    case 'м²':
    case 'м2':
      return UnitFamily.area;
    case 'сек':
    case 'мин':
    case 'ч':
      return UnitFamily.time;
    case 'квт·ч':
      return UnitFamily.energy;
    default:
      return UnitFamily.other;
  }
}

const Map<String, double> _toBase = {
  'шт': 1,
  'упак': 1,
  'услуга': 1,
  'мг': 0.000001,
  'г': 0.001,
  'кг': 1,
  'мл': 0.001,
  'л': 1,
  'мм': 0.001,
  'см': 0.01,
  'м': 1,
  'см²': 0.0001,
  'см2': 0.0001,
  'дм²': 0.01,
  'дм2': 0.01,
  'м²': 1,
  'м2': 1,
  'сек': 1 / 60,
  'мин': 1,
  'ч': 60,
  'кВт·ч': 1,
  'квт·ч': 1,
};

double qtyBaseOf(String unit) => _toBase[unit] ?? 1;

double priceBaseOf(String priceUnit) {
  switch (priceUnit) {
    case 'за шт':
    case 'за упак':
    case 'за услугу':
    case 'за кг':
    case 'за л':
    case 'за м':
    case 'за м²':
    case 'за кВт·ч':
    case 'за мин':
      return 1;
    case 'за мг':
      return 0.000001;
    case 'за г':
    case 'за мл':
    case 'за мм':
      return 0.001;
    case 'за 100 г':
      return 0.1;
    case 'за см':
    case 'за дм²':
      return 0.01;
    case 'за см²':
      return 0.0001;
    case 'за сек':
      return 1 / 60;
    case 'за ч':
      return 60;
    default:
      return 1;
  }
}

bool unitsCompatible(String a, String b) {
  final fam = unitFamily(a);
  return fam != UnitFamily.other && fam == unitFamily(b);
}

double? convertQty(double value, String from, String to) {
  if (from == to) return value;
  if (!unitsCompatible(from, to)) return null;
  final source = _toBase[from];
  final target = _toBase[to];
  if (source == null || target == null || target == 0) return null;
  return (value * source) / target;
}

double? convertQtyWithDensity(
  double value,
  String from,
  String to, {
  double? densityGPerMl,
}) {
  final direct = convertQty(value, from, to);
  if (direct != null) return direct;
  if (densityGPerMl == null || !densityGPerMl.isFinite || densityGPerMl <= 0) {
    return null;
  }
  final fFrom = unitFamily(from);
  final fTo = unitFamily(to);
  if (fFrom == UnitFamily.mass && fTo == UnitFamily.volume) {
    final grams = convertQty(value, from, 'г');
    if (grams == null) return null;
    final ml = grams / densityGPerMl;
    return convertQty(ml, 'мл', to);
  }
  if (fFrom == UnitFamily.volume && fTo == UnitFamily.mass) {
    final ml = convertQty(value, from, 'мл');
    if (ml == null) return null;
    final grams = ml * densityGPerMl;
    return convertQty(grams, 'г', to);
  }
  return null;
}

String defaultPriceUnit(String qtyUnit) {
  switch (qtyUnit) {
    case 'г':
      return 'за г';
    case 'мг':
      return 'за мг';
    case 'кг':
      return 'за кг';
    case 'мл':
      return 'за мл';
    case 'л':
      return 'за л';
    case 'см':
      return 'за см';
    case 'мм':
      return 'за мм';
    case 'м':
      return 'за м';
    case 'см²':
      return 'за см²';
    case 'дм²':
      return 'за дм²';
    case 'м²':
      return 'за м²';
    case 'сек':
      return 'за сек';
    case 'мин':
      return 'за мин';
    case 'ч':
      return 'за ч';
    case 'кВт·ч':
      return 'за кВт·ч';
    case 'упак':
      return 'за упак';
    case 'услуга':
      return 'за услугу';
    default:
      return 'за шт';
  }
}

List<String> priceUnitsFor(String qtyUnit) {
  switch (unitFamily(qtyUnit)) {
    case UnitFamily.mass:
      return const ['за мг', 'за г', 'за 100 г', 'за кг'];
    case UnitFamily.volume:
      return const ['за мл', 'за л'];
    case UnitFamily.length:
      return const ['за мм', 'за см', 'за м'];
    case UnitFamily.area:
      return const ['за см²', 'за дм²', 'за м²'];
    case UnitFamily.time:
      return const ['за сек', 'за мин', 'за ч'];
    case UnitFamily.energy:
      return const ['за кВт·ч'];
    case UnitFamily.count:
      if (qtyUnit == 'упак') return const ['за упак'];
      if (qtyUnit == 'услуга') return const ['за услугу'];
      return const ['за шт'];
    case UnitFamily.other:
      return kPriceUnits;
  }
}

String formatQty(double value, [String? unit]) {
  if (!value.isFinite) return '0';
  final rounded = (value * 1000).round() / 1000;
  final formatted = rounded % 1 == 0
      ? rounded.toInt().toString()
      : rounded
          .toStringAsFixed(3)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  final comma = formatted.replaceAll('.', ',');
  return unit != null && unit.isNotEmpty ? '$comma $unit' : comma;
}
