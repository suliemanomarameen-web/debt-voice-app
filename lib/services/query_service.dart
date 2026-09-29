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
  /// هل الجملة استعلام؟
  static bool isQuery(String text) {
    final t = text.toLowerCase();
    const queryWords = [
      'كم عنده', 'كم عندها', 'كم عند',
      'كم عليه', 'كم عليها',
      'كم له', 'كم لها',
      'كم باقي له', 'كم باقي عليها', 'كم باقي لمحمد',
      'ماذا معه', 'ماذا معها', 'ماذا مع',
      'معه كم', 'معها كم',
      'رصيد', 'كشف',
      'what does', 'how much', 'balance',
    ];
    return queryWords.any((w) => t.contains(w));
  }

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
        spokenAnswer: 'لَمْ أَفْهَمِ الاِسْمَ. قُلْ: كَمْ عِنْدَ مُحَمَّد',
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
        spokenAnswer: 'لَا يُوجَدُ حِسَابٌ بِاسْمِ $name',
      );
    }

    if (partial.length == 1) return _buildResult(partial.first, db);

    final names = partial.take(3).map((c) => c.name).join('، أَوْ ');
    return QueryResult(
      customerName: name,
      balance: 0,
      hasAccount: false,
      spokenAnswer:
          'يُوجَدُ أَكْثَرُ مِنْ حِسَاب: $names. حَدِّدِ الاِسْمَ بِدِقَّة',
    );
  }

  static Future<QueryResult> _buildResult(
      Customer c, DatabaseHelper db) async {
    final balance = await db.customerBalance(c.id!);
    final txs = await db.customerTransactions(c.id!);

    // بناء النص المنطوق (مشكّل بالكامل)
    String answer;
    if (balance > 0) {
      answer =
          '${c.name} عَلَيْهِ ${_numToWords(balance)} رِيَال';
    } else if (balance < 0) {
      answer =
          '${c.name} بَاقِي لَهُ ${_numToWords(-balance)} رِيَال';
    } else {
      answer = 'حِسَابُ ${c.name} مُتَوَازِن، لَا دُيُونَ وَلَا مُسْتَحَقَّات';
    }

    // أضف آخر 3 عمليات
    if (txs.isNotEmpty) {
      final recent = txs.take(3).toList();
      final parts = <String>[];
      for (final t in recent) {
        final isDebt = t.type == 'debt';
        final isReturn = t.items.startsWith('مرتجع');
        String prefix;
        if (isReturn) {
          prefix = 'مُرْتَجَع';
        } else if (isDebt) {
          prefix = 'دَيْن';
        } else {
          prefix = 'دَفْع';
        }

        final amount = _numToWords(t.amount);
        final items = t.items.isEmpty
            ? ''
            : ' ${t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '')}';
        parts.add('$prefix $amount$items');
      }
      answer += '. آخِرُ العَمَلِيَّات: ${parts.join("، ثُمَّ ")}';
    }

    return QueryResult(
      customerName: c.name,
      balance: balance,
      hasAccount: true,
      spokenAnswer: answer,
      transactions: txs,
    );
  }

  /// تحويل الرقم إلى كلمات عربية مشكّلة
  static String _numToWords(double num) {
    final n = num.round();
    if (n == 0) return 'صِفْر';
    if (n < 0) return 'سَالِب ${_numToWords((-n).toDouble())}';

    const ones = [
      '', 'وَاحِد', 'اِثْنَان', 'ثَلَاثَة', 'أَرْبَعَة', 'خَمْسَة',
      'سِتَّة', 'سَبْعَة', 'ثَمَانِيَة', 'تِسْعَة', 'عَشَرَة',
      'أَحَدَ عَشَر', 'اِثْنَا عَشَر', 'ثَلَاثَةَ عَشَر', 'أَرْبَعَةَ عَشَر',
      'خَمْسَةَ عَشَر', 'سِتَّةَ عَشَر', 'سَبْعَةَ عَشَر', 'ثَمَانِيَةَ عَشَر',
      'تِسْعَةَ عَشَر',
    ];
    const tens = [
      '', '', 'عِشْرُون', 'ثَلَاثُون', 'أَرْبَعُون', 'خَمْسُون',
      'سِتُّون', 'سَبْعُون', 'ثَمَانُون', 'تِسْعُون',
    ];

    if (n < 20) return ones[n];
    if (n < 100) {
      final t = n ~/ 10;
      final o = n % 10;
      if (o == 0) return tens[t];
      return '${ones[o]} وَ${tens[t]}';
    }
    if (n < 1000) {
      final h = n ~/ 100;
      final rest = n % 100;
      final hStr = h == 1
          ? 'مِائَة'
          : h == 2
              ? 'مِائَتَاْن'
              : '${ones[h]} مِائَة';
      if (rest == 0) return hStr;
      return '$hStr و${_numToWords(rest.toDouble())}';
    }
    if (n < 1000000) {
      final k = n ~/ 1000;
      final rest = n % 1000;
      final kStr = k == 1
          ? 'أَلْف'
          : k == 2
              ? 'أَلْفَان'
              : '${_numToWords(k.toDouble())} آلَاف';
      if (rest == 0) return kStr;
      return '$kStr و${_numToWords(rest.toDouble())}';
    }
    return n.toString();
  }
}
