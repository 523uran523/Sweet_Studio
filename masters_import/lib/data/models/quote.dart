import 'dart:convert';

/// Снимок коммерческого предложения (§12.4, Э3).
///
/// КП — неизменяемый документ: в момент отправки фиксируется номер, ревизия,
/// строки и итог (`snapshotJson`). Правка заказа или нового КП создаёт
/// новую ревизию, старая остаётся доступной, поэтому клиент всегда видит
/// ровно то, что согласовывал, а при разногласии есть доказательство цены.
class Quote {
  Quote({
    required this.id,
    this.jobId,
    this.leadId,
    required this.number,
    this.revision = 1,
    this.totalCents = 0,
    required this.snapshotJson,
    this.pdfPath,
    this.validUntil,
    this.sentAt,
    this.status = 'draft',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String? jobId;
  final String? leadId;

  /// Видимый номер, например `КП-2026-014`.
  final String number;

  /// Ревизия внутри номера: 1, 2, … Старые ревизии не удаляются.
  final int revision;
  final int totalCents;

  /// JSON снимка: строки, итог, клиент, срок действия. Именно он попадает
  /// в PDF, поэтому PDF повторной генерации того же снимка идентичен.
  final String snapshotJson;
  final String? pdfPath;
  final DateTime? validUntil;
  final DateTime? sentAt;

  /// `draft` / `sent` / `accepted` / `rejected`.
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isSent => sentAt != null;

  bool get isExpired =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  String get statusLabel => switch (status) {
    'sent' => 'Отправлено',
    'accepted' => 'Принято',
    'rejected' => 'Отклонено',
    _ => isExpired ? 'Истекло' : 'Черновик',
  };

  /// Строки снимка; пусто, если JSON повреждён — экран тогда покажет только
  /// итог, вместо падения на битых данных.
  List<Map<String, Object?>> get lines {
    try {
      final decoded = jsonDecode(snapshotJson);
      final raw = decoded is Map ? decoded['lines'] : decoded;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Quote copyWith({
    Object? jobId = _unset,
    Object? leadId = _unset,
    Object? number = _unset,
    Object? revision = _unset,
    Object? totalCents = _unset,
    Object? snapshotJson = _unset,
    Object? pdfPath = _unset,
    Object? validUntil = _unset,
    Object? sentAt = _unset,
    Object? status = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return Quote(
      id: id,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
      leadId: leadId == _unset ? this.leadId : leadId as String?,
      number: number == _unset ? this.number : number as String,
      revision: revision == _unset ? this.revision : revision as int,
      totalCents: totalCents == _unset ? this.totalCents : totalCents as int,
      snapshotJson: snapshotJson == _unset
          ? this.snapshotJson
          : snapshotJson as String,
      pdfPath: pdfPath == _unset ? this.pdfPath : pdfPath as String?,
      validUntil: validUntil == _unset
          ? this.validUntil
          : validUntil as DateTime?,
      sentAt: sentAt == _unset ? this.sentAt : sentAt as DateTime?,
      status: status == _unset ? this.status : status as String,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'job_id': jobId,
    'lead_id': leadId,
    'number': number,
    'revision': revision,
    'total_cents': totalCents,
    'snapshot_json': snapshotJson,
    'pdf_path': pdfPath,
    'valid_until': validUntil?.millisecondsSinceEpoch,
    'sent_at': sentAt?.millisecondsSinceEpoch,
    'status': status,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory Quote.fromMap(Map<String, Object?> m) => Quote(
    id: m['id'] as String,
    jobId: m['job_id'] as String?,
    leadId: m['lead_id'] as String?,
    number: m['number'] as String? ?? '',
    revision: (m['revision'] as num?)?.toInt() ?? 1,
    totalCents: (m['total_cents'] as num?)?.toInt() ?? 0,
    snapshotJson: m['snapshot_json'] as String? ?? '{"lines":[]}',
    pdfPath: m['pdf_path'] as String?,
    validUntil: m['valid_until'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['valid_until'] as num).toInt()),
    sentAt: m['sent_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['sent_at'] as num).toInt()),
    status: m['status'] as String? ?? 'draft',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updated_at'] as num?)?.toInt() ??
          (m['created_at'] as num?)?.toInt() ??
          0,
    ),
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['deleted_at'] as num).toInt()),
    deviceId: m['device_id'] as String?,
  );

  static const Object _unset = Object();
}
