import 'account_type.dart';

class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String accountType;
  final String? note;
  final String? photoPath;
  final String category;
  final double? maxBalance;
  final bool isActive; // 🆕 الحساب نشط أم موقوف
  final String createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.accountType = AccountType.customer,
    this.note,
    this.photoPath,
    this.category = 'normal',
    this.maxBalance,
    this.isActive = true, // 🆕 افتراضياً نشط
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'account_type': accountType,
        'note': note,
        'photo_path': photoPath,
        'category': category,
        'max_balance': maxBalance,
        'is_active': isActive ? 1 : 0, // 🆕
        'created_at': createdAt,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        name: m['name'],
        phone: m['phone'],
        accountType: m['account_type'] ?? AccountType.customer,
        note: m['note'],
        photoPath: m['photo_path'],
        category: m['category'] ?? 'normal',
        maxBalance: m['max_balance'] != null
            ? (m['max_balance'] as num).toDouble()
            : null,
        isActive: m['is_active'] == null || m['is_active'] == 1, // 🆕
        createdAt: m['created_at'],
      );

  /// نسخة معدّلة
  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? accountType,
    String? note,
    String? photoPath,
    String? category,
    double? maxBalance,
    bool? isActive,
    String? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      accountType: accountType ?? this.accountType,
      note: note ?? this.note,
      photoPath: photoPath ?? this.photoPath,
      category: category ?? this.category,
      maxBalance: maxBalance ?? this.maxBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// هل تجاوز الرصيد الحد الأقصى؟
  bool isOverLimit(double currentBalance) {
    if (maxBalance == null) return false;
    if (maxBalance! <= 0) return false;
    return currentBalance > maxBalance!;
  }

  /// نسبة الرصيد من الحد الأقصى (0.0 - 1.0+)
  double balanceRatio(double currentBalance) {
    if (maxBalance == null || maxBalance! <= 0) return 0;
    return currentBalance / maxBalance!;
  }
}

/// 🆕 التصنيفات الجاهزة
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
