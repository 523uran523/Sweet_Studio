class JobAttachment {
  const JobAttachment({
    required this.id,
    required this.jobId,
    required this.fileName,
    required this.filePath,
    this.mimeType = '',
    required this.createdAt,
    this.deletedAt,
  });

  final String id;
  final String jobId;
  final String fileName;
  final String filePath;
  final String mimeType;
  final DateTime createdAt;
  final DateTime? deletedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'job_id': jobId,
        'file_name': fileName,
        'file_path': filePath,
        'mime_type': mimeType,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': createdAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  factory JobAttachment.fromMap(Map<String, Object?> m) => JobAttachment(
        id: m['id'] as String,
        jobId: m['job_id'] as String,
        fileName: m['file_name'] as String,
        filePath: m['file_path'] as String,
        mimeType: m['mime_type'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        deletedAt: m['deleted_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int),
      );
}
