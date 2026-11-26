class BookingResource {
  const BookingResource({
    required this.id,
    required this.name,
    this.color = '#007AFF',
    this.archived = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String color;
  final bool archived;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory BookingResource.fromMap(Map<String, Object?> m) => BookingResource(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as String? ?? '#007AFF',
        archived: (m['archived'] as int? ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
      );
}
