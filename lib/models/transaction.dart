class Transaction {
  final int? id;
  final String? cloudId; // 🆕 UUID عالمي فريد (لا يتغير)
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
  final String? lastModifiedBy;
  final String? lastModifiedFrom; // device_id

  // 🆕 Soft Delete
  final bool isDeleted;
  final String? deletedAt;
  final String? deletedBy;

  final String createdAt;

  Transaction({
    this.id,
    this.cloudId,
    required this.customerId,
    this.code,
    this.accountant,
    this.source,
    required this.amount,
    this.currency = 'YER',
    required this.type,
    this.items = '',
    this.updatedBy,
    this.updatedAt,
    this.lastModifiedBy,
    this.lastModifiedFrom,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'cloud_id': cloudId,
        'customer_id': customerId,
        'code': code,
        'accountant': accountant,
        'source': source,
        'amount': amount,
        'currency': currency,
        'type': type,
        'items': items,
        'updated_by': updatedBy,
        'updated_at': updatedAt,
        'last_modified_by': lastModifiedBy,
        'last_modified_from': lastModifiedFrom,
        'is_deleted': isDeleted ? 1 : 0,
        'deleted_at': deletedAt,
        'deleted_by': deletedBy,
        'created_at': createdAt,
      };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: m['id'],
        cloudId: m['cloud_id'],
        customerId: m['customer_id'],
        code: m['code'],
        accountant: m['accountant'],
        source: m['source'],
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] ?? 'YER',
        type: m['type'],
        items: m['items'] ?? '',
        updatedBy: m['updated_by'],
        updatedAt: m['updated_at'],
        lastModifiedBy: m['last_modified_by'],
        lastModifiedFrom: m['last_modified_from'],
        isDeleted: m['is_deleted'] == 1,
        deletedAt: m['deleted_at'],
        deletedBy: m['deleted_by'],
        createdAt: m['created_at'],
      );

  Transaction copyWith({
    int? id,
    String? cloudId,
    int? customerId,
    String? code,
    String? accountant,
    String? source,
    double? amount,
    String? currency,
    String? type,
    String? items,
    String? updatedBy,
    String? updatedAt,
    String? lastModifiedBy,
    String? lastModifiedFrom,
    bool? isDeleted,
    String? deletedAt,
    String? deletedBy,
    String? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      customerId: customerId ?? this.customerId,
      code: code ?? this.code,
      accountant: accountant ?? this.accountant,
      source: source ?? this.source,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      type: type ?? this.type,
      items: items ?? this.items,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      lastModifiedFrom: lastModifiedFrom ?? this.lastModifiedFrom,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // معلومات المصدر
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
  // دوال مساعدة
  // ═══════════════════════════════════════════════════════════

  bool get isDebt => type == 'debt' && !isReturn;
  bool get isPayment => type == 'payment' && !isReturn;
  bool get isReturn => items.startsWith('مرتجع');
  bool get isCurrentlyActive => !isDeleted;
  bool get isTrashed => isDeleted;

  bool get wasModified {
    if (updatedAt == null || createdAt.isEmpty) return false;
    return updatedAt != createdAt;
  }

  bool get wasModifiedByOther {
    if (!wasModified) return false;
    if (accountant == null || updatedBy == null) return false;
    return accountant != updatedBy;
  }

  bool get hasCloudId => cloudId != null && cloudId!.isNotEmpty;

  String get deletedByLabel {
    if (deletedBy == null || deletedBy!.isEmpty) return 'غير معروف';
    return deletedBy!;
  }

  String get lastModifiedLabel {
    if (lastModifiedBy == null || lastModifiedBy!.isEmpty) {
      return 'لا تعديلات';
    }
    return 'آخر تعديل: $lastModifiedBy';
  }

  String get displayLabel {
    if (isReturn) return 'مرتجع';
    if (isDebt) return 'دين';
    return 'سداد';
  }
}
