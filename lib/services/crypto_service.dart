import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خدمة التشفير وإدارة كلمة المرور الرئيسية
/// - تخزّن كلمة المرور في Android Keystore (عبر flutter_secure_storage)
/// - تشتق مفتاحاً قوياً باستخدام PBKDF2
/// - تشفّر وتفكّ تشفير بيانات المزامنة باستخدام AES-256-GCM
class CryptoService {
  static const _storage = FlutterSecureStorage();

  static const _keyPassword = 'master_password';
  static const _keySalt = 'master_salt';
  static const _keyEnabled = 'encryption_enabled';

  // ========== إدارة كلمة المرور ==========
  static Future<bool> hasMasterPassword() async {
    final value = await _storage.read(key: _keyPassword);
    return value != null && value.isNotEmpty;
  }

  static Future<void> setMasterPassword(String password) async {
    if (password.trim().isEmpty) {
      throw Exception('كلمة المرور لا يمكن أن تكون فارغة');
    }
    final salt = _generateSalt();
    await _storage.write(key: _keySalt, value: base64Encode(salt));
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  /// 🆕 تعيين كلمة مرور مع salt محدد (عند الربط بالأساسي)
  /// يستخدم salt الأساسي بدلاً من توليد واحد جديد
  static Future<void> setMasterPasswordWithSalt(
    String password,
    String saltBase64,
  ) async {
    if (password.trim().isEmpty) {
      throw Exception('كلمة المرور لا يمكن أن تكون فارغة');
    }
    // التحقق من صحة base64
    try {
      base64Decode(saltBase64);
    } catch (e) {
      throw Exception('ملح التشفير غير صالح');
    }
    await _storage.write(key: _keySalt, value: saltBase64);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyEnabled, value: 'true');
  }

  static Future<String?> getMasterPassword() async {
    return _storage.read(key: _keyPassword);
  }

  /// 🆕 جلب الـ salt الحالي (base64) — للاستخدام في رمز الربط
  static Future<String?> getSaltBase64() async {
    return _storage.read(key: _keySalt);
  }

  static Future<void> deleteMasterPassword() async {
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyEnabled);
  }

  static Future<bool> isEncryptionEnabled() async {
    final v = await _storage.read(key: _keyEnabled);
    return v == 'true';
  }

  // ========== التشفير وفك التشفير (باستخدام salt المحفوظ) ==========

  static Future<String> encryptData(Map<String, dynamic> data) async {
    final password = await getMasterPassword();
    if (password == null) {
      throw Exception('لا توجد كلمة مرور رئيسية');
    }

    final saltBase64 = await _storage.read(key: _keySalt);
    if (saltBase64 == null) {
      throw Exception('الملح (salt) غير موجود');
    }
    final salt = base64Decode(saltBase64);
    final key = await _deriveKey(password, salt);

    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final plainText = utf8.encode(jsonEncode(data));
    final secretBox = await algorithm.encrypt(
      plainText,
      secretKey: key,
      nonce: nonce,
    );

    final combined = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);

    return base64Encode(combined);
  }

  static Future<Map<String, dynamic>> decryptData(
      String encryptedBase64) async {
    final password = await getMasterPassword();
    if (password == null) {
      throw Exception('لا توجد كلمة مرور رئيسية');
    }

    final saltBase64 = await _storage.read(key: _keySalt);
    if (saltBase64 == null) {
      throw Exception('الملح (salt) غير موجود');
    }

    return await decryptDataWithSalt(
      encryptedBase64,
      password,
      saltBase64,
    );
  }

  /// 🆕 فك تشفير باستخدام salt خارجي (للربط بالأساسي)
  static Future<Map<String, dynamic>> decryptDataWithSalt(
    String encryptedBase64,
    String password,
    String saltBase64,
  ) async {
    final salt = base64Decode(saltBase64);
    final key = await _deriveKey(password, salt);

    final combined = base64Decode(encryptedBase64);

    const nonceLength = 12;
    const macLength = 16;

    if (combined.length < nonceLength + macLength) {
      throw Exception('البيانات المشفرة غير صالحة');
    }

    final nonce = combined.sublist(0, nonceLength);
    final cipherText = combined.sublist(
      nonceLength,
      combined.length - macLength,
    );
    final macBytes = combined.sublist(combined.length - macLength);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final algorithm = AesGcm.with256bits();
    final plainBytes = await algorithm.decrypt(secretBox, secretKey: key);
    final jsonStr = utf8.decode(plainBytes);

    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// 🆕 اختبار: هل كلمة المرور صحيحة لهذا الـ salt؟
  /// (دون حفظها)
  static Future<bool> testPasswordForSalt({
    required String password,
    required String saltBase64,
    required String encryptedSample,
  }) async {
    try {
      await decryptDataWithSalt(encryptedSample, password, saltBase64);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ========== أدوات داخلية ==========
  static Future<SecretKey> _deriveKey(String password, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static Uint8List _generateSalt() {
    final random = Random.secure();
    final salt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }
}
