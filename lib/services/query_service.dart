import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';

class QueryResult {
  final String customerName;
  final double balance;
  final bool hasAccount;
  final String spokenAnswer;
  final List<Transaction> transactions;

  QueryResult({
    required this.customerName,
    required this.balance,
    required this.hasAccount,
    required this.spokenAnswer,
    this.transactions = const [],
  });
}

class QueryService {
  /// هل الجملة استعلام؟ (وليس تسجيل معاملة)
  static bool isQuery(String text) {
    final t = text.toLowerCase().trim();

    // 🔑 إذا كانت الجملة تحتوي على فعل تسجيل → ليست استعلاماً
    const recordVerbs = [
      'سجل على', 'سجل ل', 'سجل',
      'دفع', 'وصل',
      'مرتجع', 'استلم', 'استلمت', 'سدد',
    ];
    final hasRecordVerb = recordVerbs.any((v) => t.contains(v));

    // إذا كانت جملة تسجيل → نتحقق من "كم" أولاً
    if (hasRecordVerb) {
      const queryOnlyWords = [
        'كم عنده', 'كم عندها', 'كم عند',
        'كم عليه', 'كم عليها',
        'كم له', 'كم لها',
        'كم باقي', 'ماذا مع',
        'how much', 'what does',
      ];
      if (queryOnlyWords.any((w) => t.contains(w))) return true;
      return false; // جملة تسجيل
    }

    // 🔑 كلمات الاستعلام الواضحة
    const queryWords = [
      'كم عنده', 'كم عندها', 'كم عند',
      'كم عليه', 'كم عليها',
      'كم له', 'كم لها',
      'كم باقي', 'كم باقي له', 'كم باقي عليها',
      'ماذا معه', 'ماذا معها', 'ماذا مع',
      'معه كم', 'معها كم',
      'how much', 'what does', 'balance',
    ];
    if (queryWords.any((w) => t.contains(w))) return true;

    // 🔑 "رصيد" أو "كشف" — نتحقق: قد تكون صنفاً
    final words = t.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final lastWord = words.last;
      if (['رصيد', 'كشف'].contains(lastWord)) {
        // إذا كان قبلها رقم → فهي صنف (وليس استعلاماً)
        if (words.length >= 2) {
          final beforeLast = words[words.length - 2];
          if (RegExp(r'\d').hasMatch(beforeLast)) {
            return false; // رقم + رصيد = صنف
          }
        }
      }
    }

    // "رصيد محمد" أو "كشف حساب محمد" → استعلام
    if (t.startsWith('رصيد ') ||
        t.startsWith('كشف ') ||
        t.startsWith('حساب ')) {
      return true;
    }

    return false;
  }

  /// استخراج اسم الزبون من سؤال الاستعلام
  static String? extractQueryName(String text) {
    final patterns = [
      RegExp(
          r'(?:كم|ماذا)\s+(?:عند|عنده|عندها|عليه|عليها|له|لها|مع|معه|معها)\s+(.+)'),
      RegExp(r'(?:كم|ماذا)\s+(?:باقي|متبقي)\s+(?:ل|لـ)?\s*(.+)'),
      RegExp(r'^(.+?)\s+(?:كم|رصيد)'),
      RegExp(r'(?:رصيد|حساب|كشف)\s+(?:حساب)?\s*(.+)'),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        var name = m.group(1)!.trim();
        name = name.replaceAll(RegExp(r'[?؟,.!]+$'), '');
        name = name.replaceAll(RegExp(r'^(?:من|ل|لـ)\s+'), '');
        name = name.trim();
        if (name.isNotEmpty && name.length <= 40) {
          return name;
        }
      }
    }

    final words = text.split(RegExp(r'\s+'));
    for (int i = words.length - 1; i >= 0; i--) {
      final w = words[i].replaceAll(RegExp(r'[?؟,.!]+$'), '');
      if (w.length > 2 &&
          !['كم', 'عند', 'عليه', 'له', 'مع', 'رصيد', 'حساب', 'ماذا']
              .contains(w)) {
        return w;
      }
    }
    return null;
  }

  static Future<QueryResult> query(String text) async {
    final name = extractQueryName(text);
    if (name == null || name.isEmpty) {
      return QueryResult(
        customerName: '',
        balance: 0,
        hasAccount: false,
        spokenAnswer: 'لم أفهم الاسم. قل: كم عند محمد',
      );
    }

    final db = DatabaseHelper.instance;
    final exact = await db.findExactCustomer(name);

    if (exact != null) return _buildResult(exact, db);

    final partial = await db.findCustomersContaining(name);

    if (partial.isEmpty) {
      return QueryResult(
        customerName: name,
        balance: 0,
        hasAccount: false,
        spokenAnswer: 'لا يوجد حساب باسم $name',
      );
    }

    if (partial.length == 1) return _buildResult(partial.first, db);

    final names = partial.take(3).map((c) => c.name).join('، أو ');
    return QueryResult(
      customerName: name,
      balance: 0,
      hasAccount: false,
      spokenAnswer: 'يوجد أكثر من حساب: $names. حدد الاسم بدقة',
    );
  }

  static Future<QueryResult> _buildResult(
      Customer c, DatabaseHelper db) async {
    final balance = await db.customerBalance(c.id!);
    final txs = await db.customerTransactions(c.id!);

    String answer;
    if (balance > 0) {
      answer = '${c.name} عليه ${balance.toStringAsFixed(0)} ريال';
    } else if (balance < 0) {
      answer = '${c.name} باقي له ${(-balance).toStringAsFixed(0)} ريال';
    } else {
      answer = 'حساب ${c.name} متوازن، لا ديون ولا مستحقات';
    }

    if (txs.isNotEmpty) {
      final recent = txs.take(3).toList();
      final parts = <String>[];
      for (final t in recent) {
        final isDebt = t.type == 'debt';
        final isReturn = t.items.startsWith('مرتجع');
        String prefix;
        if (isReturn) {
          prefix = 'مرتجع';
        } else if (isDebt) {
          prefix = 'دين';
        } else {
          prefix = 'دفع';
        }

        final items = t.items.isEmpty
            ? ''
            : ' ${t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '')}';
        parts.add('$prefix ${t.amount.toStringAsFixed(0)}$items');
      }
      answer += '. آخر العمليات: ${parts.join("، ثم ")}';
    }

    return QueryResult(
      customerName: c.name,
      balance: balance,
      hasAccount: true,
      spokenAnswer: answer,
      transactions: txs,
    );
  }
}
