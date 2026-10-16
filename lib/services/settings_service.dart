import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';

/// ═══════════════════════════════════════════════════════════
/// خدمة الإعدادات الموحّدة
/// - Cache في الذاكرة للأداء
/// - تقرأ من SharedPreferences
/// - تُزامن الإعدادات المشتركة إلى قاعدة البيانات (settings table)
/// ═══════════════════════════════════════════════════════════
class SettingsService {
  SettingsService._();

  static final Map<String, dynamic> _cache = {};
  static bool _loaded = false;

  // ═══════════════════════════════════════════════════════════
  // التحميل
  // ═══════════════════════════════════════════════════════════

  /// يُستدعى من main() عند بدء التطبيق
  static Future<void> init() async {
    if (_loaded) return;
    await loadAll();
  }

  /// تحميل كل الإعدادات
  static Future<void> loadAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _cache.clear();

      for (final entry in AppSettings.defaults.entries) {
        final key = entry.key;
        final defaultValue = entry.value;

        if (defaultValue is bool) {
          _cache[key] = sp.getBool(key) ?? defaultValue;
        } else if (defaultValue is int) {
          _cache[key] = sp.getInt(key) ?? defaultValue;
        } else if (defaultValue is double) {
          _cache[key] = sp.getDouble(key) ?? defaultValue;
        } else if (defaultValue is String) {
          _cache[key] = sp.getString(key) ?? defaultValue;
        } else {
          _cache[key] = defaultValue;
        }
      }

