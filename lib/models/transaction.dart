class Transaction {
  final int? id;
  final int customerId;
  final String? code;
  final String? accountant;
  final String? source; // 🆕 مصدر العملية (overlay/voice/manual/customer_screen)
  final double amount;
  final String currency;
  final String type;
  final String items;
  final String createdAt;

  Transaction({
    this.id,
    required this.customerId,
    this.code,
    this.accountant,
    this.source, // 🆕
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
        'accountant': accountant,
        'source': source, // 🆕
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
        accountant: m['accountant'],
        source: m['source'], // 🆕
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'],
        type: m['type'],
        items: m['items'] ?? '',
        createdAt: m['created_at'],
      );

  /// 🆕 الحصول على معلومات المصدر (أيقونة + نص)
  static ({String label, String emoji, int color}) sourceInfo(String? source) {
    switch (source) {
      case 'overlay':
        return (label: 'الزر العائم', emoji: '🖼️', color: 0xFF9C27B0);
      case 'voice':
        return (label: 'التسجيل الصوتي', emoji: '🎤', color: 0xFF2196F3);
      case 'customer_screen':
        return (label: 'شاشة العميل', emoji: '👤', color: 0xFF4CAF50);
      case 'manual':
      default:
        return (label: 'إضافة يدوية', emoji: '➕', color: 0xFF607D8B);
    }
  }
}
