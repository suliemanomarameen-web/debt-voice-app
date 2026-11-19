import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debt_voice_app/db/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v16 migration preserves rows and upload counts include only this device active rows',
      () async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;

    final tempDirectory =
        await Directory.systemTemp.createTemp('debt_voice_db_test_');
    await sqflite.databaseFactory.setDatabasesPath(tempDirectory.path);

    final databasePath =
        p.join(await sqflite.getDatabasesPath(), 'debt_book.db');

    // Build a minimal v16 database: the two origin columns do not exist yet.
    final oldDatabase = await sqflite.openDatabase(
      databasePath,
      version: 16,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cloud_id TEXT,
            name TEXT NOT NULL,
            is_deleted INTEGER DEFAULT 0,
            is_permanently_deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cloud_id TEXT,
            customer_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            is_deleted INTEGER DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    await oldDatabase.insert('customers', {
      'name': 'حساب قديم',
      'created_at': '2025-01-01T10:00:00.000',
    });
    await oldDatabase.insert('transactions', {
      'customer_id': 1,
      'amount': 100,
      'type': 'debt',
      'created_at': '2025-01-01T10:00:00.000',
    });
    await oldDatabase.close();

    // Opening through the real singleton must execute its v16 -> v17 migration.
    final db = await DatabaseHelper.instance.database;

    final customerColumns = await db.rawQuery('PRAGMA table_info(customers)');
    final transactionColumns =
        await db.rawQuery('PRAGMA table_info(transactions)');
    expect(
      customerColumns.any((row) => row['name'] == 'created_from_device'),
      isTrue,
    );
    expect(
      transactionColumns.any((row) => row['name'] == 'created_from_device'),
      isTrue,
    );

    // Existing v16 data must remain intact and un-attributed.
    final oldCustomers = await db.query('customers', where: 'id = ?', whereArgs: [1]);
    final oldTransactions =
        await db.query('transactions', where: 'id = ?', whereArgs: [1]);
    expect(oldCustomers, hasLength(1));
    expect(oldTransactions, hasLength(1));
    expect(oldCustomers.single['created_from_device'], isNull);
    expect(oldTransactions.single['created_from_device'], isNull);

    const after = '2026-01-10T00:00:00.000';

    Future<void> addCustomer({
      required String name,
      required String device,
      String createdAt = '2026-01-11T10:00:00.000',
      int deleted = 0,
      int permanentlyDeleted = 0,
    }) async {
      await db.insert('customers', {
        'name': name,
        'created_from_device': device,
        'created_at': createdAt,
        'is_deleted': deleted,
        'is_permanently_deleted': permanentlyDeleted,
      });
    }

    Future<void> addTransaction({
      required String device,
      String createdAt = '2026-01-11T10:00:00.000',
      int deleted = 0,
    }) async {
      await db.insert('transactions', {
        'customer_id': 1,
        'amount': 250,
        'type': 'debt',
        'created_from_device': device,
        'created_at': createdAt,
        'is_deleted': deleted,
      });
    }

    await addCustomer(name: 'حساب الجهاز الحالي', device: 'device-a');
    await addCustomer(name: 'حساب جهاز آخر', device: 'device-b');
    await addCustomer(
      name: 'حساب محذوف مؤقتاً',
      device: 'device-a',
      deleted: 1,
    );
    await addCustomer(
      name: 'حساب محذوف نهائياً',
      device: 'device-a',
      permanentlyDeleted: 1,
    );
    await addCustomer(
      name: 'حساب قديم للجهاز',
      device: 'device-a',
      createdAt: '2026-01-09T10:00:00.000',
    );

    await addTransaction(device: 'device-a');
    await addTransaction(device: 'device-b');
    await addTransaction(device: 'device-a', deleted: 1);
    await addTransaction(
      device: 'device-a',
      createdAt: '2026-01-09T10:00:00.000',
    );

    final counts = await DatabaseHelper.instance.getLocalCreatedCounts(
      deviceId: 'device-a',
      after: DateTime.parse(after),
    );

    expect(counts['customers'], 1);
    expect(counts['transactions'], 1);
  });
}
