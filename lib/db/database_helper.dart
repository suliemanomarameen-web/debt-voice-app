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
      version: 3,
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
        amount REAL NOT NULL,
        currency TEXT DEFAULT 'YER',
        type TEXT NOT NULL,
        items TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
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
  }

  /// إشعار بأن البيانات تغيرت (للمزامنة التلقائية)
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

  /// إدراج زبون من المزامنة (بدون إشعار - لتجنب infinite loop)
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

  // ============ المعاملات ============
  Future<int> insertTransaction(Transaction t) async {
    final db = await database;
    final id = await db.insert('transactions', t.toMap());
    _notifyChanged();
    return id;
  }

  /// إدراج معاملة من المزامنة (بدون إشعار)
  Future<int> insertTransactionRaw(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('transactions', data);
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

  /// البحث عن معاملة موجودة بنفس البيانات (لتفادي التكرار أثناء المزامنة)
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

  /// البحث عن زبون بنفس الاسم ونفس تاريخ الإنشاء
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

  /// إفراغ كل البيانات (للاستعادة الكاملة)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('customers');
    _notifyChanged();
  }

  /// جلب كل المعاملات (للتصدير)
  Future<List<Map<String, dynamic>>> allTransactionsRaw() async {
    final db = await database;
    return db.query('transactions');
  }

  /// جلب كل الزبائن (للتصدير)
  Future<List<Map<String, dynamic>>> allCustomersRaw() async {
    final db = await database;
    return db.query('customers');
  }
}
