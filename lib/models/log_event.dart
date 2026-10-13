class LogEvent {
  final int? id;
  final String action;
  final String description;
  final LogLevel level;
  final LogCategory category;
  final String? accountant;        // ✅ موجود
  final String? relatedId;
  final String? metadata;
  final String? audioPath;
  final bool isAcknowledged;
  final String createdAt;

  // ✅ toMap() يحتوي على 'accountant'
  Map<String, dynamic> toMap() => {
    'id': id,
    'action': action,
    'description': description,
    'level': level.name,
    'category': category.name,
    'accountant': accountant,      // ✅ موجود
    'related_id': relatedId,
    'metadata': metadata,
    'audio_path': audioPath,
    'is_acknowledged': isAcknowledged ? 1 : 0,
    'created_at': createdAt,
  };

  // ✅ fromMap() يقرأ 'accountant'
  factory LogEvent.fromMap(Map<String, dynamic> m) => LogEvent(
    id: m['id'],
    action: m['action'] ?? '',
    description: m['description'] ?? '',
    level: _parseLevel(m['level']),
    category: _parseCategory(m['category']),
    accountant: m['accountant'],   // ✅ موجود
    relatedId: m['related_id'],
    metadata: m['metadata'],
    audioPath: m['audio_path'],
    isAcknowledged: m['is_acknowledged'] == 1,
    createdAt: m['created_at'] ?? '',
  );
}
