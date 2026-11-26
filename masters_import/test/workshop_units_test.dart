// Тесты перевода единиц измерения workshop-прототипа.
//
// Покрывают:
//  * новые единицы: мг, мм, см², дм²;
//  * базовые меры и цены («за ...»);
//  * несовместимые размерности (масса/длина/площадь/объём);
//  * старые (legacy) переводы, которые не должны сломаться.
//
// Импорт относительный, чтобы тест собирался независимо от имени пакета.
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/units.dart';

void main() {
  group('convertQty — новые единицы', () {
    test('мг → кг (база массы — кг)', () {
      expect(convertQty(1, 'мг', 'кг'), closeTo(0.000001, 1e-12));
      expect(convertQty(1000000, 'мг', 'кг'), closeTo(1, 1e-9));
      expect(convertQty(500, 'мг', 'кг'), closeTo(0.0005, 1e-12));
    });

    test('кг → мг', () {
      expect(convertQty(1, 'кг', 'мг'), closeTo(1000000, 1e-6));
      expect(convertQty(0.5, 'кг', 'мг'), closeTo(500000, 1e-6));
    });

    test('мг ↔ г', () {
      expect(convertQty(1000, 'мг', 'г'), closeTo(1, 1e-9));
      expect(convertQty(1, 'г', 'мг'), closeTo(1000, 1e-6));
    });

    test('мм → м (база длины — м)', () {
      expect(convertQty(1, 'мм', 'м'), closeTo(0.001, 1e-12));
      expect(convertQty(1000, 'мм', 'м'), closeTo(1, 1e-9));
    });

    test('м → мм', () {
      expect(convertQty(1, 'м', 'мм'), closeTo(1000, 1e-6));
    });

    test('мм ↔ см', () {
      expect(convertQty(10, 'мм', 'см'), closeTo(1, 1e-9));
      expect(convertQty(1, 'см', 'мм'), closeTo(10, 1e-9));
    });

    test('см² → м² (база площади — м²)', () {
      expect(convertQty(1, 'см²', 'м²'), closeTo(0.0001, 1e-12));
      expect(convertQty(10000, 'см²', 'м²'), closeTo(1, 1e-9));
    });

    test('дм² → м²', () {
      expect(convertQty(1, 'дм²', 'м²'), closeTo(0.01, 1e-12));
      expect(convertQty(100, 'дм²', 'м²'), closeTo(1, 1e-9));
    });

    test('дм² ↔ см²', () {
      expect(convertQty(1, 'дм²', 'см²'), closeTo(100, 1e-6));
      expect(convertQty(100, 'см²', 'дм²'), closeTo(1, 1e-9));
    });

    test('round-trip не теряет значение', () {
      expect(convertQty(convertQty(1234.5, 'мг', 'кг')!, 'кг', 'мг'),
          closeTo(1234.5, 1e-6));
      expect(convertQty(convertQty(42, 'мм', 'м')!, 'м', 'мм'),
          closeTo(42, 1e-9));
    });

    test('одинаковая единица возвращает значение как есть', () {
      expect(convertQty(7.25, 'мг', 'мг'), 7.25);
      expect(convertQty(7.25, 'см²', 'см²'), 7.25);
    });
  });

  group('qtyBaseOf — базовые меры', () {
    test('мг → 0.000001 кг', () {
      expect(qtyBaseOf('мг'), closeTo(0.000001, 1e-12));
    });
    test('мм → 0.001 м', () {
      expect(qtyBaseOf('мм'), closeTo(0.001, 1e-12));
    });
    test('см² → 0.0001 м²', () {
      expect(qtyBaseOf('см²'), closeTo(0.0001, 1e-12));
    });
    test('дм² → 0.01 м²', () {
      expect(qtyBaseOf('дм²'), closeTo(0.01, 1e-12));
    });
  });

  group('priceBaseOf — база цены для новых единиц', () {
    test('за мг → 0.000001 кг', () {
      expect(priceBaseOf('за мг'), closeTo(0.000001, 1e-12));
    });
    test('за мм → 0.001 м', () {
      expect(priceBaseOf('за мм'), closeTo(0.001, 1e-12));
    });
    test('за см² → 0.0001 м²', () {
      expect(priceBaseOf('за см²'), closeTo(0.0001, 1e-12));
    });
    test('за дм² → 0.01 м²', () {
      expect(priceBaseOf('за дм²'), closeTo(0.01, 1e-12));
    });
  });

  group('defaultPriceUnit — новые единицы', () {
    test('мг → за мг', () => expect(defaultPriceUnit('мг'), 'за мг'));
    test('мм → за мм', () => expect(defaultPriceUnit('мм'), 'за мм'));
    test('см² → за см²', () => expect(defaultPriceUnit('см²'), 'за см²'));
    test('дм² → за дм²', () => expect(defaultPriceUnit('дм²'), 'за дм²'));
  });

  group('priceUnitsFor — совместимые цены', () {
    test('масса содержит мг и базовые', () {
      final units = priceUnitsFor('мг');
      expect(units, contains('за мг'));
      expect(units, contains('за г'));
      expect(units, contains('за 100 г'));
      expect(units, contains('за кг'));
    });
    test('длина содержит мм', () {
      final units = priceUnitsFor('мм');
      expect(units, contains('за мм'));
      expect(units, contains('за см'));
      expect(units, contains('за м'));
    });
    test('площадь содержит см² и дм²', () {
      final units = priceUnitsFor('см²');
      expect(units, contains('за см²'));
      expect(units, contains('за дм²'));
      expect(units, contains('за м²'));
    });
  });

  group('несовместимые размерности', () {
    test('мг (масса) не переводится в мм (длина)', () {
      expect(convertQty(1, 'мг', 'мм'), isNull);
      expect(unitsCompatible('мг', 'мм'), isFalse);
    });
    test('см² (площадь) не переводится в м (длина)', () {
      expect(convertQty(1, 'см²', 'м'), isNull);
      expect(unitsCompatible('см²', 'м'), isFalse);
    });
    test('дм² (площадь) не переводится в л (объём)', () {
      expect(convertQty(1, 'дм²', 'л'), isNull);
      expect(unitsCompatible('дм²', 'л'), isFalse);
    });
    test('мг (масса) не переводится в шт (счёт)', () {
      expect(convertQty(1, 'мг', 'шт'), isNull);
      expect(unitsCompatible('мг', 'шт'), isFalse);
    });
  });

  group('convertQty — время (база — минуты)', () {
    test('ч → мин', () {
      expect(convertQty(1, 'ч', 'мин'), closeTo(60, 1e-9));
      expect(convertQty(1.5, 'ч', 'мин'), closeTo(90, 1e-9));
    });
    test('мин → ч', () {
      expect(convertQty(60, 'мин', 'ч'), closeTo(1, 1e-9));
      expect(convertQty(90, 'мин', 'ч'), closeTo(1.5, 1e-9));
    });
    test('сек → мин', () {
      expect(convertQty(60, 'сек', 'мин'), closeTo(1, 1e-9));
      expect(convertQty(30, 'сек', 'мин'), closeTo(0.5, 1e-9));
    });
    test('мин → сек', () {
      expect(convertQty(1, 'мин', 'сек'), closeTo(60, 1e-6));
      expect(convertQty(2, 'мин', 'сек'), closeTo(120, 1e-6));
    });
    test('ч ↔ сек', () {
      expect(convertQty(1, 'ч', 'сек'), closeTo(3600, 1e-6));
      expect(convertQty(3600, 'сек', 'ч'), closeTo(1, 1e-9));
    });
    test('round-trip не теряет значение', () {
      expect(convertQty(convertQty(45, 'ч', 'сек')!, 'сек', 'ч'),
          closeTo(45, 1e-9));
      expect(convertQty(convertQty(7.5, 'мин', 'сек')!, 'сек', 'мин'),
          closeTo(7.5, 1e-9));
    });
  });

  group('convertQty — энергия (база — кВт·ч)', () {
    test('кВт·ч → кВт·ч', () {
      expect(convertQty(2.5, 'кВт·ч', 'кВт·ч'), closeTo(2.5, 1e-12));
    });
    test('кВт·ч в базовой мере', () {
      expect(convertQty(1, 'кВт·ч', 'кВт·ч'), closeTo(1, 1e-12));
      expect(convertQty(3, 'кВт·ч', 'кВт·ч'), closeTo(3, 1e-12));
    });
  });

  group('время/энергия — отдельные семейства', () {
    test('unitFamily', () {
      expect(unitFamily('сек'), UnitFamily.time);
      expect(unitFamily('мин'), UnitFamily.time);
      expect(unitFamily('ч'), UnitFamily.time);
      expect(unitFamily('кВт·ч'), UnitFamily.energy);
    });
    test('время не переводится в энергию', () {
      expect(convertQty(1, 'ч', 'кВт·ч'), isNull);
      expect(unitsCompatible('ч', 'кВт·ч'), isFalse);
      expect(convertQty(1, 'кВт·ч', 'мин'), isNull);
      expect(unitsCompatible('кВт·ч', 'мин'), isFalse);
    });
    test('время не переводится в счёт', () {
      expect(convertQty(1, 'мин', 'шт'), isNull);
      expect(unitsCompatible('мин', 'шт'), isFalse);
      expect(convertQty(1, 'шт', 'ч'), isNull);
    });
    test('энергия не переводится в массу', () {
      expect(convertQty(1, 'кВт·ч', 'кг'), isNull);
      expect(unitsCompatible('кВт·ч', 'кг'), isFalse);
    });
  });

  group('qtyBaseOf — время и энергия', () {
    test('сек → 1/60 мин', () {
      expect(qtyBaseOf('сек'), closeTo(1 / 60, 1e-12));
    });
    test('мин → 1 мин', () {
      expect(qtyBaseOf('мин'), 1);
    });
    test('ч → 60 мин', () {
      expect(qtyBaseOf('ч'), 60);
    });
    test('кВт·ч → 1 кВт·ч', () {
      expect(qtyBaseOf('кВт·ч'), 1);
    });
  });

  group('priceBaseOf — база цены для времени и энергии', () {
    test('за сек → 1/60 мин', () {
      expect(priceBaseOf('за сек'), closeTo(1 / 60, 1e-12));
    });
    test('за мин → 1 мин', () {
      expect(priceBaseOf('за мин'), 1);
    });
    test('за ч → 60 мин', () {
      expect(priceBaseOf('за ч'), 60);
    });
    test('за кВт·ч → 1 кВт·ч', () {
      expect(priceBaseOf('за кВт·ч'), 1);
    });
  });

  group('defaultPriceUnit — время и энергия', () {
    test('сек → за сек', () => expect(defaultPriceUnit('сек'), 'за сек'));
    test('мин → за мин', () => expect(defaultPriceUnit('мин'), 'за мин'));
    test('ч → за ч', () => expect(defaultPriceUnit('ч'), 'за ч'));
    test('кВт·ч → за кВт·ч',
        () => expect(defaultPriceUnit('кВт·ч'), 'за кВт·ч'));
  });

  group('priceUnitsFor — время и энергия', () {
    test('время содержит сек/мин/ч', () {
      final units = priceUnitsFor('сек');
      expect(units, contains('за сек'));
      expect(units, contains('за мин'));
      expect(units, contains('за ч'));
      expect(units, isNot(contains('за шт')));
    });
    test('энергия содержит только кВт·ч', () {
      expect(priceUnitsFor('кВт·ч'), ['за кВт·ч']);
    });
    test('время не пересекается с массой', () {
      expect(priceUnitsFor('мин'), isNot(contains('за кг')));
    });
  });

  group('legacy-переводы не сломаны', () {
    test('кг ↔ г', () {
      expect(convertQty(1, 'кг', 'г'), closeTo(1000, 1e-9));
      expect(convertQty(1000, 'г', 'кг'), closeTo(1, 1e-9));
    });
    test('м ↔ см', () {
      expect(convertQty(1, 'м', 'см'), closeTo(100, 1e-9));
      expect(convertQty(100, 'см', 'м'), closeTo(1, 1e-9));
    });
    test('л ↔ мл', () {
      expect(convertQty(1, 'л', 'мл'), closeTo(1000, 1e-6));
      expect(convertQty(1000, 'мл', 'л'), closeTo(1, 1e-9));
    });
    test('старая база цены', () {
      expect(priceBaseOf('за г'), closeTo(0.001, 1e-12));
      expect(priceBaseOf('за 100 г'), closeTo(0.1, 1e-12));
      expect(priceBaseOf('за кг'), 1);
      expect(priceBaseOf('за см'), closeTo(0.01, 1e-12));
      expect(priceBaseOf('за м²'), 1);
    });
    test('старые unitFamily', () {
      expect(unitFamily('г'), UnitFamily.mass);
      expect(unitFamily('кг'), UnitFamily.mass);
      expect(unitFamily('см'), UnitFamily.length);
      expect(unitFamily('м²'), UnitFamily.area);
      expect(unitFamily('м2'), UnitFamily.area);
    });
  });

  group('счёт / упаковка / услуга сохраняют семантику', () {
    test('шт', () {
      expect(unitFamily('шт'), UnitFamily.count);
      expect(defaultPriceUnit('шт'), 'за шт');
      expect(priceUnitsFor('шт'), ['за шт']);
      expect(priceBaseOf('за шт'), 1);
    });
    test('упак', () {
      expect(unitFamily('упак'), UnitFamily.count);
      expect(defaultPriceUnit('упак'), 'за упак');
      expect(priceUnitsFor('упак'), ['за упак']);
      expect(priceBaseOf('за упак'), 1);
    });
    test('услуга', () {
      expect(unitFamily('услуга'), UnitFamily.count);
      expect(defaultPriceUnit('услуга'), 'за услугу');
      expect(priceUnitsFor('услуга'), ['за услугу']);
      expect(priceBaseOf('за услугу'), 1);
    });
  });

  group('списки опций содержат новые единицы и не дублируются', () {
    test('kUnitOptions', () {
      expect(kUnitOptions, contains('мг'));
      expect(kUnitOptions, contains('мм'));
      expect(kUnitOptions, contains('см²'));
      expect(kUnitOptions, contains('дм²'));
      expect(kUnitOptions, contains('сек'));
      expect(kUnitOptions, contains('мин'));
      expect(kUnitOptions, contains('ч'));
      expect(kUnitOptions, contains('кВт·ч'));
      expect(kUnitOptions.toSet().length, kUnitOptions.length);
    });
    test('kQtyUnits', () {
      expect(kQtyUnits, contains('мг'));
      expect(kQtyUnits, contains('мм'));
      expect(kQtyUnits, contains('см²'));
      expect(kQtyUnits, contains('дм²'));
      expect(kQtyUnits, contains('сек'));
      expect(kQtyUnits, contains('мин'));
      expect(kQtyUnits, contains('ч'));
      expect(kQtyUnits, contains('кВт·ч'));
      expect(kQtyUnits.toSet().length, kQtyUnits.length);
    });
    test('kPriceUnits', () {
      expect(kPriceUnits, contains('за мг'));
      expect(kPriceUnits, contains('за мм'));
      expect(kPriceUnits, contains('за см²'));
      expect(kPriceUnits, contains('за дм²'));
      expect(kPriceUnits, contains('за сек'));
      expect(kPriceUnits, contains('за мин'));
      expect(kPriceUnits, contains('за ч'));
      expect(kPriceUnits, contains('за кВт·ч'));
      expect(kPriceUnits.toSet().length, kPriceUnits.length);
    });
  });
}