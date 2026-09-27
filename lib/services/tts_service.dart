import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('ar-SA');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _initialized = true;
    } catch (e) {
      print('TTS init error: $e');
    }
  }

  /// إلقاء نص بالصوت
  static Future<void> speak(String text) async {
    if (text.isEmpty) return;
    if (!_initialized) await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      print('TTS speak error: $e');
    }
  }

  static Future<void> stop() async => _tts.stop();

  /// رسائل جاهزة
  static Future<void> confirmTransaction({
    required String type,       // 'دين' | 'سداد' | 'مرتجع'
    required double amount,
    required String customerName,
    required double newBalance,
    required String currency,
  }) async {
    final amountStr = amount.toStringAsFixed(0);
    final balanceStr = newBalance.toStringAsFixed(0);
    final cur = currency == 'YER' ? 'ريال' : currency;

    if (newBalance > 0) {
      await speak('تم تسجيل $type $amountStr $cur على $customerName. '
          'الرصيد المتبقي: $balanceStr $cur');
    } else if (newBalance < 0) {
      await speak('تم تسجيل $type $amountStr $cur من $customerName. '
          'الباقي له: ${(-newBalance).toStringAsFixed(0)} $cur');
    } else {
      await speak('تم تسجيل $type $amountStr $cur. '
          'الحساب متوازن مع $customerName');
    }
  }
}
