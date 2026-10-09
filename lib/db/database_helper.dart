import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/log_event.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _db;
  DatabaseHelper._init();

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
      version: 9,
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
        max_balance REAL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        code TEXT UNIQUE,
        accountant TEXT,
        source TEXT,
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
    await db.execute('''
      CREATE TABLE log_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        description TEXT NOT NULL,
        level TEXT NOT NULL,
        category TEXT NOT NULL,
        accountant TEXT,
        related_id TEXT,
        metadata TEXT,
        audio_path TEXT,
        is_acknowledged INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
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
    if (oldV < 5) {
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN accountant TEXT");
      } catch (_) {}
    }
    if (oldV < 6) {
      try {
        await db.execute(
            "ALTER TABLE customers ADD COLUMN is_active INTEGER DEFAULT 1");
      } catch (_) {}
    }
    if (oldV < 7) {
      await _ensureAllColumns(db);
    }
    if (oldV < 8) {
      try {
        await db.execute("ALTER TABLE transactions ADD COLUMN source TEXT");
      } catch (_) {}
    }
    if (oldV < 9) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS log_events(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action TEXT NOT NULL,
            description TEXT NOT NULL,
            level TEXT NOT NULL,
            category TEXT NOT NULL,
            accountant TEXT,
            related_id TEXT,
            metadata TEXT,
            audio_path TEXT,
            is_acknowledged INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      } catch (_) {}
    }
  }

  Future<void> _ensureAllColumns(Database db) async {
    try {
      final customersInfo = await db.rawQuery('PRAGMA table_info(customers)');
      final customersCols =
          customersInfo.map((c) => c['name'] as String).toSet();

      final transactionsInfo =
          await db.rawQuery('PRAGMA table_info(transactions)');
      final transactionsCols =
          transactionsInfo.map((c) => c['name'] as String).toSet();

      if (!customersCols.contains('is_active')) {
        await db.execute(
            "ALTER TABLE customers ADD COLUMN is_active INTEGER DEFAULT 1");
      }
      if (!customersCols.contains('max_balance')) {
        await db.execute("ALTER TABLE customers ADD COLUMN max_balance REAL");
      }
      if (!transactionsCols.contains('code')) {
        await db.execute("ALTER TABLE transactions ADD COLUMN code TEXT");
      }
      if (!transactionsCols.contains('accountant')) {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN accountant TEXT");
      }
      if (!transactionsCols.contains('source')) {
        await db.execute("ALTER TABLE transactions ADD COLUMN source TEXT");
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS used_codes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT UNIQUE NOT NULL,
          type TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS log_events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          description TEXT NOT NULL,
          level TEXT NOT NULL,
          category TEXT NOT NULL,
          accountant TEXT,
          related_id TEXT,
          metadata TEXT,
          audio_path TEXT,
          is_acknowledged INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings(
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    } catch (e) {
      debugPrint('❌ [DB] Error: $e');
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

  Future<List<Customer>> activeCustomers() async {
    final db = await database;
    try {
      final r = await db.query('customers',
          where: 'is_active = 1 OR is_active IS NULL',
          orderBy: 'name ASC');
      return r.map((e) => Customer.fromMap(e)).toList();
    } catch (e) {
      return allCustomers();
    }
  }

  Future<List<Customer>> inactiveCustomers() async {
    final db = await database;
    try {
      final r = await db.query('customers',
          where: 'is_active = 0', orderBy: 'name ASC');
      return r.map((e) => Customer.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
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

  Future<int> setCustomerActive(int id, bool active) async {
    final db = await database;
    try {
      final r = await db.update(
        'customers',
        {'is_active': active ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      _notifyChanged();
      return r;
    } catch (e) {
      try {
        await db.execute(
            "ALTER TABLE customers ADD COLUMN is_active INTEGER DEFAULT 1");
        final r = await db.update(
          'customers',
          {'is_active': active ? 1 : 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        _notifyChanged();
        return r;
      } catch (e2) {
        return 0;
      }
    }
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

  Future<bool> transactionExistsRecent({
    required int customerId,
    required double amount,
    required String type,
    Duration window = const Duration(seconds: 30),
  }) async {
    final db = await database;
    final since = DateTime.now().subtract(window).toIso8601String();

    final r = await db.query(
      'transactions',
      where: 'customer_id = ? AND amount = ? AND type = ? AND created_at > ?',
      whereArgs: [customerId, amount, type, since],
      limit: 1,
    );
    return r.isNotEmpty;
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
    } catch (e) {
      debugPrint('❌ updateCodesPrefix error: $e');
    }

    _notifyChanged();
    return updatedCount;
  }

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

  // ============ إدارة المحاسبين ============
  Future<List<String>> getAllAccountants() async {
    final db = await database;
    try {
      final r = await db.rawQuery('''
        SELECT DISTINCT accountant
        FROM transactions
        WHERE accountant IS NOT NULL AND accountant != ''
        ORDER BY accountant ASC
      ''');
      return r
          .map((row) => row['accountant'] as String?)
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ============ سجل الأحداث ============
  Future<int> insertLog(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('log_events', data);
  }

  Future<List<Map<String, dynamic>>> getLogsRaw({
    String? level,
    String? category,
    String? fromDate,
    String? toDate,
    String? searchQuery,
    bool onlyPending = false,
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (level != null) {
      where.add('level = ?');
      args.add(level);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    if (fromDate != null) {
      where.add('created_at >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('created_at <= ?');
      args.add(toDate);
    }
    if (onlyPending) {
      where.add('is_acknowledged = 0');
      where.add("(level = 'error' OR level = 'warning')");
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      where.add('(action LIKE ? OR description LIKE ? OR accountant LIKE ?)');
      final q = '%${searchQuery.trim()}%';
      args.add(q);
      args.add(q);
      args.add(q);
    }

    return db.query(
      'log_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> deleteLog(int id) async {
    final db = await database;
    return db.delete('log_events', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteLogsOlderThan(String cutoffIso) async {
    final db = await database;
    return db.delete('log_events',
        where: 'created_at < ?', whereArgs: [cutoffIso]);
  }

  Future<int> clearAllLogs() async {
    final db = await database;
    return db.delete('log_events');
  }

  Future<int> acknowledgeLog(int id) async {
    final db = await database;
    return db.update(
      'log_events',
      {'is_acknowledged': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> acknowledgeAllLogs() async {
    final db = await database;
    return db.update(
      'log_events',
      {'is_acknowledged': 1},
      where: 'is_acknowledged = 0',
    );
  }

  Future<int> getPendingLogsCount() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM log_events
      WHERE is_acknowledged = 0
        AND (level = 'error' OR level = 'warning')
    ''');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<Map<String, dynamic>> getLogsStats() async {
    final db = await database;
    final total = await db.rawQuery('SELECT COUNT(*) AS c FROM log_events');
    final errors = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM log_events WHERE level = 'error'");
    final warnings = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM log_events WHERE level = 'warning'");
    final today = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM log_events WHERE created_at >= ?",
        [
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
              .toIso8601String()
        ]);
    final pending = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM log_events
      WHERE is_acknowledged = 0
        AND (level = 'error' OR level = 'warning')
    ''');

    return {
      'total': (total.first['c'] as int?) ?? 0,
      'errors': (errors.first['c'] as int?) ?? 0,
      'warnings': (warnings.first['c'] as int?) ?? 0,
      'today': (today.first['c'] as int?) ?? 0,
      'pending': (pending.first['c'] as int?) ?? 0,
    };
  }

  Future<int> countLogs() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM log_events');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOldestLogs(int count) async {
    final db = await database;
    return db.query('log_events', orderBy: 'created_at ASC', limit: count);
  }

  // ============ الإعدادات ============
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final r = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (r.isEmpty) return null;
    return r.first['value'] as String?;
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
