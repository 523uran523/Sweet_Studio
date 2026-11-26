class Account {
  const Account({
    required this.id,
    required this.name,
    this.type = 'cash',
    this.color = '#007AFF',
    this.archived = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String type; // cash, card, bank, wallet, other
  final String color;
  final bool archived;
  final DateTime createdAt;

  Account copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? type = _unset,
    Object? color = _unset,
    Object? archived = _unset,
    Object? createdAt = _unset,
  }) {
    return Account(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      type: type == _unset ? this.type : type as String,
      color: color == _unset ? this.color : color as String,
      archived: archived == _unset ? this.archived : archived as bool,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'color': color,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as String,
        name: m['name'] as String,
        type: m['type'] as String? ?? 'cash',
        color: m['color'] as String? ?? '#007AFF',
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );

  static const Object _unset = Object();
}
