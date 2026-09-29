import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static String? _arabicVoice;

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
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      print('TTS speak error: $e');
    }
  }

  static Future<void> stop() async => _tts.stop();

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
  // الجمل الجاهزة المشكّلة
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
      await speak('تَمَّ تَسْجِيلُ $typeAr بِمَبْلَغِ $amountStr $cur. '
          'حِسَابُ $customerName أَصْبَحَ مُتَوَازِنًا');
      return;
    }

    if (newBalance > 0) {
      final balStr = _numToWords(newBalance);
      await speak('تَمَّ تَسْجِيلُ $typeAr بِمَبْلَغِ $amountStr $cur '
          'عَلَى $customerName. '
          'الرَّصِيدُ المُتَبَقِّي هُوَ $balStr $cur');
    } else {
      final balStr = _numToWords(-newBalance);
      await speak('تَمَّ تَسْجِيلُ $typeAr بِمَبْلَغِ $amountStr $cur '
          'مِنْ $customerName. '
          'البَاقِي لَهُ هُوَ $balStr $cur');
    }
  }

  /// نطق رصيد الحساب — يُستخدم في الاستعلام
  static Future<void> speakBalance({
    required String customerName,
    required double balance,
    required String currency,
  }) async {
    final cur = _currencyName(currency);
    if (balance > 0) {
      final balStr = _numToWords(balance);
      await speak('$customerName عَلَيْهِ $balStr $cur');
    } else if (balance < 0) {
      final balStr = _numToWords(-balance);
      await speak('$customerName بَاقِي لَهُ $balStr $cur');
    } else {
      await speak('حِسَابُ $customerName مُتَوَازِن، '
          'لَا دُيُونَ وَلَا مُسْتَحَقَّات');
    }
  }

  static Future<void> speakAccountCreated(String name) async {
    await speak('تَمَّ إِنْشَاءُ حِسَابٍ بِاسْمِ $name');
  }

  static Future<void> speakNoAccount(String name) async {
    await speak('لَا يُوجَدُ حِسَابٌ بِاسْمِ $name');
  }

  static Future<void> speakMultipleAccounts() async {
    await speak('يُوجَدُ أَكْثَرُ مِنْ حِسَاب. حَدِّدِ الاِسْمَ بِدِقَّة');
  }

  static Future<void> speakDidNotHear() async {
    await speak('لَمْ أَسْمَعْ شَيْئًا. حَدِّثْ بِوُضُوح');
  }

  static Future<void> speakDidNotUnderstand() async {
    await speak('لَمْ أَفْهَمِ الجُمْلَة');
  }

  static Future<void> speakExistsBefore(String name) async {
    await speak('حِسَابُ $name مَوْجُودٌ مُسْبَقًا');
  }

  /// نطق كشف حساب كامل
  static Future<void> speakStatement({
    required String customerName,
    required double balance,
    required String currency,
    required List<String> items, // آخر 3 عمليات
  }) async {
    final cur = _currencyName(currency);

    String intro;
    if (balance > 0) {
      intro = '$customerName عَلَيْهِ ${_numToWords(balance)} $cur';
    } else if (balance < 0) {
      intro = '$customerName بَاقِي لَهُ ${_numToWords(-balance)} $cur';
    } else {
      intro = 'حِسَابُ $customerName مُتَوَازِن';
    }

    if (items.isEmpty) {
      await speak(intro);
      return;
    }

    final joined = items.join('، ثُمَّ ');
    await speak('$intro. آخِرُ العَمَلِيَّات: $joined');
  }
}