      _loaded = true;
      debugPrint('✅ [Settings] Loaded ${_cache.length} settings');
    } catch (e) {
      debugPrint('❌ [Settings] loadAll error: $e');
      // fallback للافتراضي
      _cache.clear();
      _cache.addAll(AppSettings.defaults);
      _loaded = true;
    }
  }

  /// إعادة تحميل (نادراً ما يُستخدم)
  static Future<void> reload() async {
    _loaded = false;
    await loadAll();
  }

  // ═══════════════════════════════════════════════════════════
  // القراءة
  // ═══════════════════════════════════════════════════════════

  static bool getBool(String key, {bool? defaultValue}) {
    _ensureLoaded();
    final v = _cache[key];
    if (v is bool) return v;
    if (defaultValue != null) return defaultValue;
    final def = AppSettings.defaults[key];
    return def is bool ? def : false;
  }

  static int getInt(String key, {int? defaultValue}) {
    _ensureLoaded();
    final v = _cache[key];
    if (v is int) return v;
    if (defaultValue != null) return defaultValue;
    final def = AppSettings.defaults[key];
    return def is int ? def : 0;
  }

  static double getDouble(String key, {double? defaultValue}) {
    _ensureLoaded();
    final v = _cache[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (defaultValue != null) return defaultValue;
    final def = AppSettings.defaults[key];
    return def is double ? def : 0.0;
  }

  static String getString(String key, {String? defaultValue}) {
    _ensureLoaded();
    final v = _cache[key];
    if (v is String) return v;
    if (defaultValue != null) return defaultValue;
    final def = AppSettings.defaults[key];
    return def is String ? def : '';
  }

  /// جلب كل الإعدادات (نسخة للعرض)
  static Map<String, dynamic> getAll() {
    _ensureLoaded();
    return Map<String, dynamic>.from(_cache);
  }

  /// هل الإعداد معدّل عن الافتراضي؟
  static bool isModified(String key) {
    _ensureLoaded();
    return _cache[key] != AppSettings.defaults[key];
  }

  /// أي إعدادات معدّلة عن الافتراضي؟
  static List<String> getModifiedKeys() {
    _ensureLoaded();
    final result = <String>[];
    for (final key in AppSettings.defaults.keys) {
      if (isModified(key)) result.add(key);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // الحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<bool> setBool(String key, bool value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, value);
      _cache[key] = value;
      debugPrint('✅ [Settings] $key = $value');
      return true;
    } catch (e) {
      debugPrint('❌ [Settings] setBool $key error: $e');
      return false;
    }
  }

  static Future<bool> setInt(String key, int value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(key, value);
      _cache[key] = value;
      debugPrint('✅ [Settings] $key = $value');
      return true;
    } catch (e) {
      debugPrint('❌ [Settings] setInt $key error: $e');
      return false;
    }
  }

  static Future<bool> setDouble(String key, double value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(key, value);
      _cache[key] = value;
      debugPrint('✅ [Settings] $key = $value');
      return true;
    } catch (e) {
      debugPrint('❌ [Settings] setDouble $key error: $e');
      return false;
    }
  }

  static Future<bool> setString(String key, String value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, value);
      _cache[key] = value;
      debugPrint('✅ [Settings] $key = $value');
      return true;
    } catch (e) {
      debugPrint('❌ [Settings] setString $key error: $e');
      return false;
    }
  }

  /// حفظ تلقائي حسب النوع
  static Future<bool> set(String key, dynamic value) async {
    if (value is bool) return setBool(key, value);
    if (value is int) return setInt(key, value);
    if (value is double) return setDouble(key, value);
    if (value is String) return setString(key, value);
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // الاستعادة
  // ═══════════════════════════════════════════════════════════

  /// استعادة إعداد واحد
  static Future<void> reset(String key) async {
    final def = AppSettings.defaults[key];
    if (def == null) return;
    await set(key, def);
  }

  /// استعادة مجموعة (مثلاً: كل إعدادات الحذف)
  static Future<void> resetGroup(List<String> keys) async {
    for (final key in keys) {
      await reset(key);
    }
  }

  /// استعادة كل الإعدادات
  static Future<void> resetAll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      for (final key in AppSettings.defaults.keys) {
        await sp.remove(key);
      }
      _cache.clear();
      _cache.addAll(AppSettings.defaults);
      debugPrint('✅ [Settings] All reset to defaults');
    } catch (e) {
      debugPrint('❌ [Settings] resetAll error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // المزامنة (اختياري — للإعدادات المشتركة)
  // ═══════════════════════════════════════════════════════════

  /// حفظ الإعدادات المشتركة في جدول settings (للمزامنة)
  static Future<void> syncSharedToDb() async {
    try {
      final db = DatabaseHelper.instance;
      for (final key in AppSettings.sharedSettings) {
        final value = _cache[key];
        if (value != null) {
          await db.setSetting('setting_$key', value.toString());
        }
      }
      debugPrint('✅ [Settings] Shared settings synced to DB');
    } catch (e) {
      debugPrint('❌ [Settings] syncSharedToDb error: $e');
    }
  }

  /// استرجاع الإعدادات المشتركة من الجدول
  static Future<void> loadSharedFromDb() async {
    try {
      final db = DatabaseHelper.instance;
      final all = await db.getAllSettings();
      for (final key in AppSettings.sharedSettings) {
        final strValue = all['setting_$key'];
        if (strValue != null) {
          final def = AppSettings.defaults[key];
          if (def is bool) {
            _cache[key] = strValue == 'true';
          } else if (def is int) {
            _cache[key] = int.tryParse(strValue) ?? def;
          } else if (def is double) {
            _cache[key] = double.tryParse(strValue) ?? def;
          } else {
            _cache[key] = strValue;
          }
        }
      }
      debugPrint('✅ [Settings] Shared settings loaded from DB');
    } catch (e) {
      debugPrint('❌ [Settings] loadSharedFromDb error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة داخلية
  // ═══════════════════════════════════════════════════════════

  static void _ensureLoaded() {
    if (!_loaded) {
      // fallback سريع إذا لم يُحمّل بعد
      _cache.addAll(AppSettings.defaults);
      _loaded = true;
    }
  }

  /// للاختبار
  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _loaded = false;
  }
}
