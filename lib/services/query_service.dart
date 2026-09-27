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
  /// هل الجملة طلب استعلام؟ (كم عند / كم عليه / كم له / وش معه / رصيد)
  static bool isQuery(String text) {
    final t = text.toLowerCase();
    const queryWords = [
      'كم عنده', 'كم عندها', 'كم عند',
      'كم عليه', 'كم عليها', 'كم عليه؟',
      'كم له', 'كم لها',
      'كم باقي له', 'كم باقي عليها',
      'ماذا معه', 'ماذا معها', 'ماذا مع',
      'معه كم', 'معها كم',
      'رصيد', 'حساب', 'كشف',
      'what does', 'how much', 'balance',
    ];
    return queryWords.any((w) => t.contains(w));
  }

  /// استخرج اسم الزبون من سؤال الاستعلام
  static String? extractQueryName(String text) {
    // الأنماط:
    // "كم عند محمد عمر" / "كم عنده محمد" / "محمد كم عليه"
    // "كم باقي لمحمد" / "ماذا مع محمد" / "رصيد محمد"

    final patterns = [
      // كم/ماذا + عند/عليه/له/مع + الاسم
      RegExp(r'(?:كم|ماذا)\s+(?:عند|عنده|عندها|عليه|عليها|له|لها|مع|معه|معها)\s+(.+)'),
      RegExp(r'(?:كم|ماذا)\s+(?:باقي|متبقي)\s+(?:ل|لـ)?\s*(.+)'),
      // الاسم + كم/رصيد
      RegExp(r'^(.+?)\s+(?:كم|رصيد)'),
      // رصيد/حساب + الاسم
      RegExp(r'(?:رصيد|حساب|كشف)\s+(?:حساب)?\s*(.+)'),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m != null) {
        var name = m.group(1)!.trim();
        // احذف علامات الترقيم والكلمات الزائدة
        name = name.replaceAll(RegExp(r'[?؟,.!]+$'), '');
        name = name.replaceAll(RegExp(r'^(?:من|ل|لـ)\s+'), '');
        name = name.trim();
        if (name.isNotEmpty && name.length <= 40) {
          return name;
        }
      }
    }

    // احتياطي: خذ آخر كلمة
    final words = text.split(RegExp(r'\s+'));
    for (int i = words.length - 1; i >= 0; i--) {
      final w = words[i].replaceAll(RegExp(r'[?؟,.!]+$'), '');
      if (w.length > 2 &&
          !['كم', 'عند', 'عليه', 'له', 'مع', 'رصيد', 'حساب', 'ماذا'].contains(w)) {
        return w;
      }
    }
    return null;
  }

  /// نفّذ الاستعلام وأعد النتيجة
  static Future<QueryResult> query(String text) async {
    final name = extractQueryName(text);
    if (name == null || name.isEmpty) {
      return QueryResult(
        customerName: '',
        balance: 0,
        hasAccount: false,
        spokenAnswer: 'لم أفهم اسم الحساب. قل: كم عند محمد',
      );
    }

    final db = DatabaseHelper.instance;
    final exact = await db.findExactCustomer(name);

    if (exact != null) {
      return _buildResult(exact, db);
    }

    final partial = await db.findCustomersContaining(name);

    if (partial.isEmpty) {
      return QueryResult(
        customerName: name,
        balance: 0,
        hasAccount: false,
        spokenAnswer: 'لا يوجد حساب باسم $name',
      );
    }

    if (partial.length == 1) {
      return _buildResult(partial.first, db);
    }

    // أكثر من مطابقة → اطلب توضيحاً
    final names = partial.take(3).map((c) => c.name).join('، أو ');
    return QueryResult(
      customerName: name,
      balance: 0,
      hasAccount: false,
      spokenAnswer: 'يوجد أكثر من حساب: $names. حدد الاسم بدقة.',
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

    // أضف آخر 3 عمليات منطوقة
    if (txs.isNotEmpty) {
      final recent = txs.take(3).toList();
      final parts = <String>[];
      for (final t in recent) {
        final label = t.type == 'debt' ? '' : 'دفع ';
        final items = t.items.isEmpty ? '' : ' ${t.items}';
        parts.add('$label${t.amount.toStringAsFixed(0)}$items');
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
