import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/models/customer.dart';
import 'package:debt_voice_app/models/transaction.dart' as debt;

void main() {
  group('Customer created_from_device', () {
    test('is preserved when converting to and from a database map', () {
      final customer = Customer(
        name: 'عميل الاختبار',
        createdAt: '2026-01-01T10:00:00.000',
        createdFromDevice: 'device-a',
      );

      final restored = Customer.fromMap(customer.toMap());

      expect(restored.createdFromDevice, 'device-a');
    });

    test('legacy rows without the device field remain readable', () {
      final legacyRow = Customer(
        name: 'عميل قديم',
        createdAt: '2025-01-01T10:00:00.000',
      ).toMap()
        ..remove('created_from_device');

      final restored = Customer.fromMap(legacyRow);

      expect(restored.createdFromDevice, isNull);
    });

    test('copyWith preserves the device origin unless replaced', () {
      final customer = Customer(
        name: 'عميل الاختبار',
        createdAt: '2026-01-01T10:00:00.000',
        createdFromDevice: 'device-a',
      );

      expect(customer.copyWith(name: 'اسم جديد').createdFromDevice, 'device-a');
      expect(
        customer.copyWith(createdFromDevice: 'device-b').createdFromDevice,
        'device-b',
      );
    });
  });

  group('Transaction created_from_device', () {
    test('is preserved when converting to and from a database map', () {
      final transaction = debt.Transaction(
        customerId: 1,
        amount: 1250,
        type: 'debt',
        createdAt: '2026-01-01T10:00:00.000',
        createdFromDevice: 'device-a',
      );

      final restored = debt.Transaction.fromMap(transaction.toMap());

      expect(restored.createdFromDevice, 'device-a');
    });

    test('legacy rows without the device field remain readable', () {
      final legacyRow = debt.Transaction(
        customerId: 1,
        amount: 500,
        type: 'payment',
        createdAt: '2025-01-01T10:00:00.000',
      ).toMap()
        ..remove('created_from_device');

      final restored = debt.Transaction.fromMap(legacyRow);

      expect(restored.createdFromDevice, isNull);
    });

    test('copyWith preserves the device origin unless replaced', () {
      final transaction = debt.Transaction(
        customerId: 1,
        amount: 500,
        type: 'debt',
        createdAt: '2026-01-01T10:00:00.000',
        createdFromDevice: 'device-a',
      );

      expect(
        transaction.copyWith(amount: 700).createdFromDevice,
        'device-a',
      );
      expect(
        transaction.copyWith(createdFromDevice: 'device-b').createdFromDevice,
        'device-b',
      );
    });
  });
}
