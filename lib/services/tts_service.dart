import 'package:flutter_tts/flutter_tts.dart';
import 'voice_prompts_service.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _speaking = false;
  static String? _arabicVoice;

  /// True while the application is speaking; STT must not capture this audio.
  static bool get isSpeaking => _speaking;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          final locale = (v['locale'] ?? '').toString().toLowerCase();
          if (locale.startsWith('ar')) {
            _arabicVoice = v['name']?.toString();
            if (locale.contains('sa') ||
                locale.contains('eg') ||
                locale.contains('ae')) {
              break;
            }
          }
        }
      }

      await _tts.setLanguage('ar-SA');
      if (_arabicVoice != null) {
        try {
          await _tts.setVoice({'name': _arabicVoice!, 'locale': 'ar-SA'});
        } catch (_) {}
      }

      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
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
    _speaking = true;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      print('TTS speak error: $e');
    } finally {
      _speaking = false;
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } finally {
      _speaking = false;
    }
  }

  // ============================================================
  // تحويل الأرقام إلى كلمات عربية مشكّلة
  // ============================================================
  static String _numToWords(double num) {
    final n = num.round();
    if (n == 0) return 'صِفْر';
    if (n < 0) return 'سَالِب ${_numToWords((-n).toDouble())}';

    const ones = [
      '', 'وَاحِد', 'اِثْنَان', 'ثَلَاثَة', 'أَرْبَعَة', 'خَمْسَة',
      'سِتَّة', 'سَبْعَة', 'ثَمَانِيَة', 'تِسْعَة', 'عَشَرَة',
      'أَحَدَ عَشَر', 'اِثْنَا عَشَر', 'ثَلَاثَةَ عَشَر', 'أَرْبَعَةَ عَشَر',
      'خَمْسَةَ عَشَر', 'سِتَّةَ عَشَر', 'سَبْعَةَ عَشَر', 'ثَمَانِيَةَ عَشَر',
      'تِسْعَةَ عَشَر',
    ];
    const tens = [
      '', '', 'عِشْرُون', 'ثَلَاثُون', 'أَرْبَعُون', 'خَمْسُون',
      'سِتُّون', 'سَبْعُون', 'ثَمَانُون', 'تِسْعُون',
    ];

    if (n < 20) return ones[n];
    if (n < 100) {
      final t = n ~/ 10;
      final o = n % 10;
      if (o == 0) return tens[t];
      return '${ones[o]} وَ${tens[t]}';
    }
    if (n < 1000) {
      final h = n ~/ 100;
      final rest = n % 100;
      final hStr = h == 1
          ? 'مِائَة'
          : h == 2
              ? 'مِائَتَاْن'
              : '${ones[h]} مِائَة';
      if (rest == 0) return hStr;
      return '$hStr و${_numToWords(rest.toDouble())}';
    }
    if (n < 1000000) {
      final k = n ~/ 1000;
      final rest = n % 1000;
      final kStr = k == 1
          ? 'أَلْف'
          : k == 2
              ? 'أَلْفَان'
              : '${_numToWords(k.toDouble())} آلَاف';
      if (rest == 0) return kStr;
      return '$kStr و${_numToWords(rest.toDouble())}';
    }
    return n.toString();
  }

  static String _currencyName(String cur) {
    switch (cur.toUpperCase()) {
      case 'YER':
        return 'رِيَال';
      case 'USD':
        return 'دُولَار';
      case 'SAR':
        return 'رِيَال سُعُودِي';
      case 'AED':
        return 'دِرْهَم';
      default:
        return cur;
    }
  }

  /// كلمة نوع المعاملة مشكّلة
  static String _typeAr(String type) {
    switch (type) {
      case 'دين':
      case 'debt':
        return 'دَيْن';
      case 'سداد':
      case 'payment':
        return 'سَدَاد';
      case 'مرتجع':
      case 'return':
        return 'مُرْتَجَع';
      default:
        return type;
    }
  }

  // ============================================================
  // الجمل الجاهزة المشكّلة (تقرأ من VoicePromptsService)
  // ============================================================

  static Future<void> confirmTransaction({
    required String type,
    required double amount,
    required String customerName,
    required double newBalance,
    required String currency,
  }) async {
    final amountStr = _numToWords(amount);
    final cur = _currencyName(currency);
    final typeAr = _typeAr(type);

    if (newBalance == 0) {
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tConfirmZero,
        vars: {
          'type': typeAr,
          'amount': amountStr,
          'currency': cur,
          'customer': customerName,
        },
      );
      await speak(msg);
      return;
    }

    if (newBalance > 0) {
      final balStr = _numToWords(newBalance);
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tConfirmDebt,
        vars: {
          'type': typeAr,
          'amount': amountStr,
          'currency': cur,
          'customer': customerName,
          'balance': balStr,
        },
      );
      await speak(msg);
    } else {
      final balStr = _numToWords(-newBalance);
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tConfirmPayment,
        vars: {
          'type': typeAr,
          'amount': amountStr,
          'currency': cur,
          'customer': customerName,
          'balance': balStr,
        },
      );
      await speak(msg);
    }
  }

  static Future<void> speakBalance({
    required String customerName,
    required double balance,
    required String currency,
  }) async {
    final cur = _currencyName(currency);

    if (balance > 0) {
      final balStr = _numToWords(balance);
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceDebt,
        vars: {
          'customer': customerName,
          'balance': balStr,
          'currency': cur,
        },
      );
      await speak(msg);
    } else if (balance < 0) {
      final balStr = _numToWords(-balance);
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceCredit,
        vars: {
          'customer': customerName,
          'balance': balStr,
          'currency': cur,
        },
      );
      await speak(msg);
    } else {
      final msg = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceZero,
        vars: {'customer': customerName},
      );
      await speak(msg);
    }
  }

  static Future<void> speakAccountCreated(String name) async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tAccountCreated,
      vars: {'name': name},
    );
    await speak(msg);
  }

  static Future<void> speakNoAccount(String name) async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tNoAccount,
      vars: {'name': name},
    );
    await speak(msg);
  }

  static Future<void> speakMultipleAccounts() async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tMultipleAccounts,
    );
    await speak(msg);
  }

  static Future<void> speakDidNotHear() async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tDidNotHear,
    );
    await speak(msg);
  }

  static Future<void> speakDidNotUnderstand() async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tDidNotUnderstand,
    );
    await speak(msg);
  }

  static Future<void> speakExistsBefore(String name) async {
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tExistsBefore,
      vars: {'name': name},
    );
    await speak(msg);
  }

  static Future<void> speakStatement({
    required String customerName,
    required double balance,
    required String currency,
    required List<String> items,
  }) async {
    final cur = _currencyName(currency);

    String header;
    if (balance > 0) {
      header = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceDebt,
        vars: {
          'customer': customerName,
          'balance': _numToWords(balance),
          'currency': cur,
        },
      );
    } else if (balance < 0) {
      header = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceCredit,
        vars: {
          'customer': customerName,
          'balance': _numToWords(-balance),
          'currency': cur,
        },
      );
    } else {
      header = VoicePromptsService.getResponse(
        VoicePromptsService.tBalanceZero,
        vars: {'customer': customerName},
      );
    }

    if (items.isEmpty) {
      await speak(header);
      return;
    }

    final joined = items.join('، ثُمَّ ');
    final msg = VoicePromptsService.getResponse(
      VoicePromptsService.tStatementWithItems,
      vars: {'header': header, 'items': joined},
    );
    await speak(msg);
  }
}

// TtsService v1: خدمة النطق الصوتي
// - تحويل الأرقام إلى كلمات عربية مشكّلة
// - ترجمة العملات والأنواع
// - 8 دوال جاهزة (confirmTransaction, speakBalance, ...)
// TtsService v2: ربط بجدول الحوار الصوتي (VoicePromptsService)
// - كل النصوص تُقرأ من الجدول (قابلة للتعديل من الإعدادات)
// - دعم متغيرات {type}, {amount}, {currency}, {customer}, {balance}, {items}, {header}, {name}
