import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../models/customer.dart';
import '../models/transaction.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _db;
  DatabaseHelper._init();

  /// يُستدعى بعد أي تعديل في البيانات (للمزامنة)
  static void Function()? onDataChanged;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('debt_book.db');
    return _db!;
  }

  Future<Database> _initDB(String file) async {
    final path = join(await getDatabasesPath(), file);
    return openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgrade,
    );
  }

  Future _createDB(Database db, int v) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        account_type TEXT DEFAULT 'customer',
        note TEXT,
        photo_path TEXT,
        category TEXT DEFAULT 'normal',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        code TEXT UNIQUE,
        amount REAL NOT NULL,
        currency TEXT DEFAULT 'YER',
        type TEXT NOT NULL,
        items TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE used_codes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future _upgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      try {
        await db.execute(
            "ALTER TABLE customers ADD COLUMN account_type TEXT DEFAULT 'customer'");
        await db.execute("ALTER TABLE customers ADD COLUMN note TEXT");
      } catch (_) {}
    }
    if (oldV < 3) {
      try {
        await db.execute("ALTER TABLE customers ADD COLUMN photo_path TEXT");
        await db.execute(
            "ALTER TABLE customers ADD COLUMN category TEXT DEFAULT 'normal'");
      } catch (_) {}
    }
    if (oldV < 4) {
      try {
        await db.execute("ALTER TABLE transactions ADD COLUMN code TEXT");
        await db.execute('''
          CREATE TABLE IF NOT EXISTS used_codes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT UNIQUE NOT NULL,
            type TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
  }

  void _notifyChanged() {
    try {
      onDataChanged?.call();
    } catch (_) {}
  }

  // ============ الزبائن ============
  Future<int> insertCustomer(Customer c) async {
    final db = await database;
    final id = await db.insert('customers', c.toMap());
    _notifyChanged();
    return id;
  }

  Future<int> insertCustomerRaw(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('customers', data);
  }

  Future<int> updateCustomer(Customer c) async {
    final db = await database;
    final r = await db.update('customers', c.toMap(),
        where: 'id = ?', whereArgs: [c.id]);
    _notifyChanged();
    return r;
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    await db.delete('transactions',
        where: 'customer_id = ?', whereArgs: [id]);
    final r = await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    _notifyChanged();
    return r;
  }

  Future<List<Customer>> allCustomers() async {
    final db = await database;
    final r = await db.query('customers', orderBy: 'name ASC');
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<List<Customer>> customersByCategory(String category) async {
    final db = await database;
    final r = await db.query('customers',
        where: 'category = ?', whereArgs: [category], orderBy: 'name ASC');
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<Customer?> findExactCustomer(String name) async {
    final db = await database;
    final r = await db.query('customers',
        where: 'name = ?', whereArgs: [name], limit: 1);
    if (r.isEmpty) return null;
    return Customer.fromMap(r.first);
  }

  Future<List<Customer>> findCustomersContaining(String name) async {
    final db = await database;
    final r = await db.query('customers',
        where: 'name LIKE ?', whereArgs: ['%$name%'], orderBy: 'name ASC');
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<int?> findCustomerIdByNameAndDate(
      String name, String createdAt) async {
    final db = await database;
    final r = await db.query('customers',
        where: 'name = ? AND created_at = ?',
        whereArgs: [name, createdAt],
        limit: 1);
    if (r.isEmpty) return null;
    return r.first['id'] as int?;
  }

  // ============ المعاملات ============
  Future<int> insertTransaction(Transaction t) async {
    final db = await database;
    final id = await db.insert('transactions', t.toMap());
    if (t.code != null && t.code!.isNotEmpty) {
      try {
        await db.insert('used_codes', {
          'code': t.code,
          'type': t.type,
          'created_at': t.createdAt,
        });
      } catch (_) {}
    }
    _notifyChanged();
    return id;
  }

  Future<int> insertTransactionRaw(Map<String, dynamic> data) async {
    final db = await database;
    final id = await db.insert('transactions', data);
    final code = data['code'] as String?;
    if (code != null && code.isNotEmpty) {
      try {
        await db.insert('used_codes', {
          'code': code,
          'type': data['type'] ?? 'debt',
          'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
    return id;
  }

  Future<int> updateTransaction(Transaction t) async {
    final db = await database;
    final r = await db.update('transactions', t.toMap(),
        where: 'id = ?', whereArgs: [t.id]);
    _notifyChanged();
    return r;
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    final r = await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    _notifyChanged();
    return r;
  }

  Future<Transaction?> getTransaction(int id) async {
    final db = await database;
    final r = await db.query('transactions',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    return Transaction.fromMap(r.first);
  }

  Future<List<Transaction>> customerTransactions(int customerId) async {
    final db = await database;
    final r = await db.query('transactions',
        where: 'customer_id = ?', whereArgs: [customerId],
        orderBy: 'created_at DESC');
    return r.map((e) => Transaction.fromMap(e)).toList();
  }

  Future<double> customerBalance(int customerId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END),0) AS d,
        COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END),0) AS p
      FROM transactions WHERE customer_id = ?
    ''', [customerId]);
    final row = r.first;
    return (row['d'] as num).toDouble() - (row['p'] as num).toDouble();
  }

  Future<double> totalDebts() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END),0) AS d,
        COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END),0) AS p
      FROM transactions
    ''');
    final row = r.first;
    return (row['d'] as num).toDouble() - (row['p'] as num).toDouble();
  }

  Future<bool> transactionExists({
    required int customerId,
    required double amount,
    required String type,
    required String createdAt,
  }) async {
    final db = await database;
    final r = await db.query('transactions',
        where: 'customer_id = ? AND amount = ? AND type = ? AND created_at = ?',
        whereArgs: [customerId, amount, type, createdAt],
        limit: 1);
    return r.isNotEmpty;
  }

  // ============ إدارة الرموز ============

  Future<bool> codeExists(String code) async {
    final db = await database;
    final r = await db.query('used_codes',
        where: 'code = ?', whereArgs: [code], limit: 1);
    return r.isNotEmpty;
  }

  Future<void> addUsedCode({
    required String code,
    required String type,
  }) async {
    final db = await database;
    try {
      await db.insert('used_codes', {
        'code': code,
        'type': type,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<int> getMaxSequence(String type) async {
    final db = await database;
    final r = await db.query('used_codes',
        where: 'type = ?', whereArgs: [type], columns: ['code']);
    int maxSeq = 0;
    for (final row in r) {
      final code = row['code'] as String? ?? '';
      final parts = code.split('-');
      if (parts.length >= 2) {
        final numPart = int.tryParse(parts.sublist(1).join('-'));
        if (numPart != null && numPart > maxSeq) {
          maxSeq = numPart;
        }
      }
    }
    return maxSeq;
  }

  /// ============ تحديث رموز العمليات القديمة ============
  Future<int> updateCodesPrefix({
    required String oldPrefix,
    required String newPrefix,
  }) async {
    if (oldPrefix.isEmpty || newPrefix.isEmpty) return 0;
    if (oldPrefix == newPrefix) return 0;

    final db = await database;
    int updatedCount = 0;

    try {
      final transactions = await db.query(
        'transactions',
        where: 'code LIKE ?',
        whereArgs: ['$oldPrefix-%'],
      );

      for (final row in transactions) {
        final oldCode = row['code'] as String?;
        if (oldCode == null || oldCode.isEmpty) continue;

        final newCode = newPrefix + oldCode.substring(oldPrefix.length);

        final exists = await db.query(
          'transactions',
          where: 'code = ? AND id != ?',
          whereArgs: [newCode, row['id']],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;

        await db.update(
          'transactions',
          {'code': newCode},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        updatedCount++;

        try {
          await db.delete('used_codes',
              where: 'code = ?', whereArgs: [oldCode]);
          await db.insert('used_codes', {
            'code': newCode,
            'type': row['type'] ?? 'debt',
            'created_at':
                row['created_at'] ?? DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      debugPrint(
          '✅ Updated $updatedCount transaction codes: $oldPrefix → $newPrefix');
    } catch (e) {
      debugPrint('❌ updateCodesPrefix error: $e');
    }

    _notifyChanged();
    return updatedCount;
  }

  /// إحصائيات الرموز (للعرض)
  Future<Map<String, int>> getCodesStats() async {
    final db = await database;
    final all = await db.query('used_codes', columns: ['type']);

    final stats = <String, int>{'debt': 0, 'payment': 0, 'return': 0};
    for (final row in all) {
      final t = row['type'] as String? ?? 'debt';
      stats[t] = (stats[t] ?? 0) + 1;
    }
    return stats;
  }

  // ============ أدوات للمزامنة ============
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('customers');
    await db.delete('used_codes');
    _notifyChanged();
  }

  Future<List<Map<String, dynamic>>> allTransactionsRaw() async {
    final db = await database;
    return db.query('transactions');
  }

  Future<List<Map<String, dynamic>>> allCustomersRaw() async {
    final db = await database;
    return db.query('customers');
  }

  Future<List<Map<String, dynamic>>> allUsedCodesRaw() async {
    final db = await database;
    return db.query('used_codes');
  }

  Future<List<Map<String, dynamic>>> getAllTransactionsWithCustomer() async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.*, c.name AS customer_name, c.phone AS customer_phone
      FROM transactions t
      LEFT JOIN customers c ON t.customer_id = c.id
      ORDER BY t.created_at DESC
    ''');
  }
}
