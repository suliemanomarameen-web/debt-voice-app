import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import 'accountant_service.dart';
import 'accountants_service.dart';
import 'code_service.dart';
import 'crypto_service.dart';
import 'device_service.dart';
import 'gdrive_service.dart';
import 'link_code_service.dart';
import 'settings_service.dart';

/// نتيجة الخطوة 1: التحقق من الملف المشترك
class LinkInitResult {
  final bool success;
  final String message;

  /// هل الملف مشفر؟ (يحتاج كلمة مرور + رمز ربط)
  final bool needsPassword;

  /// معرف الملف (لإعادة استخدامه في الخطوة 2)
  final String? fileId;

  /// البيانات العادية (إذا لم يكن مشفراً)
  final Map<String, dynamic>? plainData;

  LinkInitResult({
    required this.success,
    required this.message,
    this.needsPassword = false,
    this.fileId,
    this.plainData,
  });

  factory LinkInitResult.fail(String msg) =>
      LinkInitResult(success: false, message: msg);

  factory LinkInitResult.needsPasswordInput(String fileId) => LinkInitResult(
        success: true,
        message: 'الملف مشفر — أدخل كلمة المرور ورمز الربط',
        needsPassword: true,
        fileId: fileId,
      );

  factory LinkInitResult.plainReady(Map<String, dynamic> data) =>
      LinkInitResult(
        success: true,
        message: 'تم العثور على الملف',
        needsPassword: false,
        plainData: data,
      );
}

/// نتيجة الخطوة 2: إكمال الربط
class LinkResult {
  final bool success;
  final String message;
  final String? accountantName;
  final String? accountantCode;

  LinkResult({
    required this.success,
    required this.message,
    this.accountantName,
    this.accountantCode,
  });

  factory LinkResult.fail(String msg) =>
      LinkResult(success: false, message: msg);

  factory LinkResult.ok(String name, String code) => LinkResult(
        success: true,
        message: 'تم الربط بنجاح',
        accountantName: name,
        accountantCode: code,
      );
}

