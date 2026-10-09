import 'dart:convert';

/// مستوى الحدث
enum LogLevel {
  info,      // معلومة عامة
  success,   // نجاح
  warning,   // تحذير
  error,     // خطأ
}

/// فئة الحدث
enum LogCategory {
  transaction,   // عمليات (دين/سداد/مرتجع)
  sync,          // مزامنة
  backup,        // نسخ احتياطي
  customer,      // عملاء
  settings,      // إعدادات
  voice,         // تسجيل صوتي
  security,      // أمان (قفل/كلمة مرور)
  code,          // رموز العمليات
  system,        // عام
}

class LogEvent {
  final int? id;
  final String action;        // اسم الحدث (مثل: "إضافة عملية")
  final String description;   // تفاصيل الحدث
  final LogLevel level;
  final LogCategory category;
  final String? accountant;   // من قام بالحدث
  final String? relatedId;    // معرّف مرتبط (رقم العملية / العميل)
  final String? metadata;     // JSON إضافي
  final String? audioPath;    // 🆕 مسار التسجيل الصوتي (إن وُجد)
  final bool isAcknowledged;  // 🆕 هل تم الاعتراف بالتنبيه (للفاشلة)
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

  // ===== أدوات مساعدة للعرض =====

  /// نص عربي للمستوى
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

  /// إيموجي للمستوى
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

  /// لون للمستوى
  int get levelColor {
    switch (level) {
      case LogLevel.info:
        return 0xFF2196F3; // أزرق
      case LogLevel.success:
        return 0xFF4CAF50; // أخضر
      case LogLevel.warning:
        return 0xFFFF9800; // برتقالي
      case LogLevel.error:
        return 0xFFF44336; // أحمر
    }
  }

  /// نص عربي للفئة
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

  /// أيقونة للفئة
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

  /// هل هذا الحدث يحتاج اعترافاً (زر "تم التصحيح")؟
  bool get needsAcknowledgement =>
      !isAcknowledged &&
      (level == LogLevel.error || level == LogLevel.warning);

  /// نسخة معدّلة (لتغيير حالة الاعتراف)
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
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// تحويل metadata من/إلى Map
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
