import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة نصوص الحوار الصوتي والردود الصوتية
///
/// تحتوي على جدولين:
/// 1. **الأسئلة** (Prompts) — ما يكتبه/يقوله التطبيق ليسأل.
/// 2. **الردود الصوتية** (TTS Responses) — ما يُقرأ بصوت للمستخدم.
///
/// كل نصوص قابلة للتعديل من شاشة "أسئلة الحوار الصوتي".
/// القيم الافتراضية محفوظة هنا كـ "مصدر حقيقة".
///
/// المتغيرات المدعومة (تُستبدل تلقائيًا):
/// {type}      → "دين" / "سداد" / "مرتجع"
/// {amount}    → "500"
/// {currency}  → "ريال"
/// {customer}  → "محمد"
/// {name}      → "أحمد"
/// {summary}   → "دين على محمد"
/// {max}       → "3"
class VoicePromptsService {
  // ═══════════════════════════════════════════════════════════
  // مفاتيح التخزين
  // ═══════════════════════════════════════════════════════════
  static const String _promptPrefix = 'voice_prompt_';
  static const String _responsePrefix = 'voice_response_';

  // ═══════════════════════════════════════════════════════════
  // مفاتيح الأسئلة (Prompts)
  // ═══════════════════════════════════════════════════════════
  static const String pAskIntent = 'ask_intent';
  static const String pAskCustomerDebt = 'ask_customer_debt';
  static const String pAskCustomerPayment = 'ask_customer_payment';
  static const String pAskCustomerReturn = 'ask_customer_return';
  static const String pAskCustomerUnknown = 'ask_customer_unknown';
  static const String pAskAmount = 'ask_amount';
  static const String pAskItems = 'ask_items';
  static const String pAskCustomerAmbiguous = 'ask_customer_ambiguous';
  static const String pConfirmChoice = 'confirm_choice';
  static const String pCancelWord = 'cancel_word';
  static const String pSkipItemsWord = 'skip_items_word';
  static const String pAddNewCustomerWord = 'add_new_customer_word';

  // ═══════════════════════════════════════════════════════════
  // مفاتيح الردود الصوتية (TTS Responses)
  // ═══════════════════════════════════════════════════════════
  static const String rStartListening = 'start_listening';
  static const String rStopListening = 'stop_listening';
  static const String rUnderstoodPartial = 'understood_partial';
  static const String rConfirmSave = 'confirm_save';
  static const String rSavedSuccess = 'saved_success';
  static const String rUnknownMax = 'unknown_max';
  static const String rNoAccount = 'no_account';
  static const String rCancelled = 'cancelled';
  static const String rChooseFromList = 'choose_from_list';
  static const String rAddingNew = 'adding_new';

  // ═══════════════════════════════════════════════════════════
  // القيم الافتراضية للأسئلة
  // ═══════════════════════════════════════════════════════════
  static const Map<String, String> _defaultPrompts = {
    pAskIntent: 'دين أم سداد أم مرتجع؟',
    pAskCustomerDebt: 'على من أسجل؟',
    pAskCustomerPayment: 'لمن أوصل؟',
    pAskCustomerReturn: 'مرتجع على من؟',
    pAskCustomerUnknown: 'على من أسجل؟',
    pAskAmount: 'كم المبلغ؟',
    pAskItems: 'ما البيان؟ قل "بدون بيان" لتخطي السؤال',
    pAskCustomerAmbiguous:
        'لا يوجد حساب باسم "{name}" — هل تقصد أحد هؤلاء؟',
    pConfirmChoice: 'قل الرقم أو الاسم، أو "أضف جديد"',
    pCancelWord: 'إلغاء',
    pSkipItemsWord: 'بدون بيان',
    pAddNewCustomerWord: 'أضف جديد',
  };

  // ═══════════════════════════════════════════════════════════
  // القيم الافتراضية للردود الصوتية
  // ═══════════════════════════════════════════════════════════
  static const Map<String, String> _defaultResponses = {
    rStartListening: 'جاري الاستماع...',
    rStopListening: 'تم',
    rUnderstoodPartial: 'فهمت: {summary}',
    rConfirmSave:
        'تم تسجيل {type} {amount} {currency} على {customer}',
    rSavedSuccess: 'تم الحفظ بنجاح',
    rUnknownMax:
        'لم أفهمك بعد {max} محاولات. تم حفظ التسجيل في السجل.',
    rNoAccount: 'لا يوجد حساب باسم {name}',
    rCancelled: 'تم الإلغاء',
    rChooseFromList: 'قل الرقم أو الاسم',
    rAddingNew: 'سيتم إضافة حساب جديد باسم {name}',
  };

  // ═══════════════════════════════════════════════════════════
  // Cache في الذاكرة
  // ═══════════════════════════════════════════════════════════
  static Map<String, String> _promptsCache = {};
  static Map<String, String> _responsesCache = {};
  static bool _loaded = false;

  // ═══════════════════════════════════════════════════════════
  // التهيئة
  // ═══════════════════════════════════════════════════════════

  /// يُستدعى من main() مرة واحدة عند بدء التطبيق
  static Future<void> init() async {
    if (_loaded) return;
    await reload();
  }