class PrimaryLinkService {
  // ═══════════════════════════════════════════════════════════
  // الخطوة 1: التحقق من وجود الملف المشترك
  // ═══════════════════════════════════════════════════════════
  static Future<LinkInitResult> requestLinkInit(
      String primaryEmailRaw) async {
    try {
      final primaryEmail = primaryEmailRaw.trim().toLowerCase();

      if (!primaryEmail.contains('@') || primaryEmail.length < 5) {
        return LinkInitResult.fail('بريد إلكتروني غير صالح');
      }

      if (!GDriveService.isSignedIn) {
        final err = await GDriveService.signInWithError();
        if (err != null) {
          return LinkInitResult.fail('فشل تسجيل الدخول: $err');
        }
      }

      final myEmail = GDriveService.userEmail;
      if (myEmail == null || myEmail.isEmpty) {
        return LinkInitResult.fail(
            'لم نتمكن من قراءة إيميل Google الخاص بك');
      }

      if (myEmail.toLowerCase() == primaryEmail) {
        return LinkInitResult.fail(
          'لا يمكنك ربط جهازك بنفسك.\n\n'
          'أدخل إيميل المحاسب الأساسي (شخص آخر).',
        );
      }

      final fileId = await GDriveService.findSharedSyncFileId();
      if (fileId == null) {
        return LinkInitResult.fail(
          'لم يتم العثور على ملف مزامنة مشترك.\n\n'
          'تأكد من:\n'
          '• الأساسي أضاف إيميلك ($myEmail) في "إدارة المحاسبين"\n'
          '• الأساسي قام بعمل مزامنة واحدة على الأقل بعد إضافتك\n'
          '• أنت مسجل دخول بإيميلك ($myEmail)',
        );
      }

      final raw = await GDriveService.downloadRawSyncFileById(fileId);
      if (raw == null) {
        return LinkInitResult.fail('فشل تنزيل الملف من Drive');
      }

      // ملف غير مشفر → جاهز للربط مباشرة
      if (!raw.isEncrypted) {
        final data = raw.plainData;
        if (data == null) {
          return LinkInitResult.fail('الملف تالف أو غير صالح');
        }
        return LinkInitResult.plainReady(data);
      }

      // ملف مشفر → نحتاج كلمة مرور + رمز ربط
      return LinkInitResult.needsPasswordInput(fileId);
    } catch (e) {
      debugPrint('❌ requestLinkInit error: $e');
      return LinkInitResult.fail('خطأ غير متوقع: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الخطوة 2: إكمال الربط
  // ═══════════════════════════════════════════════════════════
  static Future<LinkResult> completeLink({
    required String primaryEmail,
    String? password,
    String? linkCode,
  }) async {
    try {
      // 1. التحقق من الإيميل
      final cleanPrimaryEmail = primaryEmail.trim().toLowerCase();
      if (!cleanPrimaryEmail.contains('@')) {
        return LinkResult.fail('بريد إلكتروني غير صالح');
      }

      // 2. البحث عن الملف المشترك
      final fileId = await GDriveService.findSharedSyncFileId();
      if (fileId == null) {
        return LinkResult.fail(
            'لم يتم العثور على الملف المشترك.\nتأكد من أن الأساسي شاركه معك.');
      }

      // 3. تنزيل الملف الخام
      final raw = await GDriveService.downloadRawSyncFileById(fileId);
      if (raw == null) {
        return LinkResult.fail('فشل تنزيل الملف من Drive');
      }

      Map<String, dynamic>? data;

      // 4. معالجة الملف
      if (raw.isEncrypted) {
        // يحتاج كلمة مرور + رمز ربط
        if (password == null || password.trim().isEmpty) {
          return LinkResult.fail('كلمة المرور مطلوبة');
        }
        if (linkCode == null || linkCode.trim().isEmpty) {
          return LinkResult.fail('رمز الربط مطلوب');
        }

        // تحليل رمز الربط
        final parsed = LinkCodeService.parse(linkCode);
        if (parsed == null) {
          return LinkResult.fail(
            'رمز الربط غير صالح.\n\n'
            'تأكد من نسخه كاملاً من جهاز الأساسي.',
          );
        }

        // التحقق من الرمز مقابل primary_device_id
        final primaryIdFromFile = raw.plainData?['primary_device_id'];
        // ملاحظة: raw.plainData سيكون null للملف المشفر
        // لذا نتحقق من الرمز مقابل ما سنحصل عليه لاحقاً بعد فك التشفير

        // فك التشفير
        try {
          data = await CryptoService.decryptDataWithSalt(
            raw.encryptedPayload!,
            password.trim(),
            parsed.saltBase64,
          );
        } catch (e) {
          debugPrint('❌ Decrypt failed: $e');
          return LinkResult.fail(
            'فشل فك التشفير.\n\n'
            'تأكد من:\n'
            '• كلمة المرور صحيحة\n'
            '• رمز الربط صحيح\n'
            '• الرمز ينتمي لنفس جهاز الأساسي',
          );
        }

        // الآن بعد فك التشفير، نتحقق من primary_device_id
        final primaryId = data['primary_device_id'] as String?;
        if (!LinkCodeService.matchesPrimaryDevice(parsed, primaryId)) {
          return LinkResult.fail(
            'رمز الربط لا ينتمي لهذا الملف.\n\n'
            'تأكد من استخدام رمز الربط الصحيح من نفس الجهاز الأساسي.',
          );
        }

        // حفظ كلمة المرور + salt للاستخدام المستقبلي (المزامنات القادمة)
        try {
          await CryptoService.setMasterPasswordWithSalt(
            password.trim(),
            parsed.saltBase64,
          );
          debugPrint('✅ Password + salt saved locally');
        } catch (e) {
          debugPrint('⚠️ Failed to save password: $e');
          // لا نُفشل العملية — الربط قد يعمل
        }
      } else {
        // ملف غير مشفر
        data = raw.plainData;
        if (data == null) {
          return LinkResult.fail('الملف تالف أو غير صالح');
        }
      }

      // 5. استيراد المحاسبين
      await AccountantsService.loadFromSync(data);
      final all = AccountantsService.getAll();

      // 6. البحث عن حسابي بالإيميل
      final myEmail = GDriveService.userEmail?.toLowerCase();
      if (myEmail == null) {
        return LinkResult.fail('لم نتمكن من قراءة إيميلك');
      }

      final mine = all
          .where((a) => a.email?.toLowerCase() == myEmail)
          .toList();

      if (mine.isEmpty) {
        return LinkResult.fail(
          'إيميلك ($myEmail) غير مضاف كـ محاسب.\n\n'
          'اطلب من الأساسي إضافتك:\n'
          'الإعدادات ← إدارة المحاسبين ← "+ محاسب جديد"',
        );
      }

      if (mine.length > 1) {
        return LinkResult.fail(
          'يوجد أكثر من محاسب بنفس الإيميل.\n'
          'تواصل مع الأساسي لحل التعارض.',
        );
      }

      final myAcc = mine.first;
      final myDeviceId = await DeviceService.getDeviceId();

      // 7. التحقق: هل الحساب مرتبط بجهاز آخر؟
      if (myAcc.deviceId != null &&
          myAcc.deviceId!.isNotEmpty &&
          myAcc.deviceId != myDeviceId) {
        return LinkResult.fail(
          'حسابك مرتبط بجهاز آخر بالفعل.\n\n'
          'تواصل مع الأساسي لإلغاء ربط الجهاز القديم أولاً.',
        );
      }

      // 8. ربط الجهاز بحسابي
      await AccountantsService.updateAccountant(
        id: myAcc.id,
        deviceId: myDeviceId,
      );

      // 9. تعيين primary_device_id
      final primaryDeviceId = data['primary_device_id'] as String?;
      if (primaryDeviceId != null && primaryDeviceId.isNotEmpty) {
        await DeviceService.setPrimaryDeviceId(primaryDeviceId);
      } else {
        final primary = all.where((a) => a.isPrimary).toList();
        if (primary.isNotEmpty && primary.first.deviceId != null) {
          await DeviceService.setPrimaryDeviceId(primary.first.deviceId!);
        }
      }

      // 10. حالة الجهاز: مصرح
      await DeviceService.setDeviceStatus(DeviceService.statusAuthorized);

      // 11. اسم المحاسب (للعمليات والسجل)
      await AccountantService.setAccountantName(myAcc.name);

      // 12. استيراد الإعدادات المشتركة
      await _importSharedSettings(data);

      // 13. استيراد إعدادات رموز العمليات
      await _importCodeSettings(data);

      // 14. حذف ملفي الخاص (لتفادي التعارض)
      await GDriveService.deleteOwnSyncFileIfExists();

      // 15. إشعار المزامنة
      DatabaseHelper.onDataChanged?.call();

      debugPrint('✅ Linked as: ${myAcc.name} (${myAcc.code})');
      return LinkResult.ok(myAcc.name, myAcc.code);
    } catch (e) {
      debugPrint('❌ completeLink error: $e');
      return LinkResult.fail('خطأ غير متوقع: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // دوال مساعدة
  // ═══════════════════════════════════════════════════════════

  static Future<void> _importSharedSettings(Map<String, dynamic> data) async {
    final settingsMap = data['settings'] as Map<String, dynamic>?;
    if (settingsMap == null) return;

    for (final entry in settingsMap.entries) {
      if (AppSettings.sharedSettings.contains(entry.key)) {
        try {
          await SettingsService.set(entry.key, entry.value);
        } catch (e) {
          debugPrint('⚠️ Import setting ${entry.key}: $e');
        }
      }
    }
    debugPrint('✅ Imported shared settings');
  }

  static Future<void> _importCodeSettings(Map<String, dynamic> data) async {
    final codeMap = data['code_settings'] as Map<String, dynamic>?;
    if (codeMap == null) return;

    try {
      if (codeMap['debt_prefix'] is String) {
        await CodeService.setDebtPrefix(codeMap['debt_prefix'] as String);
      }
      if (codeMap['payment_prefix'] is String) {
        await CodeService.setPaymentPrefix(codeMap['payment_prefix'] as String);
      }
      if (codeMap['return_prefix'] is String) {
        await CodeService.setReturnPrefix(codeMap['return_prefix'] as String);
      }
      if (codeMap['digits'] is int) {
        await CodeService.setDigits(codeMap['digits'] as int);
      }
      if (codeMap['mode'] is String) {
        await CodeService.setMode(codeMap['mode'] as String);
      }
      if (codeMap['enabled'] is bool) {
        await CodeService.setEnabled(codeMap['enabled'] as bool);
      }
      debugPrint('✅ Imported code settings');
    } catch (e) {
      debugPrint('⚠️ Import code settings: $e');
    }
  }
}
