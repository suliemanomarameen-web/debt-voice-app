import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'device_service.dart';

/// نموذج المحاسب
class Accountant {
  final String id;              // UUID
  final String name;            // اسم المحاسب
  final String code;            // رمز المحاسب (S، AHM، أو فارغ)
  final String? email;          // إيميل Google
  final String? deviceId;       // جهاز المحاسب
  final bool isPrimary;         // هل هو الجهاز الأساسي؟
  final Map<String, bool> permissions; // 16 صلاحية
  final String status;          // 'active' | 'revoked'
  final String createdAt;

  Accountant({
    required this.id,
    required this.name,
    this.code = '',
    this.email,
    this.deviceId,
    this.isPrimary = false,
    Map<String, bool>? permissions,
    this.status = 'active',
    required this.createdAt,
  }) : permissions = permissions ?? Map<String, bool>.from(defaultPermissions);

  // الصلاحيات الافتراضية
  static const Map<String, bool> defaultPermissions = {
    'add_customers': true,
    'edit_customers': true,
    'delete_customers': false,
    'toggle_customer_active': false,
    'edit_max_balance': false,
    'add_transactions': true,
    'edit_transactions': false,
    'delete_transactions': false,
    'view_all_transactions': true,
    'view_stats': true,
    'export_data': true,
    'view_logs': false,
    'access_advanced_settings': false,
    'manage_backups': false,
    'manage_accountants': false,
    'can_become_primary': false,
  };

  // الأسماء العربية للصلاحيات
  static const Map<String, String> permissionLabelsAr = {
    'add_customers': 'إضافة عملاء',
    'edit_customers': 'تعديل بيانات العملاء',
    'delete_customers': 'حذف العملاء',
    'toggle_customer_active': 'إيقاف/تفعيل العملاء',
    'edit_max_balance': 'تعديل حد الرصيد',
    'add_transactions': 'إضافة عمليات',
    'edit_transactions': 'تعديل العمليات',
    'delete_transactions': 'حذف العمليات',
    'view_all_transactions': 'عرض كل العمليات',
    'view_stats': 'عرض الإحصائيات',
    'export_data': 'تصدير Excel/CSV/PDF',
    'view_logs': 'مشاهدة سجل الأحداث',
    'access_advanced_settings': 'الإعدادات المتقدمة',
    'manage_backups': 'إدارة النسخ الاحتياطية',
    'manage_accountants': 'إدارة المحاسبين الآخرين',
    'can_become_primary': 'يمكنه أن يصبح أساسياً',
  };

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'email': email,
        'device_id': deviceId,
        'is_primary': isPrimary,
        'permissions': permissions,
        'status': status,
        'created_at': createdAt,
      };

  factory Accountant.fromMap(Map<String, dynamic> m) {
    final permsRaw = m['permissions'];
    final perms = <String, bool>{};
    if (permsRaw is Map) {
      for (final e in permsRaw.entries) {
        perms[e.key.toString()] = e.value == true;
      }
    }
    // أكمل الناقص بالافتراضي
    for (final e in defaultPermissions.entries) {
      perms.putIfAbsent(e.key, () => e.value);
    }

    return Accountant(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      code: m['code'] as String? ?? '',
      email: m['email'] as String?,
      deviceId: m['device_id'] as String?,
      isPrimary: m['is_primary'] == true,
      permissions: perms,
      status: m['status'] as String? ?? 'active',
      createdAt: m['created_at'] as String? ?? '',
    );
  }

  Accountant copyWith({
    String? name,
    String? code,
    String? email,
    String? deviceId,
    bool? isPrimary,
    Map<String, bool>? permissions,
    String? status,
  }) {
    return Accountant(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      email: email ?? this.email,
      deviceId: deviceId ?? this.deviceId,
      isPrimary: isPrimary ?? this.isPrimary,
      permissions: permissions ?? Map.from(this.permissions),
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  bool can(String permission) => permissions[permission] == true;
}

/// نموذج جهاز في الانتظار
class PendingDevice {
  final String deviceId;
  final String deviceName;
  final String? email;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String requestedAt;
  final String? authorizedAt;
  final String? accountantId;

  PendingDevice({
    required this.deviceId,
    required this.deviceName,
    this.email,
    this.status = 'pending',
    required this.requestedAt,
    this.authorizedAt,
    this.accountantId,
  });

  Map<String, dynamic> toMap() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'email': email,
        'status': status,
        'requested_at': requestedAt,
        'authorized_at': authorizedAt,
        'accountant_id': accountantId,
      };

  factory PendingDevice.fromMap(Map<String, dynamic> m) => PendingDevice(
        deviceId: m['device_id'] as String? ?? '',
        deviceName: m['device_name'] as String? ?? '',
        email: m['email'] as String?,
        status: m['status'] as String? ?? 'pending',
        requestedAt: m['requested_at'] as String? ?? '',
        authorizedAt: m['authorized_at'] as String?,
        accountantId: m['accountant_id'] as String?,
      );
}

/// خدمة إدارة المحاسبين
class AccountantsService {
  static const _uuid = Uuid();
  static const String _prefsKey = 'accountants_cache_v1';
  static const String _prefsDevicesKey = 'pending_devices_cache_v1';

