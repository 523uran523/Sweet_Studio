import 'package:flutter_test/flutter_test.dart';
import 'package:masters/core/text_encoding.dart';

// Literals below are the exact strings that old builds wrote into the
// database (double-encoded UTF-8 read back as CP1251). They are written with
// escapes on purpose: the repository itself must stay free of mojibake.

/// 'Основной' corrupted once through CP1251.
const String brokenResource =
    '\u0420\u045B\u0421\u0403\u0420\u0405\u0420\u0455\u0420\u0406\u0420\u0405\u0420\u0455\u0420\u2116';

/// 'Наличные' corrupted once through CP1251.
const String brokenCash =
    '\u0420\u045C\u0420\u00B0\u0420\u00BB\u0420\u0451\u0421\u2021\u0420\u0405\u0421\u2039\u0420\u00B5';

/// 'Перевод' corrupted once through CP1251.
const String brokenTransfer =
    '\u0420\u045F\u0420\u00B5\u0421\u0402\u0420\u00B5\u0420\u0406\u0420\u0455\u0420\u0491';

void main() {
  group('repairMojibake', () {
    test('restores the historic seeded resource name', () {
      expect(repairMojibake(brokenResource), 'Основной');
    });

    test('restores corrupted account and category names', () {
      expect(repairMojibake(brokenCash), 'Наличные');
      expect(repairMojibake(brokenTransfer), 'Перевод');
    });

    test('restores text mixed with ASCII', () {
      expect(repairMojibake('$brokenResource 5W-40'), 'Основной 5W-40');
    });

    test('leaves clean Russian text untouched', () {
      for (final clean in <String>[
        'Основной',
        'Наличные',
        'Перевод',
        'Масло моторное 5W-40',
        'Колесные тормозные передние',
        'Диагностика',
        'Иван',
        'Демо-поставщик',
        'Смена кассы',
        'Всего',
        'Клиент',
        'ОК',
        'Объект, адрес',
        '12345',
        '',
        'Прайс-лист № 7',
      ]) {
        expect(repairMojibake(clean), clean, reason: 'changed: $clean');
      }
    });

    test('does not invent data for undecodable garbage', () {
      // Box-drawing residue that does not map back to valid UTF-8 stays as is.
      const junk = '\u2591\u2592\u2593 abc';
      expect(repairMojibake(junk), junk);
      expect(repairMojibake('abc'), 'abc');
    });

    test('peels off several corruption layers', () {
      // 'Основной' corrupted twice through CP1251.
      const twice =
          '\u0420\u00A0\u0421\u203A\u0420\u040E\u0420\u0453\u0420\u00A0'
          '\u0420\u2026\u0420\u00A0\u0421\u2022\u0420\u00A0\u0420\u2020'
          '\u0420\u00A0\u0420\u2026\u0420\u00A0\u0421\u2022\u0420\u00A0'
          '\u0432\u201E\u2013';
      expect(repairMojibake(twice), 'Основной');
    });

    test('never returns a still-corrupted string', () {
      const corrupted = brokenResource;
      final result = repairMojibake(corrupted);
      final residue = result.runes.any(
        (cp) =>
            cp >= 0x0400 &&
            cp <= 0x04FF &&
            !(cp >= 0x0410 && cp <= 0x044F) &&
            cp != 0x0401 &&
            cp != 0x0451,
      );
      expect(residue, isFalse, reason: 'residue left in $result');
    });

    test('leaves replacement characters alone', () {
      const damaged = 'Основ\uFFFDой';
      expect(repairMojibake(damaged), damaged);
    });
  });
}
