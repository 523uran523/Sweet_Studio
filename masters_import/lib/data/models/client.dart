class Client {
  const Client({
    required this.id,
    required this.name,
    this.phone = '',
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  Client copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? phone = _unset,
    Object? note = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return Client(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      phone: phone == _unset ? this.phone : phone as String,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory Client.fromMap(Map<String, Object?> m) => Client(
    id: m['id'] as String,
    name: m['name'] as String,
    phone: m['phone'] as String? ?? '',
    note: m['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      m['updated_at'] as int? ?? 0,
    ),
  );

  static String normalizePhone(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static String normalizeName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String? get duplicateKey {
    var digits = normalizePhone(phone);
    if (digits.length == 11 && digits.startsWith('8')) {
      digits = '7${digits.substring(1)}';
    }
    if (digits.length >= 7) return digits;
    final normalized = normalizeName(name);
    if (normalized.isEmpty) return null;
    return normalized;
  }

  bool sameIdentity(Client other) {
    final thisKey = duplicateKey;
    final otherKey = other.duplicateKey;
    if (thisKey != null && thisKey == otherKey) return true;
    final normalizedName = normalizeName(name);
    final otherName = normalizeName(other.name);
    if (normalizedName.isNotEmpty &&
        normalizedName == otherName &&
        phone.trim() == other.phone.trim()) {
      return true;
    }
    return false;
  }

  static const Object _unset = Object();
}
