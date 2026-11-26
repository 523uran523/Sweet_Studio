/// Форматирование денег с учётом валюты и разделителей из настроек.
///
/// Зачем: суммы в интерфейсе собирались вручную (`(cents / 100)
/// .toStringAsFixed(0) + ' ₽'`) в трёх десятках мест. Знак рубля был
/// зашит в строки, поэтому сменить валюту было нельзя, а разное число
/// знаков после запятой в одном экране выглядело ошибкой.
///
/// Формат хранится в одном объекте, который приложение получает из
/// настроек; сам объект неизменяемый, поэтому его можно безопасно
/// передавать в виджеты.
library;

/// Настройки денежного формата: валюта, число знаков, разделители.
class MoneyFormat {
  const MoneyFormat({
    this.symbol = '₽',
    this.decimals = 0,
    this.decimalSeparator = ',',
    this.groupSeparator = ' ',
    this.symbolAfter = true,
  });

  /// Знак валюты, например `₽`, `₸`, `$`.
  final String symbol;

  /// Сколько знаков после запятой показывать (0 — целые суммы).
  final int decimals;

  final String decimalSeparator;
  final String groupSeparator;

  /// Знак после суммы (`1 200 ₽`) или перед ней (`$1 200`).
  final bool symbolAfter;

  static const MoneyFormat rub = MoneyFormat();

  /// Форматирует копейки/центы в строку вида `1 200,50 ₽`.
  String format(int cents) {
    final negative = cents < 0;
    final abs = negative ? -cents : cents;
    final whole = abs ~/ 100;
    final fraction = abs % 100;

    final digits = whole.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(groupSeparator);
      buffer.write(digits[i]);
    }

    final body = StringBuffer();
    if (negative) body.write('−');
    body.write(buffer);
    if (decimals > 0) {
      final frac = decimals == 1
          ? (fraction ~/ 10).toString()
          : fraction.toString().padLeft(2, '0');
      body
        ..write(decimalSeparator)
        ..write(frac);
    }

    final symbolPart = symbol.isEmpty ? '' : symbol;
    if (symbolPart.isEmpty) return body.toString();
    return symbolAfter ? '$body $symbolPart' : '$symbolPart$body';
  }

  /// Сумма без знака валюты — для полей ввода и узких ячеек.
  String amount(int cents) {
    final full = format(cents);
    final symbolPart = symbol.isEmpty ? '' : symbol;
    if (symbolPart.isEmpty) return full;
    return full
        .replaceAll(' $symbolPart', '')
        .replaceAll(symbolPart, '')
        .trim();
  }

  /// Разбирает введённую пользователем сумму в копейки.
  ///
  /// Принимает `1 200`, `1200,50`, `1.200`, `-300`. Возвращает `null`,
  /// если строку не удалось разобрать: вызывающая сторона показывает
  /// ошибку ввода, а не молча подставляет ноль.
  int? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    final negative = text.startsWith('-') || text.startsWith('−');
    text = text.replaceAll(RegExp(r'[-\u2212\s\u00a0]'), '');
    text = text.replaceAll(groupSeparator, '');
    if (symbol.isNotEmpty) text = text.replaceAll(symbol, '');
    if (text.isEmpty) return null;

    final hasComma = text.contains(',');
    final hasDot = text.contains('.');
    if (hasComma && hasDot) {
      // Последний разделитель — десятичный, остальные считаем группой.
      final decimalIndex = text.lastIndexOf(RegExp(r'[.,]'));
      final head = text.substring(0, decimalIndex).replaceAll(RegExp(r'[.,]'), '');
      final tail = text.substring(decimalIndex + 1);
      text = '$head.$tail';
    } else if (hasComma) {
      text = text.replaceAll(',', '.');
    }

    final value = double.tryParse(text);
    if (value == null) return null;
    final cents = (value * 100).round();
    return negative ? -cents : cents;
  }

  MoneyFormat copyWith({
    String? symbol,
    int? decimals,
    String? decimalSeparator,
    String? groupSeparator,
    bool? symbolAfter,
  }) => MoneyFormat(
    symbol: symbol ?? this.symbol,
    decimals: decimals ?? this.decimals,
    decimalSeparator: decimalSeparator ?? this.decimalSeparator,
    groupSeparator: groupSeparator ?? this.groupSeparator,
    symbolAfter: symbolAfter ?? this.symbolAfter,
  );

  @override
  bool operator ==(Object other) =>
      other is MoneyFormat &&
      other.symbol == symbol &&
      other.decimals == decimals &&
      other.decimalSeparator == decimalSeparator &&
      other.groupSeparator == groupSeparator &&
      other.symbolAfter == symbolAfter;

  @override
  int get hashCode => Object.hash(
    symbol,
    decimals,
    decimalSeparator,
    groupSeparator,
    symbolAfter,
  );
}

/// Формат, которым сейчас пользуется приложение.
///
/// Значение выставляет `SettingsController` при загрузке и при смене
/// валюты. Глобальное состояние здесь оправдано: суммы печатаются в
/// десятках виджетов, у которых нет доступа к настройкам (диалоги,
/// строки списков, документы), а прокидывать контроллер в каждый
/// было бы дороже, чем одна точка обновления.
MoneyFormat currentMoneyFormat = MoneyFormat.rub;

/// Короткий доступ к форматированию суммы для виджетов.
String money(int cents) => currentMoneyFormat.format(cents);

/// Знак текущей валюты — для полей ввода и подписей.
String get moneySymbol => currentMoneyFormat.symbol;
