class WorkObject {
  const WorkObject({
    required this.id,
    required this.clientId,
    required this.title,
    this.address = '',
    this.note,
    required this.createdAt,
  });

  final String id;
  final String clientId;
  final String title;
  final String address;
  final String? note;
  final DateTime createdAt;

  WorkObject copyWith({
    Object? id = _unset,
    Object? clientId = _unset,
    Object? title = _unset,
    Object? address = _unset,
    Object? note = _unset,
    Object? createdAt = _unset,
  }) {
    return WorkObject(
      id: id == _unset ? this.id : id as String,
      clientId: clientId == _unset ? this.clientId : clientId as String,
      title: title == _unset ? this.title : title as String,
      address: address == _unset ? this.address : address as String,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'client_id': clientId,
        'title': title,
        'address': address,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory WorkObject.fromMap(Map<String, Object?> m) => WorkObject(
        id: m['id'] as String,
        clientId: m['client_id'] as String,
        title: m['title'] as String,
        address: m['address'] as String? ?? '',
        note: m['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            m['created_at'] as int? ?? 0),
      );

  static const Object _unset = Object();
}