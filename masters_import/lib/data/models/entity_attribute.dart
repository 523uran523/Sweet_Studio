/// Атрибут сущности: параметр изделия, свойство заказа или клиента.
///
/// Одна таблица вместо отдельных колонок под каждый параметр: код не знает
/// слов «вес», «вкус», «аллергия» — он знает только пары ключ-значение.
/// Такой подход переживает появление новых параметров без миграции схемы.
class EntityAttribute {
  const EntityAttribute({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.key,
    this.valueText,
    this.valueNum,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// item / job / client.
  final String entityType;

  final String entityId;
  final String key;
  final String? valueText;
  final double? valueNum;
  final double sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  EntityAttribute copyWith({
    String? id,
    String? entityType,
    String? entityId,
    String? key,
    Object? valueText = _unset,
    Object? valueNum = _unset,
    double? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => EntityAttribute(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    key: key ?? this.key,
    valueText: valueText == _unset ? this.valueText : valueText as String?,
    valueNum: valueNum == _unset ? this.valueNum : valueNum as double?,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'entity_type': entityType,
    'entity_id': entityId,
    'key': key,
    'value_text': valueText,
    'value_num': valueNum,
    'sort_order': sortOrder,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory EntityAttribute.fromMap(Map<String, Object?> m) => EntityAttribute(
    id: m['id'] as String,
    entityType: m['entity_type'] as String? ?? '',
    entityId: m['entity_id'] as String? ?? '',
    key: m['key'] as String? ?? '',
    valueText: m['value_text'] as String?,
    valueNum: (m['value_num'] as num?)?.toDouble(),
    sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      m['updated_at'] as int? ?? 0,
    ),
  );

  static const Object _unset = Object();
}
