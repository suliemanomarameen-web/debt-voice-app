import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/log_event.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _db;
  DatabaseHelper._init();

  static void Function()? onDataChanged;

  static const _uuid = Uuid();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('debt_book.db');
    return _db!;
  }

  Future<Database> _initDB(String file) async {
    final path = join(await getDatabasesPath(), file);
    return openDatabase(
      path,
      version: 13,
      onCreate: _createDB,
      onUpgrade: _upgrade,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // إنشاء الجداول (v13)
  // ═══════════════════════════════════════════════════════════
  Future _createDB(Database db, int v) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        account_type TEXT DEFAULT 'customer',
        note TEXT,
        photo_path TEXT,
        category TEXT DEFAULT 'normal',
        max_balance REAL,
        is_active INTEGER DEFAULT 1,
        created_by TEXT,
        updated_by TEXT,
        updated_at TEXT,
        is_deleted INTEGER DEFAULT 0,
        is_permanently_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_id TEXT UNIQUE,
        customer_id INTEGER NOT NULL,
        code TEXT UNIQUE,
        accountant TEXT,
        source TEXT,
        amount REAL NOT NULL,
        currency TEXT DEFAULT 'YER',
        type TEXT NOT NULL,
        items TEXT,
        updated_by TEXT,
        updated_at TEXT,
        last_modified_by TEXT,
        last_modified_from TEXT,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
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
        needs_acknowledgement INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE deleted_tombstones(
        cloud_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');
  }

  // ═══════════════════════════════════════════════════════════
  // ترقية قاعدة البيانات
  // ═══════════════════════════════════════════════════════════
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

    if (oldV < 10) {
      try {
        await _addColumnIfMissing(db, 'customers', 'cloud_id', 'TEXT');
        await _addColumnIfMissing(db, 'customers', 'created_by', 'TEXT');
        await _addColumnIfMissing(db, 'customers', 'updated_by', 'TEXT');
        await _addColumnIfMissing(db, 'customers', 'updated_at', 'TEXT');
        await _addColumnIfMissing(db, 'customers', 'is_deleted',
            'INTEGER DEFAULT 0');
        await _addColumnIfMissing(db, 'customers', 'deleted_at', 'TEXT');
        await _addColumnIfMissing(db, 'customers', 'deleted_by', 'TEXT');

        await _addColumnIfMissing(db, 'transactions', 'cloud_id', 'TEXT');
        await _addColumnIfMissing(db, 'transactions', 'updated_by', 'TEXT');
        await _addColumnIfMissing(db, 'transactions', 'updated_at', 'TEXT');
        await _addColumnIfMissing(
            db, 'transactions', 'last_modified_by', 'TEXT');
        await _addColumnIfMissing(
            db, 'transactions', 'last_modified_from', 'TEXT');
        await _addColumnIfMissing(db, 'transactions', 'is_deleted',
            'INTEGER DEFAULT 0');
        await _addColumnIfMissing(db, 'transactions', 'deleted_at', 'TEXT');
        await _addColumnIfMissing(db, 'transactions', 'deleted_by', 'TEXT');

        try {
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_customers_is_deleted ON customers(is_deleted)");
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_transactions_is_deleted ON transactions(is_deleted)");
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_customers_cloud_id ON customers(cloud_id)");
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_transactions_cloud_id ON transactions(cloud_id)");
        } catch (_) {}

        try {
          await db.execute(
              "UPDATE customers SET updated_at = created_at WHERE updated_at IS NULL");
          await db.execute(
              "UPDATE transactions SET updated_at = created_at WHERE updated_at IS NULL");
        } catch (_) {}

        debugPrint('✅ [DB] Upgraded to v10 (tracking + soft delete + cloudId)');
      } catch (e) {
        debugPrint('⚠️ [DB v10] $e');
      }
    }

    if (oldV < 11) {
      try {
        await _addColumnIfMissing(
            db, 'log_events', 'needs_acknowledgement', 'INTEGER DEFAULT 0');
        try {
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_log_events_needs_ack ON log_events(needs_acknowledgement)");
        } catch (_) {}
        debugPrint('✅ [DB] Upgraded to v11 (needs_acknowledgement)');
      } catch (e) {
        debugPrint('⚠️ [DB v11] $e');
      }
    }

    if (oldV < 12) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS deleted_tombstones(
            cloud_id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            deleted_at TEXT NOT NULL
          )
        ''');
        debugPrint('✅ [DB] Upgraded to v12 (tombstones)');
      } catch (e) {
        debugPrint('⚠️ [DB v12] $e');
      }
    }

    if (oldV < 13) {
      try {
        await _addColumnIfMissing(
          db, 'customers', 'is_permanently_deleted', 'INTEGER DEFAULT 0',
        );
        try {
          await db.execute(
              "CREATE INDEX IF NOT EXISTS idx_customers_is_perm_deleted "
              "ON customers(is_permanently_deleted)");
        } catch (_) {}
        debugPrint('✅ [DB] Upgraded to v13 (is_permanently_deleted)');
      } catch (e) {
        debugPrint('⚠️ [DB v13] $e');
      }
    }
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final cols = info.map((c) => c['name'] as String).toSet();
      if (!cols.contains(column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    } catch (e) {
      debugPrint('⚠️ _addColumnIfMissing $table.$column: $e');
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
    } catch (e) {
      debugPrint('❌ [DB] Error: $e');
    }
  }

  void _notifyChanged() {
    try {
      onDataChanged?.call();
    } catch (_) {}
  }

  String _now() => DateTime.now().toIso8601String();

  String _generateCloudId() => _uuid.v4();

  // ═══════════════════════════════════════════════════════════
  // فلترة الأعمدة بحسب Schema المحلي
  // ═══════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _sanitizeForTable(
    String table,
    Map<String, dynamic> row,
  ) async {
    try {
      final db = await database;
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (info.isEmpty) return row;

      final validCols = info.map((c) => c['name'] as String).toSet();
      final filtered = <String, dynamic>{};
      final skipped = <String>[];

      for (final entry in row.entries) {
        if (validCols.contains(entry.key)) {
          filtered[entry.key] = entry.value;
        } else {
          skipped.add(entry.key);
        }
      }

      if (skipped.isNotEmpty) {
        debugPrint(
          '⚠️ [DB] Ignored unknown columns in "$table": ${skipped.join(", ")}',
        );
      }

      return filtered;
    } catch (e) {
      debugPrint('❌ [DB] _sanitizeForTable($table): $e');
      return row;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // شواهد القبور (Tombstones)
  // ═══════════════════════════════════════════════════════════

  Future<void> addTombstone({
    required String cloudId,
    required String type,
  }) async {
    try {
      final db = await database;
      await db.insert(
        'deleted_tombstones',
        {
          'cloud_id': cloudId,
          'type': type,
          'deleted_at': _now(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('❌ addTombstone: $e');
    }
  }

  Future<bool> hasTombstone(String cloudId) async {
    try {
      final db = await database;
      final r = await db.query('deleted_tombstones',
          where: 'cloud_id = ?', whereArgs: [cloudId], limit: 1);
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> allTombstonesRaw() async {
    final db = await database;
    return db.query('deleted_tombstones');
  }

  Future<int> clearOldTombstones({int days = 90}) async {
    try {
      final db = await database;
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      return db.delete('deleted_tombstones',
          where: 'deleted_at < ?', whereArgs: [cutoff]);
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الزبائن
  // ═══════════════════════════════════════════════════════════

  Future<int> insertCustomer(Customer c) async {
    final db = await database;
    final map = c.toMap();

    if (map['cloud_id'] == null || (map['cloud_id'] as String).isEmpty) {
      map['cloud_id'] = _generateCloudId();
    }
    map['updated_at'] = map['updated_at'] ?? map['created_at'] ?? _now();

    final id = await db.insert('customers', map);
    _notifyChanged();
    return id;
  }

  Future<int> insertCustomerRaw(Map<String, dynamic> data) async {
    final db = await database;
    if (data['cloud_id'] == null || (data['cloud_id'] as String).isEmpty) {
      data['cloud_id'] = _generateCloudId();
    }
    data['updated_at'] = data['updated_at'] ?? data['created_at'] ?? _now();

    final sanitized = await _sanitizeForTable('customers', data);
    return db.insert('customers', sanitized);
  }

  Future<int> updateCustomer(Customer c, {String? by}) async {
    final db = await database;
    final data = c.toMap();
    data['updated_at'] = _now();
    if (by != null && by.isNotEmpty) data['updated_by'] = by;

    final r = await db.update('customers', data,
        where: 'id = ?', whereArgs: [c.id]);
    _notifyChanged();
    return r;
  }

  Future<int> updateCustomerFields(
      int id, Map<String, dynamic> fields, {String? by}) async {
    if (fields.isEmpty) return 0;
    try {
      final db = await database;
      final data = Map<String, dynamic>.from(fields);
      data['updated_at'] = _now();
      if (by != null && by.isNotEmpty) {
        data['updated_by'] = by;
      }

      final sanitized = await _sanitizeForTable('customers', data);
      final r = await db.update('customers', sanitized,
          where: 'id = ?', whereArgs: [id]);
      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ updateCustomerFields error: $e');
      return 0;
    }
  }

  Future<int> softDeleteCustomer(int id, {String? by}) async {
    try {
      final db = await database;
      final now = _now();

      final r = await db.update(
        'customers',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': by,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await db.update(
        'transactions',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': by,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'customer_id = ?',
        whereArgs: [id],
      );

      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ softDeleteCustomer: $e');
      return 0;
    }
  }

  Future<int> restoreCustomer(int id, {String? by}) async {
    try {
      final db = await database;
      final now = _now();

      final r = await db.update(
        'customers',
        {
          'is_deleted': 0,
          'is_permanently_deleted': 0,
          'deleted_at': null,
          'deleted_by': null,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await db.update(
        'transactions',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_by': null,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'customer_id = ?',
        whereArgs: [id],
      );

      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ restoreCustomer: $e');
      return 0;
    }
  }

  Future<int> hardDeleteCustomer(int id) async {
    try {
      final db = await database;
      final rows = await db.query('customers',
          where: 'id = ?', whereArgs: [id], limit: 1);
      String? cloudId;
      if (rows.isNotEmpty) {
        cloudId = rows.first['cloud_id'] as String?;
      }

      final now = _now();

      final r = await db.update(
        'customers',
        {
          'is_permanently_deleted': 1,
          'is_deleted': 1,
          'deleted_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await db.update(
        'transactions',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'updated_at': now,
        },
        where: 'customer_id = ?',
        whereArgs: [id],
      );

      if (cloudId != null && cloudId.isNotEmpty) {
        await addTombstone(cloudId: cloudId, type: 'customer');
      }

      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ hardDeleteCustomer: $e');
      return 0;
    }
  }

  Future<int> deleteCustomer(int id, {String? by}) async {
    return softDeleteCustomer(id, by: by);
  }

  Future<List<Customer>> allCustomers() async {
    final db = await database;
    final r = await db.query(
      'customers',
      where: '(is_deleted = 0 OR is_deleted IS NULL) '
          'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
      orderBy: 'name ASC',
    );
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<List<Customer>> activeCustomers() async {
    final db = await database;
    try {
      final r = await db.query(
        'customers',
        where: '(is_active = 1 OR is_active IS NULL) '
            'AND (is_deleted = 0 OR is_deleted IS NULL) '
            'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
        orderBy: 'name ASC',
      );
      return r.map((e) => Customer.fromMap(e)).toList();
    } catch (e) {
      return allCustomers();
    }
  }

  Future<List<Customer>> inactiveCustomers() async {
    final db = await database;
    try {
      final r = await db.query(
        'customers',
        where: 'is_active = 0 '
            'AND (is_deleted = 0 OR is_deleted IS NULL) '
            'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
        orderBy: 'name ASC',
      );
      return r.map((e) => Customer.fromMap(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Customer>> allCustomersWithDeleted() async {
    final db = await database;
    final r = await db.query('customers', orderBy: 'name ASC');
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<List<Customer>> getDeletedCustomers() async {
    final db = await database;
    final r = await db.query(
      'customers',
      where: 'is_deleted = 1 '
          'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
      orderBy: 'deleted_at DESC',
    );
    return r.map((e) => Customer.fromMap(e)).toList();
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await database;
    final r = await db.query('customers',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    return Customer.fromMap(r.first);
  }

  Future<Customer?> findExactCustomer(String name) async {
    final db = await database;
    final r = await db.query(
      'customers',
      where: 'name = ? '
          'AND (is_deleted = 0 OR is_deleted IS NULL) '
          'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
      whereArgs: [name],
      limit: 1,
    );
    if (r.isEmpty) return null;
    return Customer.fromMap(r.first);
  }

  Future<List<Customer>> findCustomersContaining(String name) async {
    final db = await database;
    final r = await db.query(
      'customers',
      where: 'name LIKE ? '
          'AND (is_deleted = 0 OR is_deleted IS NULL) '
          'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
      whereArgs: ['%$name%'],
      orderBy: 'name ASC',
    );
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

  Future<int> setCustomerActive(int id, bool active, {String? by}) async {
    final db = await database;
    try {
      final now = _now();
      final r = await db.update(
        'customers',
        {
          'is_active': active ? 1 : 0,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
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

  // ═══════════════════════════════════════════════════════════
  // المعاملات
  // ═══════════════════════════════════════════════════════════

  Future<int> insertTransaction(Transaction t) async {
    final db = await database;
    final map = t.toMap();

    if (map['cloud_id'] == null || (map['cloud_id'] as String).isEmpty) {
      map['cloud_id'] = _generateCloudId();
    }
    map['updated_at'] = map['updated_at'] ?? map['created_at'] ?? _now();

    final id = await db.insert('transactions', map);

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

    if (data['cloud_id'] == null ||
        (data['cloud_id'] as String?)?.isEmpty == true) {
      data['cloud_id'] = _generateCloudId();
    }
    data['updated_at'] = data['updated_at'] ?? data['created_at'] ?? _now();

    final sanitized = await _sanitizeForTable('transactions', data);
    final id = await db.insert('transactions', sanitized);

    final code = data['code'] as String?;
    if (code != null && code.isNotEmpty) {
      try {
        await db.insert('used_codes', {
          'code': code,
          'type': data['type'] ?? 'debt',
          'created_at': data['created_at'] ?? _now(),
        });
      } catch (_) {}
    }
    return id;
  }

  Future<int> updateTransaction(Transaction t, {String? by}) async {
    final db = await database;
    final now = _now();

    final data = t.toMap();
    data['updated_at'] = now;
    if (by != null && by.isNotEmpty) {
      data['updated_by'] = by;
      data['last_modified_by'] = by;
    }

    final r = await db.update('transactions', data,
        where: 'id = ?', whereArgs: [t.id]);
    _notifyChanged();
    return r;
  }

  Future<int> updateTransactionFields(
      int id, Map<String, dynamic> fields, {String? by}) async {
    if (fields.isEmpty) return 0;
    try {
      final db = await database;
      final now = _now();
      final data = Map<String, dynamic>.from(fields);
      data['updated_at'] = now;
      if (by != null && by.isNotEmpty) {
        data['updated_by'] = by;
        data['last_modified_by'] = by;
      }

      final sanitized = await _sanitizeForTable('transactions', data);
      final r = await db.update('transactions', sanitized,
          where: 'id = ?', whereArgs: [id]);
      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ updateTransactionFields error: $e');
      return 0;
    }
  }

  Future<int> softDeleteTransaction(int id, {String? by}) async {
    try {
      final db = await database;
      final now = _now();
      final r = await db.update(
        'transactions',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': by,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ softDeleteTransaction: $e');
      return 0;
    }
  }

  Future<int> restoreTransaction(int id, {String? by}) async {
    try {
      final db = await database;
      final now = _now();
      final r = await db.update(
        'transactions',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_by': null,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ restoreTransaction: $e');
      return 0;
    }
  }

  Future<int> hardDeleteTransaction(int id) async {
    try {
      final db = await database;
      final rows = await db.query('transactions',
          where: 'id = ?', whereArgs: [id], limit: 1);
      String? cloudId;
      if (rows.isNotEmpty) {
        cloudId = rows.first['cloud_id'] as String?;
      }

      final now = _now();
      final r = await db.update(
        'transactions',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (cloudId != null && cloudId.isNotEmpty) {
        await addTombstone(cloudId: cloudId, type: 'transaction');
      }

      _notifyChanged();
      return r;
    } catch (e) {
      return 0;
    }
  }

  Future<int> deleteTransaction(int id, {String? by}) async {
    return softDeleteTransaction(id, by: by);
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
        where: 'customer_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [customerId],
        orderBy: 'created_at DESC');
    return r.map((e) => Transaction.fromMap(e)).toList();
  }

  Future<List<Transaction>> allTransactionsWithDeleted() async {
    final db = await database;
    final r = await db.query('transactions', orderBy: 'created_at DESC');
    return r.map((e) => Transaction.fromMap(e)).toList();
  }

  Future<List<Transaction>> getDeletedTransactions() async {
    final db = await database;
    final r = await db.query(
      'transactions',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return r.map((e) => Transaction.fromMap(e)).toList();
  }

  Future<double> customerBalance(int customerId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type='debt' THEN amount ELSE 0 END),0) AS d,
        COALESCE(SUM(CASE WHEN type='payment' THEN amount ELSE 0 END),0) AS p
      FROM transactions
      WHERE customer_id = ?
        AND (is_deleted = 0 OR is_deleted IS NULL)
    ''', [customerId]);
    final row = r.first;
    return (row['d'] as num).toDouble() - (row['p'] as num).toDouble();
  }

  Future<double> totalDebts() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN t.type='debt' THEN t.amount ELSE 0 END),0) AS d,
        COALESCE(SUM(CASE WHEN t.type='payment' THEN t.amount ELSE 0 END),0) AS p
      FROM transactions t
      LEFT JOIN customers c ON t.customer_id = c.id
      WHERE (t.is_deleted = 0 OR t.is_deleted IS NULL)
        AND (c.is_deleted = 0 OR c.is_deleted IS NULL)
        AND (c.is_permanently_deleted = 0 OR c.is_permanently_deleted IS NULL)
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
      where:
          'customer_id = ? AND amount = ? AND type = ? AND created_at > ? AND (is_deleted = 0 OR is_deleted IS NULL)',
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

  Future<int> countCustomerTransactions(int customerId) async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM transactions
      WHERE customer_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)
    ''', [customerId]);
    return (r.first['c'] as int?) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════
  // تنظيف المحذوفات
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, int>> cleanupDeleted({int days = 30}) async {
    int customersDeleted = 0;
    int transactionsDeleted = 0;

    try {
      final db = await database;
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();

      transactionsDeleted = await db.delete(
        'transactions',
        where: 'is_deleted = 1 AND deleted_at < ?',
        whereArgs: [cutoff],
      );

      customersDeleted = await db.delete(
        'customers',
        where: 'is_deleted = 1 AND deleted_at < ? '
            'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)',
        whereArgs: [cutoff],
      );

      if (customersDeleted > 0 || transactionsDeleted > 0) {
        _notifyChanged();
        debugPrint(
            '✅ [DB] Cleanup: $customersDeleted customers, $transactionsDeleted transactions');
      }
    } catch (e) {
      debugPrint('❌ cleanupDeleted: $e');
    }

    return {
      'customers': customersDeleted,
      'transactions': transactionsDeleted,
    };
  }

  Future<Map<String, int>> getDeletedCount() async {
    try {
      final db = await database;
      final c = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM customers '
          'WHERE is_deleted = 1 '
          'AND (is_permanently_deleted = 0 OR is_permanently_deleted IS NULL)');
      final t = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM transactions WHERE is_deleted = 1');
      return {
        'customers': (c.first['c'] as int?) ?? 0,
        'transactions': (t.first['c'] as int?) ?? 0,
      };
    } catch (e) {
      return {'customers': 0, 'transactions': 0};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إدارة الرموز
  // ═══════════════════════════════════════════════════════════

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
        'created_at': _now(),
      });
    } catch (_) {}
  }

  Future<int> getMaxCodeSequence(String prefix) async {
    try {
      final db = await database;
      final prefixWithDash = '$prefix-';
      final r = await db.rawQuery('''
        SELECT MAX(
          CAST(
            SUBSTR(code, ?) AS INTEGER
          )
        ) AS max_seq
        FROM used_codes
        WHERE code LIKE ?
      ''', [prefixWithDash.length + 1, '$prefixWithDash%']);

      if (r.isEmpty) return 0;
      final v = r.first['max_seq'];
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    } catch (e) {
      debugPrint('❌ getMaxCodeSequence error: $e');
      return 0;
    }
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
            'created_at': row['created_at'] ?? _now(),
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

  // ═══════════════════════════════════════════════════════════
  // المحاسبون
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // سجل الأحداث
  // ═══════════════════════════════════════════════════════════

  Future<int> insertLog(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('log_events', data);
  }

  Future<int> insertLogEventRaw(Map<String, dynamic> data) async {
    final db = await database;
    final sanitized = await _sanitizeForTable('log_events', data);
    return db.insert('log_events', sanitized);
  }

  Future<bool> logEventExists({
    required String action,
    required String createdAt,
    String? accountant,
  }) async {
    try {
      final db = await database;
      final where = StringBuffer('action = ? AND created_at = ?');
      final args = <dynamic>[action, createdAt];

      if (accountant != null && accountant.isNotEmpty) {
        where.write(' AND accountant = ?');
        args.add(accountant);
      }

      final r = await db.query(
        'log_events',
        where: where.toString(),
        whereArgs: args,
        limit: 1,
      );
      return r.isNotEmpty;
    } catch (e) {
      debugPrint('❌ logEventExists error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> allLogEventsRaw() async {
    final db = await database;
    return db.query('log_events', orderBy: 'created_at ASC');
  }

  Future<int> clearAllLogEvents() async {
    final db = await database;
    return db.delete('log_events');
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

  Future<int> getPendingAckCount() async {
    try {
      final db = await database;
      final r = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM log_events
        WHERE needs_acknowledgement = 1
          AND is_acknowledged = 0
      ''');
      return (r.first['c'] as int?) ?? 0;
    } catch (e) {
      debugPrint('❌ getPendingAckCount: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getAllPendingAck({
    int limit = 100,
  }) async {
    try {
      final db = await database;
      return db.query(
        'log_events',
        where: 'needs_acknowledgement = 1 AND is_acknowledged = 0',
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('❌ getAllPendingAck: $e');
      return [];
    }
  }

  Future<int> acknowledgeLogEvent(int id) async {
    try {
      final db = await database;
      final r = await db.update(
        'log_events',
        {'is_acknowledged': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (r > 0) _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ acknowledgeLogEvent: $e');
      return 0;
    }
  }

  Future<int> acknowledgeAllLogEvents() async {
    try {
      final db = await database;
      final r = await db.update(
        'log_events',
        {'is_acknowledged': 1},
        where: 'is_acknowledged = 0 AND needs_acknowledgement = 1',
      );
      if (r > 0) _notifyChanged();
      return r;
    } catch (e) {
      debugPrint('❌ acknowledgeAllLogEvents: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الإعدادات
  // ═══════════════════════════════════════════════════════════

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

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final r = await db.query('settings');
    final map = <String, String>{};
    for (final row in r) {
      final k = row['key'] as String?;
      final v = row['value'] as String?;
      if (k != null && v != null) map[k] = v;
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات للمزامنة
  // ═══════════════════════════════════════════════════════════

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
      WHERE (t.is_deleted = 0 OR t.is_deleted IS NULL)
        AND (c.is_deleted = 0 OR c.is_deleted IS NULL)
        AND (c.is_permanently_deleted = 0 OR c.is_permanently_deleted IS NULL)
      ORDER BY t.created_at DESC
    ''');
  }
}
