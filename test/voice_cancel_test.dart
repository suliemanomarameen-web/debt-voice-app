import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/services/voice_conversation_service.dart';
import 'package:debt_voice_app/models/voice_session.dart';
import 'package:debt_voice_app/services/parser_service.dart';

void main() {
  group('Voice cancellation commands', () {
    test('recognizes Arabic cancel words and phrases', () {
      expect(VoiceConversationService.isCancelCommand('إلغاء'), isTrue);
      expect(VoiceConversationService.isCancelCommand('إلغاء العملية'), isTrue);
      expect(VoiceConversationService.isCancelCommand('الغاء العملية'), isTrue);
    });

    test('recognizes English cancellation commands', () {
      expect(VoiceConversationService.isCancelCommand('cancel'), isTrue);
      expect(VoiceConversationService.isCancelCommand('cancel operation'), isTrue);
    });

    test('does not treat account limit removal as cancelling the session', () {
      expect(VoiceConversationService.isCancelCommand('إلغاء سقف حساب أحمد'), isFalse);
    });

    test('handles punctuation and extra spaces around cancel command', () {
      expect(VoiceConversationService.isCancelCommand('  إلغاء   العملية! '), isTrue);
      expect(VoiceConversationService.isCancelCommand('CANCEL.'), isTrue);
    });

    test('voice cancellation clears the active session', () {
      VoiceConversationService.startSession(source: 'voice_screen');
      expect(VoiceConversationService.hasActiveSession, isTrue);

      final result = VoiceConversationService.cancelFromVoice();

      expect(result.step, ConversationStep.failed);
      expect(result.ttsMessage, 'تم إلغاء العملية');
      expect(VoiceConversationService.hasActiveSession, isFalse);
    });
  });


    test('keeps conversations isolated by source', () {
      final screenSession = VoiceConversationService.startSession(source: 'voice_screen');
      final overlaySession = VoiceConversationService.startSession(source: 'overlay_main');

      expect(VoiceConversationService.sessionFor('voice_screen'), same(screenSession));
      expect(VoiceConversationService.sessionFor('overlay_main'), same(overlaySession));

      VoiceConversationService.cancelSession(source: 'overlay_main');

      expect(VoiceConversationService.sessionFor('overlay_main'), isNull);
      expect(VoiceConversationService.sessionFor('voice_screen'), same(screenSession));
      expect(VoiceConversationService.hasActiveSessionFor('voice_screen'), isTrue);
    });

    test('voice cancellation only cancels the matching source', () {
      final screenSession = VoiceConversationService.startSession(source: 'voice_screen');
      VoiceConversationService.startSession(source: 'overlay_main');

      final result = VoiceConversationService.cancelFromVoice(source: 'overlay_main');

      expect(result.ttsMessage, 'تم إلغاء العملية');
      expect(VoiceConversationService.sessionFor('overlay_main'), isNull);
      expect(VoiceConversationService.sessionFor('voice_screen'), same(screenSession));
    });

  group('Voice session retry state', () {
    test('counts empty attempts separately for the requested field', () {
      final session = VoiceSession()..expectingField = 'items';
      session.incrementAttempt('items');
      session.incrementAttempt('items');
      expect(session.attemptsFor('items'), 2);
      expect(session.attemptsFor('amount'), 0);
    });

    test('resets attempts after a valid answer is merged', () {
      final session = VoiceSession()..expectingField = 'amount';
      session.incrementAttempt('amount');
      session.merge(ParserService.parsePartial('خمسة آلاف', expecting: 'amount'));
      expect(session.amount, 5000);
      expect(session.attemptsFor('amount'), 0);
    });

    test('an incomplete transaction remains incomplete without an amount', () {
      final session = VoiceSession(intent: 'debt', customerName: 'محمد');
      expect(session.isComplete, isFalse);
      expect(session.hasAmount, isFalse);
    });

    test('a description is optional in the session model until requested', () {
      final session = VoiceSession(
        intent: 'debt',
        customerName: 'محمد',
        amount: 5000,
      );
      expect(session.isComplete, isTrue);
      expect(session.items, isNull);
    });
  });
}
