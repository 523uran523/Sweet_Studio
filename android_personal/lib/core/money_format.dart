import 'dart:math';

String _ruPlural(int n, String one, String few, String many) {
  final absN = n.abs() % 100;
  final mod10 = absN % 10;
  if (absN > 10 && absN < 20) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

String pluralOrders(int n) => '$n ${_ruPlural(n, 'заказ', 'заказа', 'заказов')}';
String pluralItems(int n) => '$n ${_ruPlural(n, 'позиция', 'позиции', 'позиций')}';
String pluralTasks(int n) => '$n ${_ruPlural(n, 'задача', 'задачи', 'задач')}';
String pluralDays(int n) => '$n ${_ruPlural(n, 'день', 'дня', 'дней')}';
String pluralMinutes(int n) => '$n ${_ruPlural(n, 'минута', 'минуты', 'минут')}';
String pluralPhotos(int n) => '$n ${_ruPlural(n, 'фотография', 'фотографии', 'фотографий')}';

String formatMoneyCents(
  int cents, {
  bool hide = false,
  String currencySymbol = '₽',
  bool showDecimalsIfNeeded = true,
}) {
  if (hide) return '••• $currencySymbol';
  final sign = cents < 0 ? '-' : '';
  final absCents = cents.abs();
  final rubles = absCents ~/ 100;
  final kop = absCents % 100;
  final rubStr = _formatIntWithThinSpaces(rubles);
  if (kop == 0 || !showDecimalsIfNeeded) {
    return '$sign$rubStr $currencySymbol';
  }
  final kopStr = kop.toString().padLeft(2, '0');
  return '$sign$rubStr,$kopStr $currencySymbol';
}

String _formatIntWithThinSpaces(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) {
      buf.write('\u00A0');
    }
    buf.write(s[i]);
  }
  return buf.toString();
}

int parseRubToCents(String raw) {
  final normalized = raw
      .trim()
      .replaceAll('\u00A0', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (normalized.isEmpty) return 0;
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) return 0;
  return (parsed * 100).round();
}

String centsToRubInput(int cents) {
  if (cents == 0) return '0';
  final kop = cents.abs() % 100;
  if (kop == 0) return (cents ~/ 100).toString();
  return (cents / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String newId([String prefix = 'id']) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = Random().nextInt(0x3FFFFFFF).toRadixString(36);
  return '${prefix}_${ts}_$rand';
}

String todayIsoDate([DateTime? now]) {
  final d = now ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String addDaysIso(String isoDate, int days) {
  final parts = isoDate.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null) {
      final dt = DateTime.utc(y, m, d + days);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }
  final dt = DateTime.now().add(Duration(days: days));
  return todayIsoDate(dt);
}
