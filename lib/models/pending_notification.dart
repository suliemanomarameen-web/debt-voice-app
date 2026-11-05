import 'dart:convert';

/// نموذج الإشعار المعلّق
///
/// يمثّل تسجيلاً صوتياً واحداً يحتاج إجراءً من المستخدم.
class PendingNotification {
  final int? id;
  final String type;
  final String? text;
  final String? audioPath;
  final String? intent;
  final String? customerName;
  final double? amount;
  final String currency;
  final String? items;
  final String? accountType;

  /// 'single' | 'multiple' | 'unclear' | 'no_account'
  final String matchType;

  final int? matchedCustomerId;
  final String? matchedCustomerName;

  final List<Map<String, dynamic>> candidates;

  /// 'pending' | 'saved' | 'cancelled' | 'dismissed' | 'expired'
  final String status;

  final String createdAt;
  final String? expiresAt;

  PendingNotification({
    this.id,
    this.type = 'voice',
    this.text,
    this.audioPath,
    this.intent,
    this.customerName,
    this.amount,
    this.currency = 'YER',
    this.items,
    this.accountType,
    this.matchType = 'unclear',
    this.matchedCustomerId,
    this.matchedCustomerName,
    this.candidates = const [],
    this.status = 'pending',
    required this.createdAt,
    this.expiresAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'text': text,
        'audio_path': audioPath,
        'intent': intent,
        'customer_name': customerName,
        'amount': amount,
        'currency': currency,
        'items': items,
        'account_type': accountType,
        'match_type': matchType,
        'matched_customer_id': matchedCustomerId,
        'matched_customer_name': matchedCustomerName,
        'candidates': candidates.isEmpty ? null : jsonEncode(candidates),
        'status': status,
        'created_at': createdAt,
        'expires_at': expiresAt,
      };

  factory PendingNotification.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>> candidatesList = [];
    try {
      final raw = m['candidates'];
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          candidatesList =
              decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {}

    return PendingNotification(
      id: m['id'] as int?,
      type: m['type'] as String? ?? 'voice',
      text: m['text'] as String?,
      audioPath: m['audio_path'] as String?,
      intent: m['intent'] as String?,
      customerName: m['customer_name'] as String?,
      amount: (m['amount'] as num?)?.toDouble(),
      currency: m['currency'] as String? ?? 'YER',
      items: m['items'] as String?,
      accountType: m['account_type'] as String?,
      matchType: m['match_type'] as String? ?? 'unclear',
      matchedCustomerId: m['matched_customer_id'] as int?,
      matchedCustomerName: m['matched_customer_name'] as String?,
      candidates: candidatesList,
      status: m['status'] as String? ?? 'pending',
      createdAt: m['created_at'] as String? ?? '',
      expiresAt: m['expires_at'] as String?,
    );
  }

  PendingNotification copyWith({
    int? id,
    String? type,
    String? text,
    String? audioPath,
    String? intent,
    String? customerName,
    double? amount,
    String? currency,
    String? items,
    String? accountType,
    String? matchType,
    int? matchedCustomerId,
    String? matchedCustomerName,
    List<Map<String, dynamic>>? candidates,
    String? status,
    String? createdAt,
    String? expiresAt,
  }) {
    return PendingNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      audioPath: audioPath ?? this.audioPath,
      intent: intent ?? this.intent,
      customerName: customerName ?? this.customerName,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      items: items ?? this.items,
      accountType: accountType ?? this.accountType,
      matchType: matchType ?? this.matchType,
      matchedCustomerId: matchedCustomerId ?? this.matchedCustomerId,
      matchedCustomerName: matchedCustomerName ?? this.matchedCustomerName,
      candidates: candidates ?? this.candidates,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // حالة
  // ═══════════════════════════════════════════════════════════

  bool get isPending => status == 'pending';
  bool get isSaved => status == 'saved';
  bool get isCancelled => status == 'cancelled';
  bool get isDismissed => status == 'dismissed';
  bool get isExpired => status == 'expired';

  bool get isUnclear => matchType == 'unclear';
  bool get isNoAccount => matchType == 'no_account';
  bool get isSingle => matchType == 'single';
  bool get isMultiple => matchType == 'multiple';

  bool get hasExpiry => expiresAt != null && expiresAt!.isNotEmpty;
  bool get needsAction => isSingle || isMultiple;

  DateTime? get expiryDate {
    if (expiresAt == null || expiresAt!.isEmpty) return null;
    return DateTime.tryParse(expiresAt!);
  }

  Duration? get timeRemaining {
    final dt = expiryDate;
    if (dt == null) return null;
    final diff = dt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  // ═══════════════════════════════════════════════════════════
  // نصوص للعرض
  // ═══════════════════════════════════════════════════════════

  String get typeLabel {
    switch (matchType) {
      case 'single':
        return 'حساب واحد';
      case 'multiple':
        return 'أكثر من حساب';
      case 'unclear':
        return 'غير مفهوم';
      case 'no_account':
        return 'لا يوجد حساب';
      default:
        return 'إشعار';
    }
  }

  String get matchTypeEmoji {
    switch (matchType) {
      case 'single':
        return '🟢';
      case 'multiple':
        return '🟡';
      case 'unclear':
        return '⚪';
      case 'no_account':
        return '🟠';
      default:
        return '⚫';
    }
  }

  int get matchTypeColor {
    switch (matchType) {
      case 'single':
        return 0xFF4CAF50;
      case 'multiple':
        return 0xFFFFC107;
      case 'unclear':
        return 0xFF9E9E9E;
      case 'no_account':
        return 0xFFFF9800;
      default:
        return 0xFF607D8B;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'بانتظار الإجراء';
      case 'saved':
        return 'تم الحفظ';
      case 'cancelled':
        return 'أُلغي';
      case 'dismissed':
        return 'تمييز كمقروءة';
      case 'expired':
        return 'انتهت الصلاحية';
      default:
        return status;
    }
  }

  int get statusColor {
    switch (status) {
      case 'pending':
        return 0xFFFF9800;
      case 'saved':
        return 0xFF4CAF50;
      case 'cancelled':
        return 0xFF9E9E9E;
      case 'dismissed':
        return 0xFF2196F3;
      case 'expired':
        return 0xFFF44336;
      default:
        return 0xFF607D8B;
    }
  }

  String get intentLabel {
    switch (intent) {
      case 'debt':
        return 'دين';
      case 'payment':
        return 'سداد';
      case 'return':
        return 'مرتجع';
      case 'add_account':
        return 'إنشاء حساب';
      default:
        return '';
    }
  }

  String get summary {
    final parts = <String>[];
    if (intentLabel.isNotEmpty) parts.add(intentLabel);
    if (amount != null) {
      parts.add('${amount!.toStringAsFixed(0)} $currency');
    }
    if (customerName != null && customerName!.isNotEmpty) {
      parts.add(customerName!);
    }
    if (parts.isEmpty && text != null && text!.isNotEmpty) {
      return text!;
    }
    return parts.join(' — ');
  }

  bool get canSave => isSingle && matchedCustomerId != null && intent != null;
  bool get canChoose => isMultiple && candidates.isNotEmpty;

  // ═══════════════════════════════════════════════════════════
  // إنشاء من تحليل الصوت
  // ═══════════════════════════════════════════════════════════

  /// من "غير مفهوم"
  ///
  /// [expiresInMinutes] تُحدَّد من الإعداد `voicePendingAutoExpireDays`
  /// (تُمرَّر من overlay_handler)
  factory PendingNotification.unclear({
    required String text,
    String? audioPath,
    String? accountant,
    int expiresInMinutes = 5,
  }) {
    final now = DateTime.now();
    return PendingNotification(
      type: 'voice',
      text: text.isEmpty ? '(تسجيل صوتي محفوظ)' : text,
      audioPath: audioPath,
      matchType: 'unclear',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(Duration(minutes: expiresInMinutes)).toIso8601String(),
    );
  }

  /// من "لا يوجد حساب"
  factory PendingNotification.noAccount({
    required String text,
    required String customerName,
    required String intent,
    required double amount,
    required String currency,
    required String items,
    String? audioPath,
    int expiresInMinutes = 5,
  }) {
    final now = DateTime.now();
    return PendingNotification(
      type: 'voice',
      text: text,
      audioPath: audioPath,
      intent: intent,
      customerName: customerName,
      amount: amount,
      currency: currency,
      items: items,
      matchType: 'no_account',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(Duration(minutes: expiresInMinutes)).toIso8601String(),
    );
  }

  /// من "حساب واحد مطابق" — لا ينتهي
  factory PendingNotification.single({
    required String text,
    required String customerName,
    required String intent,
    required double amount,
    required String currency,
    required String items,
    required int matchedCustomerId,
    required String matchedCustomerName,
    String? audioPath,
    String? accountType,
  }) {
    return PendingNotification(
      type: 'voice',
      text: text,
      audioPath: audioPath,
      intent: intent,
      customerName: customerName,
      amount: amount,
      currency: currency,
      items: items,
      accountType: accountType,
      matchType: 'single',
      matchedCustomerId: matchedCustomerId,
      matchedCustomerName: matchedCustomerName,
      createdAt: DateTime.now().toIso8601String(),
      expiresAt: null,
    );
  }

  /// من "أكثر من حساب" — لا ينتهي
  factory PendingNotification.multiple({
    required String text,
    required String customerName,
    required String intent,
    required double amount,
    required String currency,
    required String items,
    required List<Map<String, dynamic>> candidates,
    String? audioPath,
    String? accountType,
  }) {
    return PendingNotification(
      type: 'voice',
      text: text,
      audioPath: audioPath,
      intent: intent,
      customerName: customerName,
      amount: amount,
      currency: currency,
      items: items,
      accountType: accountType,
      matchType: 'multiple',
      candidates: candidates,
      createdAt: DateTime.now().toIso8601String(),
      expiresAt: null,
    );
  }
}

// Pending Notification Model v1: نموذج إشعار صوتي معلّق يدعم 4 أنواع
// Pending Notification Model v2: إضافة expiresInMinutes لتطبيق voicePendingAutoExpireDays
