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

    test('parses item after an amount written in Arabic words', () {
      final result = ParserService.parsePartial('سجل على أحمد خمسة آلاف بضاعة');
      expect(result.intent, 'debt');
      expect(result.customerName, 'أحمد');
      expect(result.amount, 5000);
      expect(result.items, 'بضاعة');
    });

    test('parses item after a multi-part Arabic word amount', () {
      final result = ParserService.parsePartial(
        'سجل على أحمد خمسة آلاف ومئتين قطع غيار',
      );
      expect(result.intent, 'debt');
      expect(result.customerName, 'أحمد');
      expect(result.amount, 5200);
      expect(result.items, 'قطع غيار');
    });

    test('keeps item when amount and item are supplied in a follow-up answer', () {
      final result = ParserService.parsePartial(
        'خمسة آلاف بضاعة',
        expecting: 'amount',
      );
      expect(result.amount, 5000);
      expect(result.items, 'بضاعة');
    });

    test('recognizes add-account intent when the user has not said a name yet', () {
      final result = ParserService.parsePartial('أضف حساب');
      expect(result.intent, 'add_account');
      expect(result.customerName, isNull);
    });

    test('extracts the name from a contextual add-account answer', () {
      final result = ParserService.parsePartial(
        'باسم يونس',
        expecting: 'customerName',
      );
      expect(result.customerName, 'يونس');
    });

    test('parses a complete add-account command and extracts only the name', () {
      final result = ParserService.parsePartial('أضف حساب باسم أحمد');
      expect(result.intent, 'add_account');
      expect(result.customerName, 'أحمد');
    });

    test('parses complete payment command', () {
      final result = ParserService.parsePartial('دفع من أحمد ٢٥٠٠ ريال');
      expect(result.intent, 'payment');
      expect(result.customerName, 'أحمد');
      expect(result.amount, 2500);
    });

    test('parses complete return command', () {
      final result = ParserService.parsePartial('مرتجع أحمد ٣٠٠ بضاعة');
      expect(result.intent, 'return');
      expect(result.customerName, 'أحمد');
      expect(result.amount, 300);
    });

    test('parses account statement command', () {
      final result = ParserService.parsePartial('كشف حساب أحمد');
      expect(result.intent, 'statement');
      expect(result.customerName, 'أحمد');
    });

    test('parses print statement command', () {
      final result = ParserService.parsePartial('طباعة كشف حساب أحمد');
      expect(result.intent, 'print_statement');
      expect(result.customerName, 'أحمد');
    });

    test('parses numeric date range in a print statement command', () {
      final result = ParserService.parsePartial(
        'طباعة كشف حساب أحمد من تاريخ 01/11/2026 إلى 13/11/2026',
      );
      expect(result.intent, 'print_statement');
      expect(result.customerName, 'أحمد');
      expect(result.fromDate, DateTime(2026, 11, 1));
      expect(result.toDate, DateTime(2026, 11, 13));
      expect(result.amount, isNull, reason: 'Date numbers must not be treated as transaction amounts');
    });

    test('parses ISO date range with Arabic digits', () {
      final result = ParserService.parsePartial(
        'اطبع كشف حساب محمد من ٢٠٢٦-١١-٠١ إلى ٢٠٢٦-١١-١٣',
      );
      expect(result.fromDate, DateTime(2026, 11, 1));
      expect(result.toDate, DateTime(2026, 11, 13));
    });

    test('parses send statement command', () {
      final result = ParserService.parsePartial('أرسل كشف حساب أحمد');
      expect(result.intent, 'send_statement');
      expect(result.customerName, 'أحمد');
    });

    test('parses block and unblock account commands', () {
      final block = ParserService.parsePartial('أوقف الحساب أحمد');
      final unblock = ParserService.parsePartial('فعل الحساب أحمد');
      expect(block.intent, 'block_account');
      expect(block.customerName, 'أحمد');
      expect(unblock.intent, 'unblock_account');
      expect(unblock.customerName, 'أحمد');
    });

    test('parses set and remove account limit commands', () {
      final setLimit = ParserService.parsePartial('حدد سقف حساب أحمد ١٠٠٠٠');
      final removeLimit = ParserService.parsePartial('إلغاء سقف حساب أحمد');
      expect(setLimit.intent, 'set_limit');
      expect(setLimit.customerName, 'أحمد');
      expect(setLimit.amount, 10000);
      expect(removeLimit.intent, 'remove_limit');
      expect(removeLimit.customerName, 'أحمد');
    });

    test('parses statistics command', () {
      final result = ParserService.parsePartial('اعرض الإحصائيات');
      expect(result.intent, 'statistics');
    });

    test('parses last transaction command', () {
      final result = ParserService.parsePartial('آخر عملية أحمد');
      expect(result.intent, 'last_transaction');
      expect(result.customerName, 'أحمد');
    });

    test('parses search command and query', () {
      final result = ParserService.parsePartial('ابحث عن أحمد');
      expect(result.intent, 'search');
      expect(result.customerName, 'أحمد');
    });

    test('parses delete and edit account commands', () {
      final delete = ParserService.parsePartial('احذف حساب أحمد');
      final edit = ParserService.parsePartial('عدل حساب أحمد');
      expect(delete.intent, 'delete_customer');
      expect(delete.customerName, 'أحمد');
      expect(edit.intent, 'edit_customer');
      expect(edit.customerName, 'أحمد');
    });

    test('parses rename account and new name from one sentence', () {
      final result = ParserService.parsePartial('غير اسم الحساب أحمد إلى محمد');
      expect(result.intent, 'rename_customer');
      expect(result.customerName, 'أحمد');
      expect(result.items, 'محمد');
    });

    test('parses generic process command for follow-up type selection', () {
      final result = ParserService.parsePartial('ابدأ عملية جديدة');
      expect(result.intent, 'process');
    });
  });
}
