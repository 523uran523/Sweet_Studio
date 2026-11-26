/// Тип пользовательского параметра: задаёт формат ввода и валидацию значения.
///
/// `entity_attributes` хранит пары ключ-значение и сама по себе не знает,
/// «вес» — это число или текст. Из-за одного и того же ключа в разных заказах
/// появлялись `1.5` и `полтора кг`, и отчёты по параметру рассыпались.
/// Тип отвечает на вопрос «как вводить», поэтому поле в интерфейсе строится
/// по нему, а стор отклоняет значение неподходящего формата.
class AttributeType {
  const AttributeType({
    required this.key,
    required this.valueType,
    required this.entityType,
    this.label = '',
    required this.createdAt,
  });

  /// Ключ параметра (`weight`, `size`, `flavor`) — тот же, что в `key`
  /// у `entity_attributes`.
  final String key;

  /// `text` / `number` / `date`.
  final String valueType;

  /// Для какой сущности описан параметр: `item` / `job` / `client`,
  /// либо `*` — общий для всех.
  final String entityType;

  /// Подпись в интерфейсе («Вес, кг»).
  final String label;

  final DateTime createdAt;

  bool get isUniversal => entityType == '*';

  /// Пустое значение допустимо всегда: параметр необязательный.
  static bool isBlank(String? raw) => raw == null || raw.trim().isEmpty;

  /// Приводит строку из поля ввода к значению атрибута.
  ///
  /// Возвращает `null`, если значение не соответствует типу, — вызывающий код
  /// показывает подсказку вместо записи мусора в базу. Число парится с
  /// запятой как разделителем, потому что так вводят на русской клавиатуре.
  AttributeValue? parse(String? raw) {
    if (isBlank(raw)) return const AttributeValue();
    final trimmed = raw!.trim();
    switch (valueType) {
      case 'number':
        final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
        if (parsed == null) return null;
        return AttributeValue(num: parsed, display: trimmed);
      case 'date':
        if (!_isIsoDate(trimmed)) return null;
        return AttributeValue(text: trimmed, display: trimmed);
      default:
        return AttributeValue(text: trimmed, display: trimmed);
    }
  }

  /// Подсказка формата для поля ввода.
  String get formatHint => switch (valueType) {
    'number' => 'Число',
    'date' => 'ДД.ММ.ГГГГ',
    _ => 'Текст',
  };

  static bool _isIsoDate(String value) {
    // Принимаем дд.мм.гггг — формат, который видит пользователь в полях приложения.
    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(value);
    if (match == null) return false;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return false;
    return true;
  }

  Map<String, Object?> toMap() => {
    'key': key,
    'value_type': valueType,
    'entity_type': entityType,
    'label': label,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory AttributeType.fromMap(Map<String, Object?> m) => AttributeType(
    key: m['key'] as String,
    valueType: m['value_type'] as String? ?? 'text',
    entityType: m['entity_type'] as String? ?? '*',
    label: m['label'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
  );
}

/// Разобранное значение атрибута: что класть в `value_text` / `value_num`.
class AttributeValue {
  const AttributeValue({this.text, this.num, this.display});

  final String? text;
  final double? num;

  /// Как показать значение списком.
  final String? display;

  bool get isEmpty => text == null && num == null;
}
