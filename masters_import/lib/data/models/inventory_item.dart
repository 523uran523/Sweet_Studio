class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.kind = 'good',
    this.unit = 'шт',
    this.sellPriceCents = 0,
    this.costCents = 0,
    this.category = '',
    this.trackStock = true,
    this.stockQty = 0,
    this.minQty = 0,
    this.archived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String kind; // good / service
  final String unit;
  final int sellPriceCents;
  final int costCents;
  final String category;
  final bool trackStock;
  final double stockQty;
  final double minQty;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get lowStock =>
      trackStock && (stockQty < 0 || (minQty > 0 && stockQty <= minQty));

  InventoryItem copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? kind = _unset,
    Object? unit = _unset,
    Object? sellPriceCents = _unset,
    Object? costCents = _unset,
    Object? category = _unset,
    Object? trackStock = _unset,
    Object? stockQty = _unset,
    Object? minQty = _unset,
    Object? archived = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return InventoryItem(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      kind: kind == _unset ? this.kind : kind as String,
      unit: unit == _unset ? this.unit : unit as String,
      sellPriceCents: sellPriceCents == _unset
          ? this.sellPriceCents
          : sellPriceCents as int,
      costCents: costCents == _unset ? this.costCents : costCents as int,
      category: category == _unset ? this.category : category as String,
      trackStock: trackStock == _unset ? this.trackStock : trackStock as bool,
      stockQty: stockQty == _unset ? this.stockQty : stockQty as double,
      minQty: minQty == _unset ? this.minQty : minQty as double,
      archived: archived == _unset ? this.archived : archived as bool,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'kind': kind,
    'unit': unit,
    'sell_price_cents': sellPriceCents,
    'cost_cents': costCents,
    'category': category,
    'track_stock': trackStock ? 1 : 0,
    'stock_qty': stockQty,
    'min_qty': minQty,
    'archived': archived ? 1 : 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory InventoryItem.fromMap(Map<String, Object?> m) => InventoryItem(
    id: m['id'] as String,
    name: m['name'] as String,
    kind: m['kind'] as String? ?? 'good',
    unit: m['unit'] as String? ?? 'шт',
    sellPriceCents: m['sell_price_cents'] as int? ?? 0,
    costCents: m['cost_cents'] as int? ?? 0,
    category: m['category'] as String? ?? '',
    trackStock: (m['track_stock'] as int? ?? 1) == 1,
    stockQty: (m['stock_qty'] as num?)?.toDouble() ?? 0,
    minQty: (m['min_qty'] as num?)?.toDouble() ?? 0,
    archived: (m['archived'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      m['updated_at'] as int? ?? 0,
    ),
  );

  static const Object _unset = Object();
}
