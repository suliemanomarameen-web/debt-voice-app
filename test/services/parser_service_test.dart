import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debt_voice_app/services/keywords_service.dart';
import 'package:debt_voice_app/services/parser_service.dart';
import 'package:debt_voice_app/services/query_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KeywordsService.reload();
  });

  test('create-account intent takes priority and extracts the name', () {
    final parsed = ParserService.parsePartial('أضف حساب باسم وليد');

    expect(parsed.intent, 'add_account');
    expect(parsed.customerName, 'وليد');
  });

  test('bare create-account command is recognized without a name', () {
    final parsed = ParserService.parsePartial('أضف حساب');

    expect(parsed.intent, 'add_account');
    expect(parsed.customerName, isNull);
  });

  test('default create-account commands remain available after customization', () async {
    await KeywordsService.set(
      KeywordsService.catAddAccount,
      ['أضف حساب باسم', 'باسم'],
    );

    final parsed = ParserService.parsePartial('أضف حساب باسم يونس');

    expect(parsed.intent, 'add_account');
    expect(parsed.customerName, 'يونس');
  });

  test('built-in add-account command still works when custom words contain only باسم', () async {
    await KeywordsService.set(
      KeywordsService.catAddAccount,
      ['باسم'],
    );

    final parsed = ParserService.parsePartial('أضف حساب');

    expect(parsed.intent, 'add_account');
    expect(parsed.customerName, isNull);
  });

  test('the connector word باسم alone does not turn a statement into account creation', () async {
    await KeywordsService.set(
      KeywordsService.catAddAccount,
      ['باسم'],
    );

    final parsed = ParserService.parsePartial('كشف حساب باسم وليد');

    expect(parsed.intent, 'statement');
  });

  test('statement phrase means account statement, not send or print', () {
    expect(ParserService.parsePartial('كشف حساب خالد').intent, 'statement');
    expect(QueryService.isQuery('كشف حساب خالد'), isTrue);
  });

  test('explicit send and print verbs outrank the general statement phrase', () {
    expect(ParserService.parsePartial('أرسل كشف حساب خالد').intent, 'send_statement');
    expect(ParserService.parsePartial('اطبع كشف حساب خالد').intent, 'print_statement');
    expect(QueryService.isQuery('أرسل كشف حساب خالد'), isFalse);
    expect(QueryService.isQuery('اطبع كشف حساب خالد'), isFalse);
  });

  test('query-all phrases are routed to statistics', () {
    expect(ParserService.parsePartial('إجمالي الديون').intent, 'statistics');
    expect(ParserService.parsePartial('كل الحسابات').intent, 'statistics');
  });

  test('account management keywords extract the customer after structural words', () {
    final block = ParserService.parsePartial('أوقف حساب خالد');
    expect(block.intent, 'block_account');
    expect(block.customerName, 'خالد');

    final unblock = ParserService.parsePartial('فعل الحساب خالد');
    expect(unblock.intent, 'unblock_account');
    expect(unblock.customerName, 'خالد');

    final limit = ParserService.parsePartial('حدد سقف حساب خالد 5000');
    expect(limit.intent, 'set_limit');
    expect(limit.customerName, 'خالد');
    expect(limit.amount, 5000);
  });

  test('all configured voice-intent categories resolve to their own intent', () {
    final cases = <String, String>{
      'سجل على خالد 500': 'debt',
      'دفع من خالد 500': 'payment',
      'مرتجع خالد 500': 'return',
      'أضف حساب باسم خالد': 'add_account',
      'كم عليه خالد': 'statement',
      'كشف حساب خالد': 'statement',
      'إجمالي الديون': 'statistics',
      'الإحصائيات': 'statistics',
      'إيقاف الحساب خالد': 'block_account',
      'تفعيل الحساب خالد': 'unblock_account',
      'سقف الحساب خالد 5000': 'set_limit',
      'أوقف حساب خالد': 'block_account',
      'فعل الحساب خالد': 'unblock_account',
      'حدد سقف حساب خالد 5000': 'set_limit',
      'عملية جديدة': 'process',
      'اطبع كشف حساب خالد': 'print_statement',
      'أرسل كشف حساب خالد': 'send_statement',
      'آخر عملية خالد': 'last_transaction',
      'ابحث عن خالد': 'search',
      'احذف حساب خالد': 'delete_customer',
      'عدل حساب خالد': 'edit_customer',
    };

    for (final entry in cases.entries) {
      expect(
        ParserService.parsePartial(entry.key).intent,
        entry.value,
        reason: 'Failed intent for: ${entry.key}',
      );
    }
  });

  test('custom keywords are recognized by the same intent detector', () async {
    await KeywordsService.set(
      KeywordsService.catBlockAccount,
      ['جمّد الحساب'],
    );
    final parsed = ParserService.parsePartial('جمّد الحساب خالد');
    expect(parsed.intent, 'block_account');
    expect(parsed.customerName, 'خالد');
  });

  test('a statement keyword inside a transaction description does not override recording', () {
    final parsed = ParserService.parsePartial('سجل على خالد 500 رصيد');
    expect(parsed.intent, 'debt');
    expect(parsed.customerName, 'خالد');
    expect(parsed.amount, 500);
    expect(QueryService.isQuery('سجل على خالد 500 رصيد'), isFalse);
  });

}
