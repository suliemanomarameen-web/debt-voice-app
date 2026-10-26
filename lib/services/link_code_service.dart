import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'crypto_service.dart';
import 'device_service.dart';

/// رمز الربط: يسمح للمحاسب الثاني بفك تشفير ملف الأساسي
///
/// الصيغة: LK1-<base64_salt>-<primary_short>
/// مثال: LK1-aBcDeFgHiJkLmNoPqRsT-abc12345
///
/// - base64_salt: الـ salt الخاص بالأساسي (16 بايت = 22 حرف base64)
/// - primary_short: أول 8 أحرف من primary_device_id (للتحقق)
class ParsedLinkCode {
  final String saltBase64;
  final String primaryShort;

  ParsedLinkCode({
    required this.saltBase64,
    required this.primaryShort,
  });
}

class LinkCodeService {
  static const String _prefix = 'LK1';

  /// توليد رمز ربط من الـ salt الحالي + primary device
  static Future<String> generate() async {
    final saltB64 = await CryptoService.getSaltBase64();
    if (saltB64 == null || saltB64.isEmpty) {
      throw Exception(
        'التشفير غير مفعل — لا يمكن توليد رمز ربط.\n'
        'فعّل التشفير أولاً من قسم 🔐 تشفير المزامنة.',
      );
    }

    final primaryId = await DeviceService.getPrimaryDeviceId();
    if (primaryId == null || primaryId.isEmpty) {
      throw Exception(
        'لم يتم تعيين هذا الجهاز كأساسي بعد.\n'
        'عيّن نفسك كمحاسب أساسي أولاً.',
      );
    }

    final primaryShort = primaryId.length >= 8
        ? primaryId.substring(0, 8)
        : primaryId;

    // إزالة padding من base64 لتقصير الرمز
    final saltClean = saltB64.replaceAll('=', '');

    return '$_prefix-$saltClean-$primaryShort';
  }

  /// تحليل رمز الربط
  static ParsedLinkCode? parse(String raw) {
    try {
      final cleaned = raw.trim();
      if (cleaned.isEmpty) return null;

      final parts = cleaned.split('-');
      // المتوقع: [LK1, salt, primaryShort] = 3 أجزاء
      // لكن salt قد يحتوي على '-' في base64 URL-safe؟ لا، base64 القياسي
      // لذا نتحقق من الأجزاء بعناية
      if (parts.length < 3) return null;
      if (parts[0] != _prefix) return null;

      // آخر جزء هو primaryShort (8 أحرف)
      final primaryShort = parts.last;
      if (primaryShort.length != 8) return null;

      // الجزء الأوسط: كل ما بين الأول والأخير (قد يكون جزءاً واحداً)
      final saltParts = parts.sublist(1, parts.length - 1);
      final saltClean = saltParts.join('');

      if (saltClean.isEmpty) return null;

      // إعادة padding لـ base64
      final padded = _padBase64(saltClean);

      // التحقق من صحة base64
      try {
        base64Decode(padded);
      } catch (_) {
        return null;
      }

      return ParsedLinkCode(
        saltBase64: padded,
        primaryShort: primaryShort,
      );
    } catch (e) {
      debugPrint('❌ parse link code: $e');
      return null;
    }
  }

  /// إعادة padding لـ base64 (المضاعفات 4)
  static String _padBase64(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    if (mod == 2) return '$s==';
    if (mod == 3) return '$s=';
    return s; // mod == 1 (غير صالح لكن نتركه للتحقق)
  }

  /// تحقق من أن رمز الربط ينتمي لملف الأساسي
  static bool matchesPrimaryDevice(
    ParsedLinkCode code,
    String? primaryDeviceId,
  ) {
    if (primaryDeviceId == null || primaryDeviceId.isEmpty) return false;
    final expected =
        primaryDeviceId.length >= 8
            ? primaryDeviceId.substring(0, 8)
            : primaryDeviceId;
    return code.primaryShort == expected;
  }
}
