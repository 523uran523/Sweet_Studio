/// Единицы измерения, общие для склада, состава стоимости и калькулятора.
///
/// Все значения хранятся как строки, чтобы пользователь мог задать свою
/// единицу («упак», «услуга» и т.п.). Для известных единиц работает перевод
/// внутри одной «семьи» (масса, объём, длина, площадь, время, энергия).
library;

const List<String> kUnitOptions = [
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
  'услуга',
];

/// Единицы, в которых можно указать количество в калькуляторе.
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
];

/// Единицы цены («цена за ...»).
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

enum UnitFamily { count, mass, volume, length, area, time, energy, other }

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

/// Базовые меры: кг, л, м, м², шт; время — минуты, энергия — кВт·ч.
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

/// Базовая мера единицы (кг, л, м, м², шт) — для расчёта стоимости строки.
double qtyBaseOf(String unit) => _toBase[unit] ?? 1;

/// Единица цены «за ...» → базовая мера (например, «за 100 г» → 0.1 кг).
double priceBaseOf(String priceUnit) {
  switch (priceUnit) {
    case 'за шт':
    case 'за упак':
    case 'за услугу':
    case 'за кг':
    case 'за л':
    case 'за м':
    case 'за м²':
      return 1;
    case 'за мг':
      return 0.000001;
    case 'за г':
      return 0.001;
    case 'за 100 г':
      return 0.1;
    case 'за мм':
      return 0.001;
    case 'за см':
      return 0.01;
    case 'за мл':
      return 0.001;
    case 'за см²':
      return 0.0001;
    case 'за дм²':
      return 0.01;
    case 'за сек':
      return 1 / 60;
    case 'за мин':
      return 1;
    case 'за ч':
      return 60;
    case 'за кВт·ч':
      return 1;
    default:
      return 1;
  }
}

bool unitsCompatible(String a, String b) {
  final family = unitFamily(a);
  return family != UnitFamily.other && family == unitFamily(b);
}

/// Переводит [value] из единицы [from] в [to].
/// Возвращает `null`, если единицы несовместимы.
double? convertQty(double value, String from, String to) {
  if (from == to) return value;
  if (!unitsCompatible(from, to)) return null;
  final source = _toBase[from];
  final target = _toBase[to];
  if (source == null || target == null || target == 0) return null;
  return value * source / target;
}

/// Единица цены по умолчанию для единицы количества.
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

/// Доступные единицы цены для единицы количества.
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
      return qtyUnit == 'упак'
          ? const ['за упак']
          : (qtyUnit == 'услуга'
                ? const ['за услугу']
                : const ['за шт']);
    case UnitFamily.other:
      return kPriceUnits;
  }
}

/// Компактная запись количества: без лишних нулей.
String formatQty(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  if (value % 1 == 0) return value.toInt().toString();
  final fixed = value.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
