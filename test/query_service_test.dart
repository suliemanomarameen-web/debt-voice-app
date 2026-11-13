import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/services/query_service.dart';

void main() {
  group('QueryService command routing', () {
    test('does not classify add-account commands as account queries', () {
      expect(QueryService.isQuery('أضف حساب'), isFalse);
      expect(QueryService.isQuery('أضف حساب باسم يونس'), isFalse);
      expect(QueryService.isQuery('أنشئ حساب باسم أحمد'), isFalse);
    });

    test('keeps account statement requests as queries', () {
      expect(QueryService.isQuery('كشف حساب أحمد'), isTrue);
      expect(QueryService.isQuery('رصيد محمد'), isTrue);
    });

    test('does not classify print and management commands as queries', () {
      expect(QueryService.isQuery('طباعة كشف حساب أحمد'), isFalse);
      expect(QueryService.isQuery('إلغاء سقف حساب أحمد'), isFalse);
      expect(QueryService.isQuery('أوقف الحساب أحمد'), isFalse);
      expect(QueryService.isQuery('فعل الحساب أحمد'), isFalse);
    });

    test('does not classify complete transaction commands as queries', () {
      expect(QueryService.isQuery('سجل على أحمد ٥٠٠٠ بضاعة'), isFalse);
      expect(QueryService.isQuery('دفع من أحمد ٢٥٠٠ ريال'), isFalse);
      expect(QueryService.isQuery('مرتجع أحمد ٣٠٠ بضاعة'), isFalse);
    });
  });
}
