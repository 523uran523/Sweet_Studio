class Employee {
  const Employee({
    required this.id,
    required this.name,
    this.role = 'employee',
    this.payType = 'hourly',
    this.rateCents = 0,
    this.percent = 0,
    this.archived = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String role; // owner, manager, employee
  final String payType; // hourly, piece, percent, salary, mixed
  final int rateCents;
  final double percent;
  final bool archived;
  final DateTime createdAt;

  String get payTypeLabel => switch (payType) {
        'piece' => 'Сдельная',
        'percent' => 'Процент',
        'salary' => 'Оклад',
        'mixed' => 'Смешанная',
        _ => 'Почасовая',
      };

  Employee copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? role = _unset,
    Object? payType = _unset,
    Object? rateCents = _unset,
    Object? percent = _unset,
    Object? archived = _unset,
    Object? createdAt = _unset,
  }) {
    return Employee(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      role: role == _unset ? this.role : role as String,
      payType: payType == _unset ? this.payType : payType as String,
      rateCents: rateCents == _unset ? this.rateCents : rateCents as int,
      percent: percent == _unset ? this.percent : percent as double,
      archived: archived == _unset ? this.archived : archived as bool,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'role': role,
        'pay_type': payType,
        'rate_cents': rateCents,
        'percent': percent,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Employee.fromMap(Map<String, Object?> m) => Employee(
        id: m['id'] as String,
        name: m['name'] as String,
        role: m['role'] as String? ?? 'employee',
        payType: m['pay_type'] as String? ?? 'hourly',
        rateCents: m['rate_cents'] as int? ?? 0,
        percent: (m['percent'] as num?)?.toDouble() ?? 0,
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );

  static const Object _unset = Object();
}
