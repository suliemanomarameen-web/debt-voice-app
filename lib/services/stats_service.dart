import '../db/database_helper.dart';

class CustomerStat {
  final int id;
  final String name;
  final double balance;
  CustomerStat({required this.id, required this.name, required this.balance});
}

class MonthlyPoint {
  final String month;
  final double debt;
  final double payment;
  MonthlyPoint({required this.month, required this.debt, required this.payment});
}

class StatsService {
  /// 🆕 يستثني المحذوفين فقط (soft + permanent)
  ///
  /// - يستثني عملاء السلة (is_deleted = 1)
  /// - يستثني المحذوفين نهائياً (is_permanently_deleted = 1)
  /// - لا يحسب إلا المعاملات النشطة
  ///
  /// ⚠️ ملاحظة: الموقوفون (is_active = 0) يظهرون هنا.
  ///    "الموقوف" ≠ "المحذوف" — الدين ما زال قائماً.
  static Future<List<CustomerStat>> topDebtors({int limit = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT c.id, c.name,
        COALESCE(SUM(CASE WHEN t.type='debt' THEN t.amount ELSE 0 END),0) -
        COALESCE(SUM(CASE WHEN t.type='payment' THEN t.amount ELSE 0 END),0) AS bal
      FROM customers c
      LEFT JOIN transactions t ON t.customer_id = c.id
        AND (t.is_deleted = 0 OR t.is_deleted IS NULL)
      WHERE (c.is_deleted = 0 OR c.is_deleted IS NULL)
        AND (c.is_permanently_deleted = 0 OR c.is_permanently_deleted IS NULL)
      GROUP BY c.id
      HAVING bal > 0
      ORDER BY bal DESC
      LIMIT ?
    ''', [limit]);
    return result
        .map((r) => CustomerStat(
              id: r['id'] as int,
              name: r['name'] as String,
              balance: (r['bal'] as num).toDouble(),
            ))
        .toList();
  }

  /// 🆕 يستثني المعاملات المحذوفة من الإحصائيات الشهرية
  ///
  /// ملاحظة تصميمية: لا يستثني العملاء المحذوفين أو الموقوفين،
  /// لأن هذا المخطط يقيس "النشاط التاريخي" في كل شهر.
  /// معاملة دين أُضيفت في يناير ثم حُذف العميل في أكتوبر:
  ///   → تبقى في يناير (كانت نشاطاً حقيقياً في ذلك الوقت).
  ///
  /// فقط المعاملات المحذوفة (soft) تُستثنى، لأنها "لم تكن موجودة أبداً".
  static Future<List<MonthlyPoint>> monthlyTrend({int months = 6}) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('''
      SELECT
        strftime('%Y-%m', created_at) AS m,
        SUM(CASE WHEN type='debt' THEN amount ELSE 0 END) AS d,
        SUM(CASE WHEN type='payment' THEN amount ELSE 0 END) AS p
      FROM transactions
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
      GROUP BY m
      ORDER BY m DESC
      LIMIT ?
    ''', [months]);

    final list = result
        .map((r) => MonthlyPoint(
              month: r['m'] as String,
              debt: (r['d'] as num?)?.toDouble() ?? 0,
              payment: (r['p'] as num?)?.toDouble() ?? 0,
            ))
        .toList();

    return list.reversed.toList();
  }

  /// 🆕 يستثني المحذوفين فقط (soft + permanent) من الملخص
  ///
  /// - LEFT JOIN customers للوصول إلى حالة كل عميل
  /// - استثناء المعاملات المحذوفة
  /// - استثناء معاملات العملاء في السلة
  /// - استثناء معاملات المحذوفين نهائياً
  ///
  /// ⚠️ ملاحظة: الموقوفون (is_active = 0) يظهرون هنا.
  ///    الدين على حساب موقوف ما زال ديناً حقيقياً.
  static Future<Map<String, double>> summary() async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN t.type='debt' THEN t.amount ELSE 0 END),0) AS d,
        COALESCE(SUM(CASE WHEN t.type='payment' THEN t.amount ELSE 0 END),0) AS p,
        COUNT(DISTINCT t.customer_id) AS c
      FROM transactions t
      LEFT JOIN customers cu ON t.customer_id = cu.id
      WHERE (t.is_deleted = 0 OR t.is_deleted IS NULL)
        AND (cu.is_deleted = 0 OR cu.is_deleted IS NULL)
        AND (cu.is_permanently_deleted = 0 OR cu.is_permanently_deleted IS NULL)
    ''');
    final row = r.first;
    final totalDebt = (row['d'] as num).toDouble();
    final totalPaid = (row['p'] as num).toDouble();
    return {
      'total_debt': totalDebt,
      'total_paid': totalPaid,
      'outstanding': totalDebt - totalPaid,
      'customers': (row['c'] as num).toDouble(),
    };
  }
}

// Stats Service v2.2: استثناء المحذوفين فقط (soft + permanent) — إلغاء استثناء الموقوفين