  static List<Accountant> _accountants = [];
  static List<PendingDevice> _pendingDevices = [];
  static bool _loaded = false;

  // ═══════════════════════════════════════════════════════════
  // التحميل والحفظ
  // ═══════════════════════════════════════════════════════════

  static Future<void> init() async {
    if (_loaded) return;
    await _loadFromLocal();
    _loaded = true;
  }

  static Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJson = prefs.getString(_prefsKey);
      final devicesJson = prefs.getString(_prefsDevicesKey);

      if (accountsJson != null) {
        final list = jsonDecode(accountsJson) as List;
        _accountants = list
            .map((e) => Accountant.fromMap(e as Map<String, dynamic>))
            .toList();
      }
      if (devicesJson != null) {
        final list = jsonDecode(devicesJson) as List;
        _pendingDevices = list
            .map((e) => PendingDevice.fromMap(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('❌ [Accountants] loadLocal: $e');
    }
  }

  static Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_accountants.map((a) => a.toMap()).toList()),
      );
      await prefs.setString(
        _prefsDevicesKey,
        jsonEncode(_pendingDevices.map((d) => d.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('❌ [Accountants] saveLocal: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التكامل مع المزامنة
  // ═══════════════════════════════════════════════════════════

  /// يُستدعى من sync_service عند تنزيل بيانات من السحابة
  static Future<void> loadFromSync(Map<String, dynamic> syncData) async {
    try {
      final accList = syncData['accountants'] as List?;
      final devList = syncData['devices'] as List?;

      if (accList != null) {
        _accountants = accList
            .map((e) => Accountant.fromMap(e as Map<String, dynamic>))
            .toList();
      }
      if (devList != null) {
        _pendingDevices = devList
            .map((e) => PendingDevice.fromMap(e as Map<String, dynamic>))
            .toList();
      }
      await _saveToLocal();
      debugPrint(
          '✅ [Accountants] Loaded ${_accountants.length} accountants from sync');
    } catch (e) {
      debugPrint('❌ [Accountants] loadFromSync: $e');
    }
  }

  /// يُستدعى من sync_service قبل الرفع
  static Map<String, dynamic> getForSync() {
    return {
      'accountants': _accountants.map((a) => a.toMap()).toList(),
      'devices': _pendingDevices.map((d) => d.toMap()).toList(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // القراءة
  // ═══════════════════════════════════════════════════════════

  static List<Accountant> getAll() =>
      List<Accountant>.unmodifiable(_accountants);

  static List<Accountant> getActive() =>
      _accountants.where((a) => a.status == 'active').toList();

  static Accountant? getById(String id) {
    try {
      return _accountants.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// المحاسب المرتبط بالجهاز الحالي
  static Future<Accountant?> getCurrentAccountant() async {
    final deviceId = await DeviceService.getDeviceId();
    try {
      return _accountants.firstWhere((a) => a.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasAnyAccountants() async {
    return _accountants.isNotEmpty;
  }

  static Future<bool> isCurrentDevicePrimary() async {
    final current = await getCurrentAccountant();
    return current?.isPrimary == true;
  }

  // ═══════════════════════════════════════════════════════════
  // فحص الصلاحيات
  // ═══════════════════════════════════════════════════════════

  /// فحص صلاحية للمحاسب الحالي (على هذا الجهاز)
  static Future<bool> hasPermission(String permission) async {
    final current = await getCurrentAccountant();
    if (current == null) return false;
    return current.can(permission);
  }

  /// فحص صلاحية لمحاسب معين
  static bool canAccountant(String accountantId, String permission) {
    final acc = getById(accountantId);
    return acc?.can(permission) ?? false;
  }

  /// هل المحاسب الحالي يمكنه إدارة المحاسبين؟
  static Future<bool> canManageAccountants() async {
    return hasPermission('manage_accountants');
  }

  // ═══════════════════════════════════════════════════════════
  // CRUD المحاسبين (للأساسي فقط)
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> addAccountant({
    required String name,
    String code = '',
    String? email,
    String? deviceId,
    Map<String, bool>? permissions,
    bool isPrimary = false,
  }) async {
    try {
      // فحص الصلاحية
      if (!isPrimary && !await canManageAccountants()) {
        return {'success': false, 'message': 'ليس لديك صلاحية إضافة محاسبين'};
      }

      if (name.trim().isEmpty) {
        return {'success': false, 'message': 'الاسم مطلوب'};
      }

      // فحص عدم التكرار (اسم أو إيميل)
      final cleanName = name.trim();
      if (_accountants.any((a) => a.name == cleanName)) {
        return {'success': false, 'message': 'اسم المحاسب موجود مسبقاً'};
      }
      if (email != null &&
          email.isNotEmpty &&
          _accountants.any((a) => a.email == email)) {
        return {'success': false, 'message': 'الإيميل مستخدم مسبقاً'};
      }

      final newAcc = Accountant(
        id: _uuid.v4(),
        name: cleanName,
        code: code.trim(),
        email: email?.trim(),
        deviceId: deviceId,
        isPrimary: isPrimary,
        permissions: permissions,
        createdAt: DateTime.now().toIso8601String(),
      );

      _accountants.add(newAcc);
      await _saveToLocal();

      debugPrint('✅ [Accountants] Added: ${newAcc.name}');
      return {'success': true, 'accountant': newAcc};
    } catch (e) {
      debugPrint('❌ [Accountants] add: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateAccountant({
    required String id,
    String? name,
    String? code,
    String? email,
    Map<String, bool>? permissions,
    String? status,
  }) async {
    try {
      if (!await canManageAccountants()) {
        return {'success': false, 'message': 'ليس لديك صلاحية'};
      }

      final idx = _accountants.indexWhere((a) => a.id == id);
      if (idx == -1) {
        return {'success': false, 'message': 'المحاسب غير موجود'};
      }

      final current = _accountants[idx];
      final updated = current.copyWith(
        name: name?.trim(),
        code: code?.trim(),
        email: email?.trim(),
        permissions: permissions,
        status: status,
      );

      _accountants[idx] = updated;
      await _saveToLocal();

      debugPrint('✅ [Accountants] Updated: ${updated.name}');
      return {'success': true, 'accountant': updated};
    } catch (e) {
      debugPrint('❌ [Accountants] update: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  static Future<Map<String, dynamic>> removeAccountant(String id) async {
    try {
      if (!await canManageAccountants()) {
        return {'success': false, 'message': 'ليس لديك صلاحية'};
      }

      final acc = getById(id);
      if (acc == null) {
        return {'success': false, 'message': 'المحاسب غير موجود'};
      }
      if (acc.isPrimary) {
        return {'success': false, 'message': 'لا يمكن حذف المحاسب الأساسي'};
      }

      _accountants.removeWhere((a) => a.id == id);
      await _saveToLocal();

      debugPrint('✅ [Accountants] Removed: ${acc.name}');
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إدارة الأجهزة
  // ═══════════════════════════════════════════════════════════

  /// جهاز جديد يطلب الانضمام
  static Future<void> requestDeviceJoin({
    required String deviceId,
    required String deviceName,
    String? email,
  }) async {
    if (_pendingDevices.any((d) => d.deviceId == deviceId)) return;

    _pendingDevices.add(PendingDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      email: email,
      status: 'pending',
      requestedAt: DateTime.now().toIso8601String(),
    ));
    await _saveToLocal();
    debugPrint('📱 [Accountants] New pending device: $deviceName');
  }

  static List<PendingDevice> getPendingDevices() =>
      _pendingDevices.where((d) => d.status == 'pending').toList();

  static List<PendingDevice> getAllDevices() =>
      List<PendingDevice>.unmodifiable(_pendingDevices);

  /// قبول جهاز (وينشئ محاسب مرتبط به)
  static Future<Map<String, dynamic>> approveDevice({
    required String deviceId,
    required String accountantName,
    String code = '',
    Map<String, bool>? permissions,
  }) async {
    try {
      if (!await canManageAccountants()) {
        return {'success': false, 'message': 'ليس لديك صلاحية'};
      }

      final devIdx = _pendingDevices.indexWhere((d) => d.deviceId == deviceId);
      if (devIdx == -1) {
        return {'success': false, 'message': 'الجهاز غير موجود'};
      }

      final dev = _pendingDevices[devIdx];

      // إنشاء المحاسب
      final result = await addAccountant(
        name: accountantName,
        code: code,
        email: dev.email,
        deviceId: deviceId,
        permissions: permissions,
      );

      if (result['success'] != true) return result;

      final newAcc = result['accountant'] as Accountant;

      // تحديث حالة الجهاز
      _pendingDevices[devIdx] = PendingDevice(
        deviceId: dev.deviceId,
        deviceName: dev.deviceName,
        email: dev.email,
        status: 'approved',
        requestedAt: dev.requestedAt,
        authorizedAt: DateTime.now().toIso8601String(),
        accountantId: newAcc.id,
      );
      await _saveToLocal();

      return {
        'success': true,
        'accountant': newAcc,
        'device': _pendingDevices[devIdx],
      };
    } catch (e) {
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  static Future<bool> rejectDevice(String deviceId) async {
    try {
      if (!await canManageAccountants()) return false;

      final idx = _pendingDevices.indexWhere((d) => d.deviceId == deviceId);
      if (idx == -1) return false;

      final dev = _pendingDevices[idx];
      _pendingDevices[idx] = PendingDevice(
        deviceId: dev.deviceId,
        deviceName: dev.deviceName,
        email: dev.email,
        status: 'rejected',
        requestedAt: dev.requestedAt,
        authorizedAt: DateTime.now().toIso8601String(),
      );
      await _saveToLocal();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // مسح
  // ═══════════════════════════════════════════════════════════

  static Future<void> clearAll() async {
    _accountants = [];
    _pendingDevices = [];
    await _saveToLocal();
  }

  /// إعادة تحميل من التخزين المحلي (بعد تغيير مزامنة)
  static Future<void> reload() async {
    await _loadFromLocal();
  }
}
