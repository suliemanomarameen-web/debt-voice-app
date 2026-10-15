import 'dart:convert';

/// مستوى الحدث
enum LogLevel {
  info,
  success,
  warning,
  error,
}

/// فئة الحدث
enum LogCategory {
  transaction,
  sync,
  backup,
  customer,
  settings,
  voice,
  security,
  code,
  system,
}

class LogEvent {
  final int? id;
  final String action;
  final String description;
  final LogLevel level;
  final LogCategory category;
  final String? accountant;
  final String? relatedId;
  final String? metadata;
  final String? audioPath;
  final bool isAcknowledged;

  // 🆕 حقل جديد: يحتاج تأكيد من المستخدم
  final bool needsAck;

  final String createdAt;

  LogEvent({
    this.id,
    required this.action,
    required this.description,
    required this.level,
    required this.category,
    this.accountant,
    this.relatedId,
    this.metadata,
    this.audioPath,
    this.isAcknowledged = false,
    // 🆕
    this.needsAck = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'action': action,
        'description': description,
        'level': level.name,
        'category': category.name,
        'accountant': accountant,
        'related_id': relatedId,
        'metadata': metadata,
        'audio_path': audioPath,
        'is_acknowledged': isAcknowledged ? 1 : 0,
        // 🆕
        'needs_acknowledgement': needsAck ? 1 : 0,
        'created_at': createdAt,
      };

  factory LogEvent.fromMap(Map<String, dynamic> m) => LogEvent(
        id: m['id'],
        action: m['action'] ?? '',
        description: m['description'] ?? '',
        level: _parseLevel(m['level']),
        category: _parseCategory(m['category']),
        accountant: m['accountant'],
        relatedId: m['related_id'],
        metadata: m['metadata'],
        audioPath: m['audio_path'],
        isAcknowledged: m['is_acknowledged'] == 1,
        // 🆕
        needsAck: m['needs_acknowledgement'] == 1,
        createdAt: m['created_at'] ?? '',
      );

  static LogLevel _parseLevel(String? s) {
    switch (s) {
      case 'success':
        return LogLevel.success;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      case 'info':
      default:
        return LogLevel.info;
    }
  }

  static LogCategory _parseCategory(String? s) {
    switch (s) {
      case 'transaction':
        return LogCategory.transaction;
      case 'sync':
        return LogCategory.sync;
      case 'backup':
        return LogCategory.backup;
      case 'customer':
        return LogCategory.customer;
      case 'settings':
        return LogCategory.settings;
      case 'voice':
        return LogCategory.voice;
      case 'security':
        return LogCategory.security;
      case 'code':
        return LogCategory.code;
      case 'system':
      default:
        return LogCategory.system;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة للعرض
  // ═══════════════════════════════════════════════════════════

  String get levelLabel {
    switch (level) {
      case LogLevel.info:
        return 'معلومة';
      case LogLevel.success:
        return 'نجاح';
      case LogLevel.warning:
        return 'تحذير';
      case LogLevel.error:
        return 'خطأ';
    }
  }

  String get levelEmoji {
    switch (level) {
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.success:
        return '✅';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  int get levelColor {
    switch (level) {
      case LogLevel.info:
        return 0xFF2196F3;
      case LogLevel.success:
        return 0xFF4CAF50;
      case LogLevel.warning:
        return 0xFFFF9800;
      case LogLevel.error:
        return 0xFFF44336;
    }
  }

  String get categoryLabel {
    switch (category) {
      case LogCategory.transaction:
        return 'عملية';
      case LogCategory.sync:
        return 'مزامنة';
      case LogCategory.backup:
        return 'نسخ احتياطي';
      case LogCategory.customer:
        return 'عميل';
      case LogCategory.settings:
        return 'إعدادات';
      case LogCategory.voice:
        return 'تسجيل صوتي';
      case LogCategory.security:
        return 'أمان';
      case LogCategory.code:
        return 'رموز';
      case LogCategory.system:
        return 'نظام';
    }
  }

  String get categoryEmoji {
    switch (category) {
      case LogCategory.transaction:
        return '💰';
      case LogCategory.sync:
        return '☁️';
      case LogCategory.backup:
        return '💾';
      case LogCategory.customer:
        return '👤';
      case LogCategory.settings:
        return '⚙️';
      case LogCategory.voice:
        return '🎤';
      case LogCategory.security:
        return '🔒';
      case LogCategory.code:
        return '🔢';
      case LogCategory.system:
        return '📱';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 دوال الإشعارات المعلقة
  // ═══════════════════════════════════════════════════════════

  /// هل الإشعار ينتظر تأكيداً من المستخدم؟
  bool get isPendingAck => needsAck && !isAcknowledged;

  /// هل يحتاج تأكيداً بشكل عام (build على الحقل الجديد)؟
  bool get shouldAcknowledge => needsAck && !isAcknowledged;

  /// (Legacy) — يحتاج تأكيداً حسب المستوى
  bool get shouldAcknowledgeByDefault =>
      !isAcknowledged &&
      (level == LogLevel.error || level == LogLevel.warning);

  // ═══════════════════════════════════════════════════════════
  // 🆕 تحديد نوع الإشعار
  // ═══════════════════════════════════════════════════════════

  /// هل هذا إشعار "دين على حساب موقوف"؟
  bool get isDebtOnInactiveWarning {
    return action.contains('دين') && description.contains('موقوف');
  }

  /// هل هذا إشعار "إعادة تفعيل حساب"؟
  bool get isRestoreEvent {
    return action.contains('إعادة تفعيل') ||
        action.contains('استعادة') ||
        description.contains('إعادة تفعيل');
  }

  /// هل هذا إشعار "نزاع مزامنة"؟
  bool get isSyncConflict {
    return category == LogCategory.sync &&
        (action.contains('تعارض') || description.contains('تعارض'));
  }

  /// هل هذا إشعار "فشل مزامنة"؟
  bool get isSyncFailure {
    return category == LogCategory.sync &&
        level == LogLevel.error;
  }

  /// هل هذا إشعار "تجاوز الحد الأقصى"؟
  bool get isOverLimitWarning {
    return action.contains('تجاوز الحد') ||
        description.contains('تجاوز الحد');
  }

  // ═══════════════════════════════════════════════════════════
  // copyWith
  // ═══════════════════════════════════════════════════════════

  LogEvent copyWith({
    int? id,
    String? action,
    String? description,
    LogLevel? level,
    LogCategory? category,
    String? accountant,
    String? relatedId,
    String? metadata,
    String? audioPath,
    bool? isAcknowledged,
    bool? needsAck,
    String? createdAt,
  }) {
    return LogEvent(
      id: id ?? this.id,
      action: action ?? this.action,
      description: description ?? this.description,
      level: level ?? this.level,
      category: category ?? this.category,
      accountant: accountant ?? this.accountant,
      relatedId: relatedId ?? this.relatedId,
      metadata: metadata ?? this.metadata,
      audioPath: audioPath ?? this.audioPath,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
      needsAck: needsAck ?? this.needsAck,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Metadata
  // ═══════════════════════════════════════════════════════════

  static String? encodeMetadata(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? get metadataMap {
    if (metadata == null || metadata!.isEmpty) return null;
    try {
      return jsonDecode(metadata!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
