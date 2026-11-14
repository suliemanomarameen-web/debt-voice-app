import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debt_voice_app/services/keywords_service.dart';
import 'package:debt_voice_app/services/parser_service.dart';

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
}
