import 'package:flutter_test/flutter_test.dart';

import 'package:debt_voice_app/services/voice_conversation_service.dart';

void main() {
  setUp(() {
    VoiceConversationService.cancelSession();
  });

  tearDown(() {
    VoiceConversationService.cancelSession();
  });

  test('cancel command overrides a pending items answer and clears the session', () async {
    final session = VoiceConversationService.startSession();
    session.intent = 'debt';
    session.customerName = 'محمد';
    session.amount = 5000;
    session.expectingField = 'items';
    session.items = null;

    final result = await VoiceConversationService.processText('إلغاء');

    expect(result.step, ConversationStep.failed);
    expect(result.errorMessage, 'تم إلغاء العملية');
    expect(result.ttsMessage, 'تم إلغاء العملية');
    expect(VoiceConversationService.hasActiveSession, isFalse);
  });

  test('recognizes common standalone cancellation phrases', () {
    expect(VoiceConversationService.isCancelCommand('إلغاء'), isTrue);
    expect(VoiceConversationService.isCancelCommand('الغاء العملية'), isTrue);
    expect(VoiceConversationService.isCancelCommand('cancel'), isTrue);
    expect(VoiceConversationService.isCancelCommand('إلغاء العملية.'), isTrue);
  });

  test('does not classify unrelated phrases as cancellation', () {
    expect(VoiceConversationService.isCancelCommand('سجل على محمد 5000'), isFalse);
    expect(VoiceConversationService.isCancelCommand('بيان العملية شراء بضاعة'), isFalse);
  });
}
