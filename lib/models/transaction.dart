class Transaction {
  final int? id;
  final int customerId;
  final String? code; // رمز العملية (مثل D-0001, P-0002)
  final double amount;
  final String currency;
  final String type;
  final String items;
  final String createdAt;

  Transaction({
    this.id,
    required this.customerId,
    this.code,
    required this.amount,
    this.currency = 'YER',
    required this.type,
    this.items = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'code': code,
        'amount': amount,
        'currency': currency,
        'type': type,
        'items': items,
        'created_at': createdAt,
      };

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: m['id'],
        customerId: m['customer_id'],
        code: m['code'],
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'],
        type: m['type'],
        items: m['items'] ?? '',
        createdAt: m['created_at'],
      );
}
