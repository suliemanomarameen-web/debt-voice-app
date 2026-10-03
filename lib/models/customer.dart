import 'account_type.dart';

class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String accountType;
  final String? note;
  final String? photoPath;    // 🆕 مسار صورة العميل
  final String category;      // 🆕 التصنيف (VIP، عادي، إلخ)
  final String createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.accountType = AccountType.customer,
    this.note,
    this.photoPath,
    this.category = 'normal',
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
    createdAt: m['created_at'],
  );
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
