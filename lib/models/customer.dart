import 'account_type.dart';

class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String accountType;
  final String? note;
  final String createdAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.accountType = AccountType.customer,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'account_type': accountType,
    'note': note,
    'created_at': createdAt,
  };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
    id: m['id'],
    name: m['name'],
    phone: m['phone'],
    accountType: m['account_type'] ?? AccountType.customer,
    note: m['note'],
    createdAt: m['created_at'],
  );
}
