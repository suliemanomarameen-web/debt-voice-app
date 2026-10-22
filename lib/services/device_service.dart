import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// خدمة إدارة هوية الجهاز
/// - تولّد device_id فريداً عند أول تشغيل
/// - تخزّن حالة الترخيص محلياً
/// - تُدير معرّف الجهاز الأساسي
class DeviceService {
  static const _storage = FlutterSecureStorage();

  static const _keyDeviceId = 'device_id';
  static const _keyDeviceName = 'device_name';
  static const _keyDeviceStatus = 'device_status'; // pending | authorized | revoked
  static const _keyPrimaryDeviceId = 'primary_device_id';
  static const _keyDeviceAccountantCode = 'device_accountant_code';

  static const String statusPending = 'pending';
  static const String statusAuthorized = 'authorized';
  static const String statusRevoked = 'revoked';

  // ========== device_id ==========
  static Future<String> getDeviceId() async {
    var id = await _storage.read(key: _keyDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.write(key: _keyDeviceId, value: id);
    }
    return id;
  }

  static Future<void> resetDeviceId() async {
    await _storage.delete(key: _keyDeviceId);
  }

  // ========== device_name ==========
  static Future<String?> getDeviceName() async {
    return _storage.read(key: _keyDeviceName);
  }

  static Future<void> setDeviceName(String name) async {
    await _storage.write(key: _keyDeviceName, value: name.trim());
  }

  // ========== device_status ==========
  static Future<String> getDeviceStatus() async {
    final v = await _storage.read(key: _keyDeviceStatus);
    return v ?? statusPending;
  }

  static Future<void> setDeviceStatus(String status) async {
    await _storage.write(key: _keyDeviceStatus, value: status);
  }

  static Future<bool> isAuthorized() async {
    return await getDeviceStatus() == statusAuthorized;
  }

  // ========== primary_device_id ==========
  static Future<String?> getPrimaryDeviceId() async {
    return _storage.read(key: _keyPrimaryDeviceId);
  }

  static Future<void> setPrimaryDeviceId(String id) async {
    await _storage.write(key: _keyPrimaryDeviceId, value: id);
  }

  static Future<bool> isPrimaryDevice() async {
    final primaryId = await getPrimaryDeviceId();
    if (primaryId == null) return false;
    final myId = await getDeviceId();
    return primaryId == myId;
  }

  // ========== رمز المحاسب على هذا الجهاز ==========
  static Future<String?> getAccountantCode() async {
    return _storage.read(key: _keyDeviceAccountantCode);
  }

  static Future<void> setAccountantCode(String code) async {
    if (code.trim().isEmpty) {
      await _storage.delete(key: _keyDeviceAccountantCode);
    } else {
      await _storage.write(key: _keyDeviceAccountantCode, value: code.trim());
    }
  }

  // ========== مسح كامل ==========
  static Future<void> clearAll() async {
    await _storage.delete(key: _keyDeviceId);
    await _storage.delete(key: _keyDeviceName);
    await _storage.delete(key: _keyDeviceStatus);
    await _storage.delete(key: _keyPrimaryDeviceId);
    await _storage.delete(key: _keyDeviceAccountantCode);
  }
}
