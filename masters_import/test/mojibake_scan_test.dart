import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Multi-character signature patterns that indicate double CP866/CP1251 encoding.
// Single characters (e.g. '║') can appear legitimately in clean UI (₽, →, etc.)
// so we require context: at least 2 sequential artifact chars or a prefix + Cyrillic.
// CP1252 double-encoding: multi-char patterns like 'Рћ', 'С‚', 'Рє', 'Сѓ', 'Рё', 'Рѕ', 'РЅ', 'РІ'.
const List<String> _mojibakeSignaturesCp1252 = <String>[
  'Рћ',
  'С‚',
  'Рє',
  'Сѓ',
  'Рё',
  'Рѕ',
  'РЅ',
  'РІ',
  'РЈ',
  'РЎ',
  'Рё',
  'Р�',
  'Рє',
  'Рѕ',
  'Рі',
  'Рї',
  'Рј',
  'Рћ',
  'Р›',
  'РЅ',
  'РІ',
  'Р°',
  'Р±',
  'Рµ',
  'Р¶',
  'Р·',
  'Р»',
  'Рј',
  'Рї',
  'Рі',
  'Рґ',
  'Р—',
  'Р№',
  'СЃ',
  'СЊ',
  'СЋ',
  'СЏ',
  'Р°',
  'Р±',
  'Рµ',
  'Р¶',
  'Р·',
  'Р»',
  'Рј',
  'Рї',
  'Рі',
  'Рґ',
  'Р—',
  'Р№',
  'СЃ',
  'СЊ',
  'СЋ',
  'СЏ',
  'Сѓ',
  'С‘',
  'С€',
  'С€',
  'Р№',
  'СЏ',
  'Сѓ',
  'С‘',
  'С†',
  'С‡',
  'С…',
  'С‰',
  'С‹',
];

bool _textHasMojibake(String text) {
  // Use regexes for multi-char patterns to avoid single-char false positives.
  // CP1252: any of the multi-char signatures.
  for (final sig in _mojibakeSignaturesCp1252) {
    if (text.contains(sig)) return true;
  }
  // CP866: require at least 2 consecutive box chars, OR box + Cyrillic prefix.
  // This filters out single '₽' (₽), '→', '↩' which use box chars in isolation.
  final cp866Pattern = RegExp(r'[╨╩╪╫╬╭╮╯╰║╤╥╦╧]{2,}');
  if (cp866Pattern.hasMatch(text)) return true;
  // Multi-char Cyrillic prefix combos: тХ, тА, тБ, тГ, тД, тЕ, тЖ, тФ, тАв
  final prefixPattern = RegExp(r'т[ХАБГДЕЖФ][иА-Яё]?|тАв');
  if (prefixPattern.hasMatch(text)) return true;
  // CP866 single-box residue: a box-drawing glyph (U+2500-U+257F) glued to a
  // Cyrillic letter (e.g. '×' corrupted to U+251C U+0427) never occurs in clean
  // Russian/English UI text. Keyed on adjacency so isolated box separators
  // ('║' rules, '─' dividers) that are NOT next to a letter are still allowed.
  final boxCyrillicPattern = RegExp(
    r'[\u2500-\u257F][\u0400-\u04FF]|[\u0400-\u04FF][\u2500-\u257F]',
  );
  if (boxCyrillicPattern.hasMatch(text)) return true;
  return false;
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(followLinks: false)) {
    if (e is Directory)
      yield* _dartFiles(e);
    else if (e is File && e.path.endsWith('.dart'))
      yield e;
  }
}

String _readUtf8(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final u16 = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      u16.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(u16);
  }
  return utf8.decode(bytes);
}

void main() {
  test('lib contains no mojibake (double-encoded Cyrillic)', () {
    final problems = <String>[];
    final libDir = Directory('lib');
    for (final f in _dartFiles(libDir)) {
      final text = _readUtf8(f);
      if (_textHasMojibake(text)) {
        problems.add('${f.path}: Mojibake detected');
      }
    }
    expect(
      problems,
      isEmpty,
      reason: 'Found mojibake in: ${problems.join(", ")}',
    );
  });
}
