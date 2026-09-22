class AccountType {
  static const String customer = 'customer';
  static const String supplier = 'supplier';
  static const String other = 'other';

  static const Map<String, String> labelsAr = {
    customer: 'عميل',
    supplier: 'مورد',
    other: 'أخرى',
  };

  static List<String> get all => [customer, supplier, other];
}
