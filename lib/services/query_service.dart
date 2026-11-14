import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'parser_service.dart';

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
  /// هل الجملة استعلام عن كشف/رصيد حساب؟
  /// يستخدم محلّل النوايا الموحد حتى لا تختلف النتيجة بين مسارات الصوت.
  /// أوامر الإرسال والطباعة لها نوايا مستقلة ولا تمر من هنا.
  static bool isQuery(String text) {
    if (text.trim().isEmpty) return false;
    return ParserService.parsePartial(text).intent == 'statement';
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
      // ✅ إصلاح: آخر 3 عمليات لكن مرتبة من الأقدم للأحدث
      final recent = txs.take(3).toList().reversed.toList();
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

// Query Service v1: خدمة الاستعلام الأساسية (رصيد / كشف حساب)
// Query Service v2: ربط keywords_service (كلمات قابلة للتعديل)
// Query Service v2.1: ترتيب آخر 3 عمليات من الأقدم للأحدث (reversed بعد take)
