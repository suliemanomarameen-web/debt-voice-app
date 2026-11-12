import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/services/voice_conversation_service.dart';

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
  });
}
