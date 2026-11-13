import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/models/voice_session.dart';
import 'package:debt_voice_app/services/parser_service.dart';

void main() {
  group('VoiceSession statement date range', () {
    test('merges and clones spoken statement dates', () {
      final from = DateTime(2026, 11, 1);
      final to = DateTime(2026, 11, 13);
      final session = VoiceSession(source: 'voice_screen');
      session.merge(ParsedPartial(
        intent: 'print_statement',
        customerName: 'أحمد',
        fromDate: from,
        toDate: to,
        rawText: 'طباعة كشف حساب أحمد من 01/11/2026 إلى 13/11/2026',
      ));

      final clone = session.clone();
      expect(clone.fromDate, from);
      expect(clone.toDate, to);
      expect(clone.toPartial().fromDate, from);
      expect(clone.toPartial().toDate, to);
    });
  });
}
