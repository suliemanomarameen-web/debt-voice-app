import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import 'accountants_service.dart';
import 'device_service.dart';

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

  static const String _pendingPolicyRequestKey = 'pending_delete_policy_requests_v1';
  static const String _policyApprovalKey = 'delete_policy_approval_v1';
  static const String _policyRevisionKey = 'delete_policy_revision_v1';
  static bool _writingPolicyInternally = false;

  static const Set<String> _policyKeys = {
    AppSettings.permanentDeleteAlwaysWins,
    AppSettings.modificationAlwaysWins,
    AppSettings.softDeleteAlwaysWins,
    AppSettings.softModificationAlwaysWins,
  };

  /// 🆕 يُستدعى عند تغيير أي إعداد مشترك (للمزامنة)
  static void Function()? onChanged;

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
    if (_policyKeys.contains(key) && !_writingPolicyInternally) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, value);
      _cache[key] = value;
      debugPrint('✅ [Settings] $key = $value');
      _notifyIfShared(key);
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
      _notifyIfShared(key);
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
      _notifyIfShared(key);
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
      _notifyIfShared(key);
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


  /// تغيير سياسة واحدة. المحاسب يحتاج صلاحية مستقلة؛ لا تمنحه هذه الصلاحية
  /// حق الوصول إلى بقية الإعدادات المتقدمة.
  static Future<bool> setDeleteConflictPolicy({
    required bool softDelete,
    required String mode,
  }) async {
    if (!{'delete', 'modification', 'latest'}.contains(mode)) return false;

    final isPrimary = await DeviceService.isPrimaryDevice();
    final accountant = isPrimary ? null : await AccountantsService.getCurrentAccountant();
    if (!isPrimary &&
        (accountant == null ||
            accountant.status != 'active' ||
            !accountant.can('change_delete_conflict_policy'))) {
      return false;
    }

    final keys = softDelete
        ? [AppSettings.softDeleteAlwaysWins, AppSettings.softModificationAlwaysWins]
        : [AppSettings.permanentDeleteAlwaysWins, AppSettings.modificationAlwaysWins];
    final deleteWins = mode == 'delete';
    final modificationWins = mode == 'modification';
    final values = <String, bool>{
      keys[0]: deleteWins,
      keys[1]: modificationWins,
    };

    final previousValues = <String, bool>{
      for (final key in keys)
        key: getBool(key, defaultValue: AppSettings.defaults[key] as bool),
    };
    int? previousRevision;
    String? previousApproval;
    try {
      final sp = await SharedPreferences.getInstance();
      previousRevision = sp.getInt(_policyRevisionKey);
      previousApproval = sp.getString(_policyApprovalKey);
      _writingPolicyInternally = true;
      for (final entry in values.entries) {
        if (!await sp.setBool(entry.key, entry.value)) {
          throw StateError('تعذر حفظ سياسة التعارض');
        }
        _cache[entry.key] = entry.value;
      }
      _writingPolicyInternally = false;

      final deviceId = await DeviceService.getDeviceId();
      final currentSettings = <String, bool>{
        for (final key in _policyKeys)
          key: getBool(key, defaultValue: AppSettings.defaults[key] as bool),
      };

      if (isPrimary) {
        final revision = (sp.getInt(_policyRevisionKey) ?? -1) + 1;
        await sp.setInt(_policyRevisionKey, revision);
        final primaryId = await DeviceService.getPrimaryDeviceId() ?? deviceId;
        await sp.setString(_policyApprovalKey, jsonEncode({
          'approved': true,
          'revision': revision,
          'approved_by_device_id': primaryId,
          'updated_at': DateTime.now().toIso8601String(),
          'settings': currentSettings,
        }));
      } else {
        final request = {
          'request_id': '$deviceId-${DateTime.now().microsecondsSinceEpoch}',
          'actor_accountant_id': accountant!.id,
          'actor_device_id': deviceId,
          'created_at': DateTime.now().toIso8601String(),
          'base_revision': sp.getInt(_policyRevisionKey) ?? -1,
          'settings': currentSettings,
        };
        final existing = await getPendingDeletePolicyRequests();
        existing.removeWhere((item) =>
            item['actor_accountant_id'] == accountant.id &&
            item['actor_device_id'] == deviceId);
        existing.add(request);
        await sp.setString(_pendingPolicyRequestKey, jsonEncode(existing));
      }

      _notifyIfShared(keys.first);
      return true;
    } catch (e) {
      _writingPolicyInternally = true;
      try {
        final rollbackSp = await SharedPreferences.getInstance();
        for (final entry in previousValues.entries) {
          await rollbackSp.setBool(entry.key, entry.value);
          _cache[entry.key] = entry.value;
        }
        if (previousRevision == null) {
          await rollbackSp.remove(_policyRevisionKey);
        } else {
          await rollbackSp.setInt(_policyRevisionKey, previousRevision);
        }
        if (previousApproval == null) {
          await rollbackSp.remove(_policyApprovalKey);
        } else {
          await rollbackSp.setString(_policyApprovalKey, previousApproval);
        }
      } catch (_) {}
      _writingPolicyInternally = false;
      debugPrint('❌ [Settings] setDeleteConflictPolicy: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingDeletePolicyRequests() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_pendingPolicyRequestKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (decoded is Map) return [Map<String, dynamic>.from(decoded)];
    } catch (_) {}
    return [];
  }

  static Future<void> mergePendingDeletePolicyRequests(List<dynamic> incoming) async {
    final sp = await SharedPreferences.getInstance();
    final merged = await getPendingDeletePolicyRequests();
    final ids = merged.map((e) => e['request_id']?.toString()).toSet();
    for (final item in incoming) {
      if (item is! Map) continue;
      final request = Map<String, dynamic>.from(item);
      final id = request['request_id']?.toString();
      if (id != null && id.isNotEmpty && ids.add(id)) merged.add(request);
    }
    await sp.setString(_pendingPolicyRequestKey, jsonEncode(merged));
  }

  static Future<void> removePendingDeletePolicyRequest(String? requestId) async {
    if (requestId == null || requestId.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final requests = await getPendingDeletePolicyRequests();
    requests.removeWhere((item) => item['request_id']?.toString() == requestId);
    await sp.setString(_pendingPolicyRequestKey, jsonEncode(requests));
  }

  static Future<Map<String, dynamic>> getDeletePolicyApproval() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_policyApprovalKey);
    if (raw != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    final Map<String, dynamic> fallback = {
      'approved': true,
      'revision': sp.getInt(_policyRevisionKey) ?? 0,
      'approved_by_device_id': await DeviceService.getPrimaryDeviceId(),
      'updated_at': '',
      'settings': {
        for (final key in _policyKeys)
          key: getBool(key, defaultValue: AppSettings.defaults[key] as bool),
      },
    };
    // يحفظ الجهاز الأساسي رقم الإصدار الابتدائي حتى لا يرفض أول طلب
    // قادم من جهاز ثانوي استقبل هذه السياسة.
    if (await DeviceService.isPrimaryDevice()) {
      await sp.setInt(_policyRevisionKey, fallback['revision'] as int);
      await sp.setString(_policyApprovalKey, jsonEncode(fallback));
    }
    return fallback;
  }

  static Future<int> getDeletePolicyRevision() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_policyRevisionKey) ?? -1;
  }

  /// اعتماد طلب قادم على الجهاز الأساسي بعد التحقق من هوية المحاسب وصلاحيته.
  static Future<Map<String, dynamic>> approveDeletePolicyRequest(
      Map<String, dynamic> request) async {
    final settings = Map<String, dynamic>.from(request['settings'] as Map? ?? {});
    final sp = await SharedPreferences.getInstance();
    final currentRevision = sp.getInt(_policyRevisionKey) ?? -1;
    final baseRevision = request['base_revision'] is int
        ? request['base_revision'] as int
        : -1;
    // لا نقبل طلباً بُني على سياسة أقدم من السياسة المعتمدة حالياً.
    // على الجهاز الثانوي أن يستقبل السياسة الأحدث أولاً ثم يعيد إرسال طلبه.
    if (baseRevision != currentRevision) {
      return await getDeletePolicyApproval();
    }
    if (_policyKeys.any((key) => settings[key] is! bool) ||
        (settings[AppSettings.permanentDeleteAlwaysWins] == true &&
            settings[AppSettings.modificationAlwaysWins] == true) ||
        (settings[AppSettings.softDeleteAlwaysWins] == true &&
            settings[AppSettings.softModificationAlwaysWins] == true)) {
      await removePendingDeletePolicyRequest(request['request_id']?.toString());
      return await getDeletePolicyApproval();
    }
    final revision = currentRevision + 1;
    await _applyDeletePolicyValues(settings);
    await sp.setInt(_policyRevisionKey, revision);
    final primaryId = await DeviceService.getDeviceId();
    final approval = {
      'approved': true,
      'revision': revision,
      'approved_by_device_id': primaryId,
      'actor_accountant_id': request['actor_accountant_id'],
      'actor_device_id': request['actor_device_id'],
      'request_id': request['request_id'],
      'updated_at': DateTime.now().toIso8601String(),
      'settings': {
        for (final key in _policyKeys)
          key: getBool(key, defaultValue: AppSettings.defaults[key] as bool),
      },
    };
    await sp.setString(_policyApprovalKey, jsonEncode(approval));
    await removePendingDeletePolicyRequest(request['request_id']?.toString());
    return approval;
  }

  /// تطبيق سياسة اعتمدها الجهاز الأساسي فقط.
  static Future<bool> applyApprovedDeletePolicy(
      Map<String, dynamic> approval) async {
    if (approval['approved'] != true || approval['revision'] is! int) return false;
    final revision = approval['revision'] as int;
    if (revision <= await getDeletePolicyRevision()) return false;
    final expectedPrimary = await DeviceService.getPrimaryDeviceId();
    if (expectedPrimary == null ||
        approval['approved_by_device_id'] != expectedPrimary) return false;
    final settings = Map<String, dynamic>.from(approval['settings'] as Map? ?? {});
    if (_policyKeys.any((key) => settings[key] is! bool) ||
        (settings[AppSettings.permanentDeleteAlwaysWins] == true &&
            settings[AppSettings.modificationAlwaysWins] == true) ||
        (settings[AppSettings.softDeleteAlwaysWins] == true &&
            settings[AppSettings.softModificationAlwaysWins] == true)) {
      return false;
    }
    await _applyDeletePolicyValues(settings);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_policyRevisionKey, revision);
    await sp.setString(_policyApprovalKey, jsonEncode(approval));
    await removePendingDeletePolicyRequest(approval['request_id']?.toString());
    return true;
  }

  static Future<void> _applyDeletePolicyValues(Map<String, dynamic> values) async {
    final sp = await SharedPreferences.getInstance();
    _writingPolicyInternally = true;
    try {
      for (final key in _policyKeys) {
        final value = values[key];
        if (value is bool) {
          await sp.setBool(key, value);
          _cache[key] = value;
        }
      }
    } finally {
      _writingPolicyInternally = false;
    }
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
      final preservedPolicy = <String, dynamic>{
        for (final key in _policyKeys)
          key: getBool(key, defaultValue: AppSettings.defaults[key] as bool),
      };
      for (final key in AppSettings.defaults.keys) {
        // سياسة التعارض لها اعتماد ومراجعة مستقلة؛ لا تُمسح عبر زر reset-all.
        if (_policyKeys.contains(key)) continue;
        await sp.remove(key);
      }
      _cache.clear();
      _cache.addAll(AppSettings.defaults);
      _cache.addAll(preservedPolicy);
      debugPrint('✅ [Settings] All reset to defaults');
      try {
        onChanged?.call();
      } catch (_) {}
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

  /// 🆕 يُخبر المزامنة بأن هناك تغييراً محلياً (إذا كان الإعداد مشتركاً)
  static void _notifyIfShared(String key) {
    if (AppSettings.isShared(key)) {
      try {
        onChanged?.call();
      } catch (e) {
        debugPrint('⚠️ [Settings] onChanged error: $e');
      }
    }
  }

  /// للاختبار
  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _loaded = false;
  }
}

// الإعدادات v2.1: إضافة onChanged callback لربط تغييرات الإعدادات المشتركة بالمزامنة