  /// إعادة تحميل النصوص من SharedPreferences
  static Future<void> reload() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // الأسئلة
      _promptsCache = {};
      for (final entry in _defaultPrompts.entries) {
        _promptsCache[entry.key] =
            sp.getString('$_promptPrefix${entry.key}') ?? entry.value;
      }

      // الردود
      _responsesCache = {};
      for (final entry in _defaultResponses.entries) {
        _responsesCache[entry.key] =
            sp.getString('$_responsePrefix${entry.key}') ?? entry.value;
      }

      _loaded = true;
      debugPrint(
          '✅ [VoicePrompts] Loaded ${_promptsCache.length} prompts + ${_responsesCache.length} responses');
    } catch (e) {
      debugPrint('❌ [VoicePrompts] reload error: $e');
      _promptsCache = Map.from(_defaultPrompts);
      _responsesCache = Map.from(_defaultResponses);
      _loaded = true;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // القراءة
  // ═══════════════════════════════════════════════════════════

  /// جلب نص سؤال، مع استبدال المتغيرات
  static String getPrompt(String key, {Map<String, String>? vars}) {
    if (!_loaded) {
      return _substitute(_defaultPrompts[key] ?? '', vars);
    }
    final text = _promptsCache[key] ?? _defaultPrompts[key] ?? '';
    return _substitute(text, vars);
  }

  /// جلب نص رد صوتي، مع استبدال المتغيرات
  static String getResponse(String key, {Map<String, String>? vars}) {
    if (!_loaded) {
      return _substitute(_defaultResponses[key] ?? '', vars);
    }
    final text = _responsesCache[key] ?? _defaultResponses[key] ?? '';
    return _substitute(text, vars);
  }

  /// استبدال المتغيرات {var} بقيمها
  static String _substitute(String text, Map<String, String>? vars) {
    if (vars == null || vars.isEmpty) return text;
    String result = text;
    for (final entry in vars.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<void> setPrompt(String key, String value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cleaned = value.trim();

      if (cleaned.isEmpty || cleaned == _defaultPrompts[key]) {
        await sp.remove('$_promptPrefix$key');
        _promptsCache[key] = _defaultPrompts[key] ?? '';
      } else {
        await sp.setString('$_promptPrefix$key', cleaned);
        _promptsCache[key] = cleaned;
      }
      debugPrint('✅ [VoicePrompts] Saved prompt: $key');
    } catch (e) {
      debugPrint('❌ [VoicePrompts] setPrompt: $e');
    }
  }

  static Future<void> setResponse(String key, String value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cleaned = value.trim();

      if (cleaned.isEmpty || cleaned == _defaultResponses[key]) {
        await sp.remove('$_responsePrefix$key');
        _responsesCache[key] = _defaultResponses[key] ?? '';
      } else {
        await sp.setString('$_responsePrefix$key', cleaned);
        _responsesCache[key] = cleaned;
      }
      debugPrint('✅ [VoicePrompts] Saved response: $key');
    } catch (e) {
      debugPrint('❌ [VoicePrompts] setResponse: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الاستعادة
  // ═══════════════════════════════════════════════════════════

  static Future<void> resetPrompt(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('$_promptPrefix$key');
      _promptsCache[key] = _defaultPrompts[key] ?? '';
    } catch (e) {
      debugPrint('❌ [VoicePrompts] resetPrompt: $e');
    }
  }

  static Future<void> resetResponse(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('$_responsePrefix$key');
      _responsesCache[key] = _defaultResponses[key] ?? '';
    } catch (e) {
      debugPrint('❌ [VoicePrompts] resetResponse: $e');
    }
  }

  static Future<void> resetAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final key in _defaultPrompts.keys) {
        await sp.remove('$_promptPrefix$key');
      }
      for (final key in _defaultResponses.keys) {
        await sp.remove('$_responsePrefix$key');
      }
      _promptsCache = Map.from(_defaultPrompts);
      _responsesCache = Map.from(_defaultResponses);
      debugPrint('✅ [VoicePrompts] Reset ALL to defaults');
    } catch (e) {
      debugPrint('❌ [VoicePrompts] resetAll: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // حالة التعديل
  // ═══════════════════════════════════════════════════════════

  static bool isPromptModified(String key) {
    if (!_loaded) return false;
    return _promptsCache[key] != _defaultPrompts[key];
  }

  static bool isResponseModified(String key) {
    if (!_loaded) return false;
    return _responsesCache[key] != _defaultResponses[key];
  }

  static bool get hasAnyModification {
    for (final key in _defaultPrompts.keys) {
      if (isPromptModified(key)) return true;
    }
    for (final key in _defaultResponses.keys) {
      if (isResponseModified(key)) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // للعرض
  // ═══════════════════════════════════════════════════════════

  static Map<String, String> getAllPrompts() =>
      Map<String, String>.from(_promptsCache);

  static Map<String, String> getAllResponses() =>
      Map<String, String>.from(_responsesCache);

  static String getDefaultPrompt(String key) => _defaultPrompts[key] ?? '';

  static String getDefaultResponse(String key) => _defaultResponses[key] ?? '';
}

// VoicePromptsService v1: خدمة نصوص الحوار الصوتي
// - جدولان: أسئلة (12) + ردود TTS (10)
// - استبدال متغيرات {type}, {amount}, {customer}, {name}, {summary}, {max}
// - تخزين في SharedPreferences
// - تعديل فوري بدون بناء
