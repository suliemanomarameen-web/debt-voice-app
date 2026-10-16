import 'account_type.dart';

class Customer {
  final int? id;
  final String? cloudId; // 🆕 UUID عالمي فريد (لا يتغير أبداً)
  final String name;
  final String? phone;
  final String accountType;
  final String? note;
  final String? photoPath;
  final String category;
  final double? maxBalance;
  final bool isActive;

  // 🆕 Tracking
  final String? createdBy;
  final String? updatedBy;
  final String? updatedAt;

  // 🆕 Soft Delete + من حذف
  final bool isDeleted;
  final String? deletedAt;
  final String? deletedBy;

  final String createdAt;

  Customer({
    this.id,
    this.cloudId,
    required this.name,
    this.phone,
    this.accountType = AccountType.customer,
    this.note,
    this.photoPath,
    this.category = 'normal',
    this.maxBalance,
    this.isActive = true,
    this.createdBy,
    this.updatedBy,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'cloud_id': cloudId,
        'name': name,
        'phone': phone,
        'account_type': accountType,
        'note': note,
        'photo_path': photoPath,
        'category': category,
        'max_balance': maxBalance,
        'is_active': isActive ? 1 : 0,
        'created_by': createdBy,
        'updated_by': updatedBy,
        'updated_at': updatedAt,
        'is_deleted': isDeleted ? 1 : 0,
        'deleted_at': deletedAt,
        'deleted_by': deletedBy,
        'created_at': createdAt,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        cloudId: m['cloud_id'],
        name: m['name'],
        phone: m['phone'],
        accountType: m['account_type'] ?? AccountType.customer,
        note: m['note'],
        photoPath: m['photo_path'],
        category: m['category'] ?? 'normal',
        maxBalance: m['max_balance'] != null
            ? (m['max_balance'] as num).toDouble()
            : null,
        isActive: m['is_active'] == null || m['is_active'] == 1,
        createdBy: m['created_by'],
        updatedBy: m['updated_by'],
        updatedAt: m['updated_at'],
        isDeleted: m['is_deleted'] == 1,
        deletedAt: m['deleted_at'],
        deletedBy: m['deleted_by'],
        createdAt: m['created_at'] ?? '',
      );

  Customer copyWith({
    int? id,
    String? cloudId,
    String? name,
    String? phone,
    String? accountType,
    String? note,
    String? photoPath,
    String? category,
    double? maxBalance,
    bool? isActive,
    String? createdBy,
    String? updatedBy,
    String? updatedAt,
    bool? isDeleted,
    String? deletedAt,
    String? deletedBy,
    String? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      accountType: accountType ?? this.accountType,
      note: note ?? this.note,
      photoPath: photoPath ?? this.photoPath,
      category: category ?? this.category,
      maxBalance: maxBalance ?? this.maxBalance,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool isOverLimit(double currentBalance) {
    if (maxBalance == null) return false;
    if (maxBalance! <= 0) return false;
    return currentBalance > maxBalance!;
  }

  double balanceRatio(double currentBalance) {
    if (maxBalance == null || maxBalance! <= 0) return 0;
    return currentBalance / maxBalance!;
  }

  bool get isCurrentlyActive => isActive && !isDeleted;
  bool get isTrashed => isDeleted;

  bool get wasModified {
    if (updatedAt == null || createdAt.isEmpty) return false;
    return updatedAt != createdAt;
  }

  bool get wasModifiedByOther {
    if (!wasModified) return false;
    if (createdBy == null || updatedBy == null) return false;
    return createdBy != updatedBy;
  }

  bool get hasCloudId => cloudId != null && cloudId!.isNotEmpty;

  String get deletedByLabel {
    if (deletedBy == null || deletedBy!.isEmpty) return 'غير معروف';
    return deletedBy!;
  }
}

class CustomerCategory {
  static const String normal = 'normal';
  static const String vip = 'vip';
  static const String newCustomer = 'new';
  static const String blocked = 'blocked';
  static const String family = 'family';

  static const Map<String, String> labelsAr = {
    normal: 'عادي',
    vip: 'VIP',
    newCustomer: 'جديد',
    blocked: 'محظور',
    family: 'عائلة',
  };

  static const Map<String, int> colors = {
    normal: 0xFF607D8B,
    vip: 0xFFFFB300,
    newCustomer: 0xFF4CAF50,
    blocked: 0xFFE53935,
    family: 0xFF9C27B0,
  };

  static List<String> get all => [normal, vip, newCustomer, blocked, family];

  static String label(String key) => labelsAr[key] ?? 'عادي';
  static int color(String key) => colors[key] ?? 0xFF607D8B;
}
