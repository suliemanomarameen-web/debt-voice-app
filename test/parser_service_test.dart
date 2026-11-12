import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/services/parser_service.dart';

void main() {
  group('ParserService Arabic word amounts', () {
    test('parses خمسة آلاف as 5000', () {
      final result = ParserService.parsePartial('خمسة آلاف', expecting: 'amount');
      expect(result.amount, 5000);
    });

    test('parses خمسة آلاف ومئتين as 5200', () {
      final result = ParserService.parsePartial('خمسة آلاف ومئتين', expecting: 'amount');
      expect(result.amount, 5200);
    });

    test('does not append spoken amount to customer name', () {
      final result = ParserService.parsePartial('محمد خمسة آلاف', expecting: 'customerName');
      expect(result.customerName, 'محمد');
      expect(result.amount, 5000);
    });

    test('removes باسم from customer name', () {
      final result = ParserService.parsePartial('باسم يونس', expecting: 'customerName');
      expect(result.customerName, 'يونس');
    });

    test('keeps digit amount parsing unchanged', () {
      final result = ParserService.parsePartial('5000', expecting: 'amount');
      expect(result.amount, 5000);
    });

    test('parses a complete debt sentence with amount and item', () {
      final result = ParserService.parsePartial('سجل على أحمد ٥٠٠٠ بضاعة');
      expect(result.intent, 'debt');
      expect(result.customerName, 'أحمد');
      expect(result.amount, 5000);
      expect(result.items, 'بضاعة');
    });

    test('parses a complete add-account command and extracts only the name', () {
      final result = ParserService.parsePartial('أضف حساب باسم أحمد');
      expect(result.intent, 'add_account');
      expect(result.customerName, 'أحمد');
    });
  });
}
