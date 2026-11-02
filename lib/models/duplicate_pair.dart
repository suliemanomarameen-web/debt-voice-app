import 'dart:convert';

/// نموذج التكرار — يمثّل سجلاً واحداً في جدول `pending_duplicates`
///
/// يمثّل حالة تكرار واحد بين:
/// - سجل محلي (localCloudId)
/// - سجل سحابي (cloudCloudId)
///
/// مع تفاصيل التشابه والقرار المتخذ (إن وُجد).
class DuplicatePair {
  final int? id;
  final String type; // 'customer' | 'transaction'
  final String localCloudId;
  final String cloudCloudId;

  /// درجة التشابه (0.0 - 1.0)
  /// - 1.0 = تطابق تام (تكرار مؤكد)
  /// - 0.9 = محتمل (بادئة 2+ كلمات)
  /// - 0.85 = تشابه حرفي (Levenshtein = 1)
  /// - 0.5 = ضعيف (بادئة كلمة واحدة)
  final double similarityScore;

  /// مستوى التشابه: 'confirmed' | 'likely' | 'weak' | 'similar'
  final String similarityLevel;

  final String detectedAt;

  /// 'pending' | 'skipped' | 'resolved'
  final String status;

  /// 'merge' | 'rename' | null
  final String? resolution;

  final String? resolvedAt;
  final String? resolvedBy;

  /// بيانات إضافية (JSON): الأسماء، المبالغ، العمليات، إلخ
  final String? metadata;

  DuplicatePair({
    this.id,
    required this.type,
    required this.localCloudId,
    required this.cloudCloudId,
    this.similarityScore = 1.0,
    this.similarityLevel = 'confirmed',
    required this.detectedAt,
    this.status = 'pending',
    this.resolution,
    this.resolvedAt,
    this.resolvedBy,
    this.metadata,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'local_cloud_id': localCloudId,
        'cloud_cloud_id': cloudCloudId,
        'similarity_score': similarityScore,
        'similarity_level': similarityLevel,
        'detected_at': detectedAt,
        'status': status,
        'resolution': resolution,
        'resolved_at': resolvedAt,
        'resolved_by': resolvedBy,
        'metadata': metadata,
      };

  factory DuplicatePair.fromMap(Map<String, dynamic> m) => DuplicatePair(
        id: m['id'] as int?,
        type: m['type'] as String? ?? 'customer',
        localCloudId: m['local_cloud_id'] as String? ?? '',
        cloudCloudId: m['cloud_cloud_id'] as String? ?? '',
        similarityScore:
            (m['similarity_score'] as num?)?.toDouble() ?? 1.0,
        similarityLevel:
            m['similarity_level'] as String? ?? 'confirmed',
        detectedAt: m['detected_at'] as String? ?? '',
        status: m['status'] as String? ?? 'pending',
        resolution: m['resolution'] as String?,
        resolvedAt: m['resolved_at'] as String?,
        resolvedBy: m['resolved_by'] as String?,
        metadata: m['metadata'] as String?,
      );

  DuplicatePair copyWith({
    int? id,
    String? type,
    String? localCloudId,
    String? cloudCloudId,
    double? similarityScore,
    String? similarityLevel,
    String? detectedAt,
    String? status,
    String? resolution,
    String? resolvedAt,
    String? resolvedBy,
    String? metadata,
  }) {
    return DuplicatePair(
      id: id ?? this.id,
      type: type ?? this.type,
      localCloudId: localCloudId ?? this.localCloudId,
      cloudCloudId: cloudCloudId ?? this.cloudCloudId,
      similarityScore: similarityScore ?? this.similarityScore,
      similarityLevel: similarityLevel ?? this.similarityLevel,
      detectedAt: detectedAt ?? this.detectedAt,
      status: status ?? this.status,
      resolution: resolution ?? this.resolution,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      metadata: metadata ?? this.metadata,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // حالة التكرار
  // ═══════════════════════════════════════════════════════════

  bool get isPending => status == 'pending';
  bool get isSkipped => status == 'skipped';
  bool get isResolved => status == 'resolved';

  bool get isUnresolved => isPending || isSkipped;

  // ═══════════════════════════════════════════════════════════
  // نوع القرار
  // ═══════════════════════════════════════════════════════════

  bool get resolutionIsMerge => resolution == 'merge';
  bool get resolutionIsRename => resolution == 'rename';

  // ═══════════════════════════════════════════════════════════
  // مستوى التشابه
  // ═══════════════════════════════════════════════════════════

  bool get isConfirmed => similarityLevel == 'confirmed';
  bool get isLikely => similarityLevel == 'likely';
  bool get isWeak => similarityLevel == 'weak';
  bool get isSimilar => similarityLevel == 'similar';

  // ═══════════════════════════════════════════════════════════
  // النوع
  // ═══════════════════════════════════════════════════════════

  bool get isCustomer => type == 'customer';
  bool get isTransaction => type == 'transaction';

  // ═══════════════════════════════════════════════════════════
  // Metadata
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic>? get metadataMap {
    if (metadata == null || metadata!.isEmpty) return null;
    try {
      return jsonDecode(metadata!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String? encodeMetadata(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // نصوص للعرض
  // ═══════════════════════════════════════════════════════════

  String get typeLabel {
    switch (type) {
      case 'customer':
        return 'حساب';
      case 'transaction':
        return 'عملية';
      default:
        return type;
    }
  }

  String get typeEmoji {
    switch (type) {
      case 'customer':
        return '👤';
      case 'transaction':
        return '💼';
      default:
        return '❓';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'بانتظار المراجعة';
      case 'skipped':
        return 'مؤجل';
      case 'resolved':
        return 'تم الحل';
      default:
        return status;
    }
  }

  String get resolutionLabel {
    switch (resolution) {
      case 'merge':
        return 'تم الدمج';
      case 'rename':
        return 'تم إعادة التسمية';
      default:
        return 'بدون قرار';
    }
  }

  String get similarityLevelLabel {
    switch (similarityLevel) {
      case 'confirmed':
        return 'تطابق تام';
      case 'likely':
        return 'تشابه محتمل';
      case 'weak':
        return 'تشابه ضعيف';
      case 'similar':
        return 'تشابه حرفي';
      default:
        return similarityLevel;
    }
  }

  String get similarityLevelEmoji {
    switch (similarityLevel) {
      case 'confirmed':
        return '🟢';
      case 'likely':
        return '🟡';
      case 'weak':
        return '⚪';
      case 'similar':
        return '🟠';
      default:
        return '⚫';
    }
  }

  int get similarityLevelColor {
    switch (similarityLevel) {
      case 'confirmed':
        return 0xFF4CAF50; // أخضر
      case 'likely':
        return 0xFFFFC107; // أصفر
      case 'weak':
        return 0xFF9E9E9E; // رمادي
      case 'similar':
        return 0xFFFF9800; // برتقالي
      default:
        return 0xFF607D8B;
    }
  }

  /// نسبة مئوية (للعرض)
  String get similarityPercentLabel {
    final pct = (similarityScore * 100).round();
    return '$pct%';
  }

  String get localCloudIdShort =>
      localCloudId.length >= 8 ? localCloudId.substring(0, 8) : localCloudId;

  String get cloudCloudIdShort =>
      cloudCloudId.length >= 8 ? cloudCloudId.substring(0, 8) : cloudCloudId;
}

// التكرارات v1: نموذج DuplicatePair الأساسي لجدول pending_duplicates (المرحلة 1)
