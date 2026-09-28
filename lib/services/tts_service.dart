import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static String? _arabicVoice;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // ابحث عن صوت عربي مثالي
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          final locale = (v['locale'] ?? '').toString().toLowerCase();
          if (locale.startsWith('ar')) {
            _arabicVoice = v['name']?.toString();
            // فضّل ar-SA أو ar-EG أو ar-AE (أوضح صوتاً)
            if (locale.contains('sa') ||
                locale.contains('eg') ||
                locale.contains('ae')) {
              break;
            }
          }
        }
      }

      // ضبط اللغة والنطق
      await _tts.setLanguage('ar-SA');
      if (_arabicVoice != null) {
        try {
          await _tts.setVoice({'name': _arabicVoice!, 'locale': 'ar-SA'});
        } catch (_) {}
      }

      // إعدادات النطق
      await _tts.setSpeechRate(0.42);   // أبطأ قليلاً ليتضح النطق
      await _tts.setPitch(1.05);        // نبرة أعلى قليلاً
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);

      _initialized = true;
    } catch (e) {
      print('TTS init error: $e');
    }
  }

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

  static Future<void> confirmTransaction({
    required String type,
    required double amount,
    required String customerName,
    required double newBalance,
    required String currency,
  }) async {
    final amountStr = amount.toStringAsFixed(0);
    final balanceStr = newBalance.toStringAsFixed(0);
    final cur = currency == 'YER' ? 'ريال' : currency;

    if (newBalance > 0) {
      await speak(
          'تم تسجيل $type بمبلغ $amountStr $cur على $customerName. '
          'الرصيد المتبقي هو $balanceStr $cur');
    } else if (newBalance < 0) {
      await speak(
          'تم تسجيل $type بمبلغ $amountStr $cur من $customerName. '
          'الباقي له هو ${(-newBalance).toStringAsFixed(0)} $cur');
    } else {
      await speak('تم تسجيل $type بمبلغ $amountStr $cur. '
          'حساب $customerName أصبح متوازناً');
    }
  }
}
