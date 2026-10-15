class Transaction {
  final int? id;
  final int customerId;
  final String? code;
  final String? accountant;
  final String? source;
  final double amount;
  final String currency;
  final String type;
  final String items;

  // 🆕 Tracking
  final String? updatedBy;
  final String? updatedAt;

  // 🆕 Soft Delete
  final bool isDeleted;
  final String? deletedAt;

  final String createdAt;

  Transaction({
    this.id,
    required this.customerId,
    this.code,
    this.accountant,
    this.source,
    required this.amount,
    this.currency = 'YER',
    required this.type,
    this.items = '',
    // 🆕
    this.updatedBy,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'code': code,
        'accountant': accountant,
        'source': source,
        'amount': amount,
        'currency': currency,
        'type': type,
        'items': items,
        // 🆕
        'updated_by': updatedBy,
        'updated_at': updatedAt,
        'is_deleted': isDeleted ? 1 : 0,
        'deleted_at': deletedAt,
        'created_at': createdAt,
      };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: m['id'],
        customerId: m['customer_id'],
        code: m['code'],
        accountant: m['accountant'],
        source: m['source'],
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] ?? 'YER',
        type: m['type'],
        items: m['items'] ?? '',
        // 🆕
        updatedBy: m['updated_by'],
        updatedAt: m['updated_at'],
        isDeleted: m['is_deleted'] == 1,
        deletedAt: m['deleted_at'],
        createdAt: m['created_at'],
      );

  Transaction copyWith({
    int? id,
    int? customerId,
    String? code,
    String? accountant,
    String? source,
    double? amount,
    String? currency,
    String? type,
    String? items,
    // 🆕
    String? updatedBy,
    String? updatedAt,
    bool? isDeleted,
    String? deletedAt,
    String? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      code: code ?? this.code,
      accountant: accountant ?? this.accountant,
      source: source ?? this.source,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      type: type ?? this.type,
      items: items ?? this.items,
      // 🆕
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // معلومات المصدر (أيقونة + نص + لون)
  // ═══════════════════════════════════════════════════════════
  static ({String label, String emoji, int color}) sourceInfo(String? source) {
    switch (source) {
      case 'overlay':
        return (label: 'الزر العائم', emoji: '🖼️', color: 0xFF9C27B0);
      case 'voice':
        return (label: 'التسجيل الصوتي', emoji: '🎤', color: 0xFF2196F3);
      case 'voice+manual':
        return (
          label: 'صوتي + مراجَع',
          emoji: '🎤✏️',
          color: 0xFFFF6F00
        );
      case 'customer_screen':
        return (label: 'شاشة العميل', emoji: '👤', color: 0xFF4CAF50);
      case 'manual':
      default:
        return (label: 'إضافة يدوية', emoji: '➕', color: 0xFF607D8B);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 دوال مساعدة
  // ═══════════════════════════════════════════════════════════

  /// هل العملية دين؟
  bool get isDebt => type == 'debt' && !isReturn;

  /// هل العملية سداد؟
  bool get isPayment => type == 'payment' && !isReturn;

  /// هل العملية مرتجع؟
  bool get isReturn => items.startsWith('مرتجع');

  /// هل العملية نشطة + غير محذوفة؟
  bool get isCurrentlyActive => !isDeleted;

  /// هل العملية محذوفة؟
  bool get isTrashed => isDeleted;

  /// هل تم تعديلها بعد الإنشاء؟
  bool get wasModified {
    if (updatedAt == null || createdAt.isEmpty) return false;
    return updatedAt != createdAt;
  }

  /// هل تم تعديلها بواسطة شخص مختلف عن المنشئ؟
  bool get wasModifiedByOther {
    if (!wasModified) return false;
    if (accountant == null || updatedBy == null) return false;
    return accountant != updatedBy;
  }
}
