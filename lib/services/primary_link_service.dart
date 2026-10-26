import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import 'accountant_service.dart';
import 'accountants_service.dart';
import 'code_service.dart';
import 'device_service.dart';
import 'gdrive_service.dart';
import 'settings_service.dart';

/// نتيجة محاولة الربط
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
  /// ربط الجهاز الحالي بالمحاسب الأساسي
  static Future<LinkResult> linkToPrimary(String primaryEmailRaw) async {
    try {
      final primaryEmail = primaryEmailRaw.trim().toLowerCase();

      // 1. التحقق من الإيميل
      if (!primaryEmail.contains('@') || primaryEmail.length < 5) {
        return LinkResult.fail('بريد إلكتروني غير صالح');
      }

      // 2. تسجيل الدخول
      if (!GDriveService.isSignedIn) {
        final err = await GDriveService.signInWithError();
        if (err != null) {
          return LinkResult.fail('فشل تسجيل الدخول: $err');
        }
      }

      final myEmail = GDriveService.userEmail;
      if (myEmail == null || myEmail.isEmpty) {
        return LinkResult.fail('لم نتمكن من قراءة إيميل Google الخاص بك');
      }

      // 3. لا يمكن الربط بالنفس
      if (myEmail.toLowerCase() == primaryEmail) {
        return LinkResult.fail(
          'لا يمكنك ربط جهازك بنفسك.\n\n'
          'أدخل إيميل المحاسب الأساسي (شخص آخر).',
        );
      }

      // 4. البحث عن الملف المشترك
      final fileId = await GDriveService.findSharedSyncFileId();
      if (fileId == null) {
        return LinkResult.fail(
          'لم يتم العثور على ملف مزامنة مشترك.\n\n'
          'تأكد من:\n'
          '• الأساسي أضاف إيميلك ($myEmail) في "إدارة المحاسبين"\n'
          '• الأساسي قام بعمل مزامنة واحدة على الأقل بعد إضافتك\n'
          '• أنت مسجل دخول بإيميلك ($myEmail)',
        );
      }

      // 5. تنزيل الملف
      final data = await GDriveService.downloadSyncFileById(fileId);
      if (data == null) {
        return LinkResult.fail(
          'فشل تحميل الملف.\n\n'
          'إذا كان التشفير مفعلاً، تأكد من إدخال كلمة المرور أولاً.',
        );
      }

      // 6. استيراد قائمة المحاسبين
      await AccountantsService.loadFromSync(data);
      final all = AccountantsService.getAll();

      // 7. البحث عن حسابي بالإيميل
      final mine = all
          .where((a) => a.email?.toLowerCase() == myEmail.toLowerCase())
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

      // 8. التحقق: هل الحساب مرتبط بجهاز آخر؟
      if (myAcc.deviceId != null &&
          myAcc.deviceId!.isNotEmpty &&
          myAcc.deviceId != myDeviceId) {
        return LinkResult.fail(
          'حسابك مرتبط بجهاز آخر بالفعل.\n\n'
          'تواصل مع الأساسي لإلغاء ربط الجهاز القديم أولاً.',
        );
      }

      // 9. تسجيل deviceId على حسابي
      await AccountantsService.updateAccountant(
        id: myAcc.id,
        deviceId: myDeviceId,
      );

      // 10. تعيين primary_device_id
      final primaryDeviceId = data['primary_device_id'] as String?;
      if (primaryDeviceId != null && primaryDeviceId.isNotEmpty) {
        await DeviceService.setPrimaryDeviceId(primaryDeviceId);
      } else {
        final primary = all.where((a) => a.isPrimary).toList();
        if (primary.isNotEmpty && primary.first.deviceId != null) {
          await DeviceService.setPrimaryDeviceId(primary.first.deviceId!);
        }
      }

      // 11. حالة الجهاز: مصرح
      await DeviceService.setDeviceStatus(
          DeviceService.statusAuthorized);

      // 12. اسم المحاسب (للعمليات والسجل)
      await AccountantService.setAccountantName(myAcc.name);

      // 13. استيراد إعدادات رموز العمليات
      await _importCodeSettings(data);

      // 14. حذف ملف المزامنة الخاص بي إن وُجد (حتى لا يتعارض)
      await GDriveService.deleteOwnSyncFileIfExists();

      // 15. إشعار المزامنة بتغيير محلي (لتشغيل مزامنة تلقائية)
      DatabaseHelper.onDataChanged?.call();

      return LinkResult.ok(myAcc.name, myAcc.code);
    } catch (e) {
      debugPrint('❌ linkToPrimary error: $e');
      return LinkResult.fail('خطأ غير متوقع: $e');
    }
  }

  /// استيراد إعدادات رموز العمليات + الإعدادات المشتركة
  static Future<void> _importCodeSettings(
      Map<String, dynamic> data) async {
    // AppSettings المشتركة
    final settingsMap = data['settings'] as Map<String, dynamic>?;
    if (settingsMap != null) {
      for (final entry in settingsMap.entries) {
        if (AppSettings.sharedSettings.contains(entry.key)) {
          try {
            await SettingsService.set(entry.key, entry.value);
          } catch (e) {
            debugPrint('⚠️ Import setting ${entry.key}: $e');
          }
        }
      }
    }

    // إعدادات CodeService
    final codeMap = data['code_settings'] as Map<String, dynamic>?;
    if (codeMap != null) {
      try {
        if (codeMap['debt_prefix'] is String) {
          await CodeService.setDebtPrefix(codeMap['debt_prefix']);
        }
        if (codeMap['payment_prefix'] is String) {
          await CodeService.setPaymentPrefix(codeMap['payment_prefix']);
        }
        if (codeMap['return_prefix'] is String) {
          await CodeService.setReturnPrefix(codeMap['return_prefix']);
        }
        if (codeMap['digits'] is int) {
          await CodeService.setDigits(codeMap['digits'] as int);
        }
        if (codeMap['mode'] is String) {
          await CodeService.setMode(codeMap['mode']);
        }
        if (codeMap['enabled'] is bool) {
          await CodeService.setEnabled(codeMap['enabled'] as bool);
        }
      } catch (e) {
        debugPrint('⚠️ Import code settings: $e');
      }
    }
  }
}
