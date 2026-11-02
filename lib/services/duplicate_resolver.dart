import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import '../models/log_event.dart';

/// مُحلّل التكرارات — ينفّذ قرارات المستخدم
///
/// - **merge**: يبقي حساباً/عملية واحدة + يحذف الأخرى
/// - **rename**: يعيد تسمية السحابي ليكون فريداً
/// - **skip**: يؤجل القرار (يبقى التكرار نشطاً)
class DuplicateResolver {
  // ═══════════════════════════════════════════════════════════
  // دمج العملاء
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> mergeCustomer({
    required int duplicateId,
    required String keepWhich, // 'local' | 'cloud'
    String? by,
  }) async {
    final db = DatabaseHelper.instance;

    try {
      final dup = await db.getDuplicateByIdRaw(duplicateId);
      if (dup == null) {
        return {'success': false, 'message': 'التكرار غير موجود'};
      }
      if (dup['status'] == 'resolved') {
        return {'success': false, 'message': 'تم حل هذا التكرار مسبقاً'};
      }

      final localCloudId = dup['local_cloud_id'] as String;
      final cloudCloudId = dup['cloud_cloud_id'] as String;
      final metadata = _decodeMetadata(dup['metadata']);
      final cloudRecord =
          metadata?['cloud_record'] as Map<String, dynamic>?;
      final localName = (metadata?['local_name'] as String?) ?? '';
      final cloudName = (metadata?['cloud_name'] as String?) ?? '';

      // البحث عن السجل المحلي
      final localRows = await (await db.database).query(
        'customers',
        where: 'cloud_id = ?',
        whereArgs: [localCloudId],
        limit: 1,
      );
      if (localRows.isEmpty) {
        await db.markDuplicateResolved(duplicateId, 'merge', by: by);
        return {
          'success': true,
          'message': 'تم إغلاق التكرار (السجل المحلي مفقود)',
        };
      }
      final localId = localRows.first['id'] as int;

      if (keepWhich == 'local') {
        // الاحتفاظ بالمحلي: نضع tombstone للسحابي
        await db.addTombstone(cloudId: cloudCloudId, type: 'customer');
        await db.markDuplicateResolved(duplicateId, 'merge', by: by);

        await _afterResolve(
          action: 'merge',
          itemType: 'customer',
          keptName: localName,
          removedName: cloudName,
          by: by,
        );

        return {
          'success': true,
          'message': 'تم الاحتفاظ بالنسخة المحلية "$localName"',
        };
      }

      // الاحتفاظ بالسحابي
      if (cloudRecord == null) {
        return {'success': false, 'message': 'بيانات السحابة مفقودة'};
      }

      // 1. إدراج السجل السحابي إذا لم يكن موجوداً
      final existingCloudRows = await (await db.database).query(
        'customers',
        where: 'cloud_id = ?',
        whereArgs: [cloudCloudId],
        limit: 1,
      );
      int cloudLocalId;
      if (existingCloudRows.isEmpty) {
        final newMap = Map<String, dynamic>.from(cloudRecord);
        newMap.remove('id');
        newMap['cloud_id'] = cloudCloudId;
        // تأكد من عدم كونه محذوفاً
        newMap['is_deleted'] = 0;
        newMap['is_permanently_deleted'] = 0;
        newMap['deleted_at'] = null;
        newMap['deleted_by'] = null;
        cloudLocalId = await db.insertCustomerRaw(newMap);
      } else {
        cloudLocalId = existingCloudRows.first['id'] as int;
      }

      // 2. نقل معاملات المحلي إلى السحابي
      final now = DateTime.now().toIso8601String();
      await (await db.database).update(
        'transactions',
        {
          'customer_id': cloudLocalId,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
        where: 'customer_id = ?',
        whereArgs: [localId],
      );

      // 3. وسم المحلي كـ محذوف نهائياً
      await (await db.database).update(
        'customers',
        {
          'is_deleted': 1,
          'is_permanently_deleted': 1,
          'deleted_at': now,
          'deleted_by': by,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      // 4. tombstone للسجل المحلي
      await db.addTombstone(cloudId: localCloudId, type: 'customer');

      // 5. حلّ التكرار
      await db.markDuplicateResolved(duplicateId, 'merge', by: by);

      await _afterResolve(
        action: 'merge',
        itemType: 'customer',
        keptName: cloudName,
        removedName: localName,
        by: by,
      );

      return {
        'success': true,
        'message': 'تم الدمج بنجاح — الاحتفاظ بـ "$cloudName"',
      };
    } catch (e) {
      debugPrint('❌ [Resolver] mergeCustomer: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // دمج العمليات
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> mergeTransaction({
    required int duplicateId,
    required String keepWhich, // 'local' | 'cloud'
    String? by,
  }) async {
    final db = DatabaseHelper.instance;

    try {
      final dup = await db.getDuplicateByIdRaw(duplicateId);
      if (dup == null) {
        return {'success': false, 'message': 'التكرار غير موجود'};
      }
      if (dup['status'] == 'resolved') {
        return {'success': false, 'message': 'تم حل هذا التكرار مسبقاً'};
      }

      final localCloudId = dup['local_cloud_id'] as String;
      final cloudCloudId = dup['cloud_cloud_id'] as String;
      final metadata = _decodeMetadata(dup['metadata']);
      final cloudRecord =
          metadata?['cloud_record'] as Map<String, dynamic>?;
      final code = (metadata?['code'] as String?) ?? '';

      final localRows = await (await db.database).query(
        'transactions',
        where: 'cloud_id = ?',
        whereArgs: [localCloudId],
        limit: 1,
      );
      if (localRows.isEmpty) {
        await db.markDuplicateResolved(duplicateId, 'merge', by: by);
        return {
          'success': true,
          'message': 'تم إغلاق التكرار (السجل المحلي مفقود)',
        };
      }
      final localId = localRows.first['id'] as int;

      final now = DateTime.now().toIso8601String();

      if (keepWhich == 'local') {
        // الاحتفاظ بالمحلي: tombstone للسحابي
        await db.addTombstone(cloudId: cloudCloudId, type: 'transaction');
        await db.markDuplicateResolved(duplicateId, 'merge', by: by);

        await _afterResolve(
          action: 'merge',
          itemType: 'transaction',
          keptName: code,
          removedName: code,
          by: by,
        );

        return {
          'success': true,
          'message': 'تم الاحتفاظ بالعملية المحلية ($code)',
        };
      }

      // الاحتفاظ بالسحابي
      if (cloudRecord == null) {
        return {'success': false, 'message': 'بيانات السحابة مفقودة'};
      }

      // إدراج السحابي إذا لم يكن موجوداً
      final existingCloudRows = await (await db.database).query(
        'transactions',
        where: 'cloud_id = ?',
        whereArgs: [cloudCloudId],
        limit: 1,
      );
      if (existingCloudRows.isEmpty) {
        final newMap = Map<String, dynamic>.from(cloudRecord);
        newMap.remove('id');
        newMap['cloud_id'] = cloudCloudId;
        newMap['is_deleted'] = 0;
        newMap['deleted_at'] = null;
        newMap['deleted_by'] = null;
        await db.insertTransactionRaw(newMap);
      }

      // وسم المحلي كـ محذوف نهائياً (بدون عمود is_permanently_deleted للمعاملات، نستخدم is_deleted فقط)
      await (await db.database).update(
        'transactions',
        {
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': by,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      // tombstone للمحلي
      await db.addTombstone(cloudId: localCloudId, type: 'transaction');

      await db.markDuplicateResolved(duplicateId, 'merge', by: by);

      await _afterResolve(
        action: 'merge',
        itemType: 'transaction',
        keptName: code,
        removedName: code,
        by: by,
      );

      return {
        'success': true,
        'message': 'تم الدمج بنجاح — الاحتفاظ بالعملية السحابية ($code)',
      };
    } catch (e) {
      debugPrint('❌ [Resolver] mergeTransaction: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إعادة التسمية
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> renameCustomer({
    required int duplicateId,
    required String newName,
    String? by,
  }) async {
    final db = DatabaseHelper.instance;

    try {
      final dup = await db.getDuplicateByIdRaw(duplicateId);
      if (dup == null) {
        return {'success': false, 'message': 'التكرار غير موجود'};
      }
      if (dup['status'] == 'resolved') {
        return {'success': false, 'message': 'تم حل هذا التكرار مسبقاً'};
      }

      final trimmed = newName.trim();
      if (trimmed.isEmpty) {
        return {'success': false, 'message': 'الاسم فارغ'};
      }

      final cloudCloudId = dup['cloud_cloud_id'] as String;
      final metadata = _decodeMetadata(dup['metadata']);
      final cloudRecord =
          metadata?['cloud_record'] as Map<String, dynamic>?;
      final oldName = (metadata?['cloud_name'] as String?) ?? '';

      if (cloudRecord == null) {
        return {'success': false, 'message': 'بيانات السحابة مفقودة'};
      }

      // التحقق من عدم تكرار الاسم
      final existing = await db.findExactCustomer(trimmed);
      if (existing != null && existing.cloudId != cloudCloudId) {
        return {
          'success': false,
          'message': 'اسم "$trimmed" مستخدم بالفعل',
        };
      }

      // إدراج السجل السحابي إذا لم يكن موجوداً
      final existingCloudRows = await (await db.database).query(
        'customers',
        where: 'cloud_id = ?',
        whereArgs: [cloudCloudId],
        limit: 1,
      );
      int cloudLocalId;
      if (existingCloudRows.isEmpty) {
        final newMap = Map<String, dynamic>.from(cloudRecord);
        newMap.remove('id');
        newMap['cloud_id'] = cloudCloudId;
        newMap['is_deleted'] = 0;
        newMap['is_permanently_deleted'] = 0;
        newMap['deleted_at'] = null;
        newMap['deleted_by'] = null;
        cloudLocalId = await db.insertCustomerRaw(newMap);
      } else {
        cloudLocalId = existingCloudRows.first['id'] as int;
      }

      // إعادة التسمية
      final now = DateTime.now().toIso8601String();
      await db.updateCustomerFields(
        cloudLocalId,
        {
          'name': trimmed,
          'updated_at': now,
          if (by != null && by.isNotEmpty) 'updated_by': by,
        },
      );

      await db.markDuplicateResolved(duplicateId, 'rename', by: by);

      await _afterResolve(
        action: 'rename',
        itemType: 'customer',
        keptName: trimmed,
        removedName: oldName,
        by: by,
      );

      return {
        'success': true,
        'message': 'تمت إعادة التسمية: "$oldName" → "$trimmed"',
      };
    } catch (e) {
      debugPrint('❌ [Resolver] renameCustomer: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التخطي
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> skip({
    required int duplicateId,
    String? by,
  }) async {
    final db = DatabaseHelper.instance;

    try {
      final dup = await db.getDuplicateByIdRaw(duplicateId);
      if (dup == null) {
        return {'success': false, 'message': 'التكرار غير موجود'};
      }
      if (dup['status'] == 'resolved') {
        return {'success': false, 'message': 'تم حل هذا التكرار مسبقاً'};
      }

      final metadata = _decodeMetadata(dup['metadata']);
      final type = dup['type'] as String? ?? 'customer';
      final name = (metadata?['local_name'] as String?) ??
          (metadata?['code'] as String?) ??
          '';

      await db.markDuplicateSkipped(duplicateId, by: by);

      await _afterResolve(
        action: 'skip',
        itemType: type,
        keptName: name,
        removedName: '',
        by: by,
      );

      return {
        'success': true,
        'message': 'تم تأجيل التكرار — سيظهر في المزامنة القادمة',
      };
    } catch (e) {
      debugPrint('❌ [Resolver] skip: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // حلّ الكل
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> resolveAll({
    required String action, // 'merge' | 'rename' | 'skip'
    String keepWhich = 'cloud', // 'local' | 'cloud'
    String? by,
  }) async {
    final db = DatabaseHelper.instance;

    try {
      final all = await db.getUnresolvedDuplicatesRaw();
      int resolved = 0;
      int failed = 0;

      for (final row in all) {
        final dupId = row['id'] as int?;
        if (dupId == null) continue;
        final type = row['type'] as String? ?? 'customer';

        Map<String, dynamic> result;
        if (action == 'skip') {
          result = await skip(duplicateId: dupId, by: by);
        } else if (action == 'merge') {
          result = type == 'customer'
              ? await mergeCustomer(
                  duplicateId: dupId, keepWhich: keepWhich, by: by)
              : await mergeTransaction(
                  duplicateId: dupId, keepWhich: keepWhich, by: by);
        } else if (action == 'rename') {
          if (type == 'customer') {
            final suggested = await _findAvailableName(
              (row['metadata'] != null)
                  ? (_decodeMetadata(row['metadata'])?['cloud_name']
                          as String? ??
                      '')
                  : '',
            );
            result = await renameCustomer(
              duplicateId: dupId,
              newName: suggested,
              by: by,
            );
          } else {
            // لا إعادة تسمية للعمليات
            result = await skip(duplicateId: dupId, by: by);
          }
        } else {
          result = {'success': false};
        }

        if (result['success'] == true) {
          resolved++;
        } else {
          failed++;
        }
      }

      return {
        'success': true,
        'resolved': resolved,
        'failed': failed,
        'message': 'تم حل $resolved، فشل $failed',
      };
    } catch (e) {
      debugPrint('❌ [Resolver] resolveAll: $e');
      return {'success': false, 'message': 'خطأ: $e'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════

  /// يبحث عن أول اسم متاح: "أحمد (2)", "أحمد (3)", ...
  static Future<String> findAvailableName(String baseName) async {
    return _findAvailableName(baseName);
  }

  static Future<String> _findAvailableName(String baseName) async {
    final db = DatabaseHelper.instance;
    final clean = baseName.trim();
    if (clean.isEmpty) return 'مكرر';

    final format = SettingsService.getString(
      AppSettings.autoRenameFormat,
      defaultValue: '(2)',
    );

    // هل الاسم الأصلي مستخدم في نسخة أخرى؟ نبدأ من (2)
    for (int i = 2; i <= 999; i++) {
      final candidate = _applyRenameFormat(clean, i, format);
      final existing = await db.findExactCustomer(candidate);
      if (existing == null) return candidate;
    }

    return '$clean (${DateTime.now().millisecondsSinceEpoch})';
  }

  static String _applyRenameFormat(
      String base, int index, String format) {
    switch (format) {
      case '-2':
        return '$base-$index';
      case '_2':
        return '${base}_$index';
      case '(2)':
      default:
        return '$base ($index)';
    }
  }

  static Map<String, dynamic>? _decodeMetadata(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// بعد الحل: إشعار + سجل
  static Future<void> _afterResolve({
    required String action, // 'merge' | 'rename' | 'skip'
    required String itemType, // 'customer' | 'transaction'
    required String keptName,
    required String removedName,
    String? by,
  }) async {
    try {
      // هل يجب إظهار إشعار محلي؟
      bool shouldNotify = false;
      if (action == 'merge') {
        shouldNotify = SettingsService.getBool(
            AppSettings.notifyOnMerge, defaultValue: true);
      } else if (action == 'rename') {
        shouldNotify = SettingsService.getBool(
            AppSettings.notifyOnRename, defaultValue: true);
      } else if (action == 'skip') {
        shouldNotify = SettingsService.getBool(
            AppSettings.notifyOnSkip, defaultValue: false);
      }

      final String typeLabel =
          itemType == 'customer' ? 'حساب' : 'عملية';

      final String title;
      final String body;

      switch (action) {
        case 'merge':
          title = '🔀 دمج $typeLabel';
          body = itemType == 'customer'
              ? 'تم دمج "$removedName" مع "$keptName"\nبواسطة: ${by ?? "محاسب"}'
              : 'تم دمج العملية ($keptName)\nبواسطة: ${by ?? "محاسب"}';
          break;
        case 'rename':
          title = '✏️ إعادة تسمية $typeLabel';
          body = 'تمت إعادة تسمية "$removedName" إلى "$keptName"\nبواسطة: ${by ?? "محاسب"}';
          break;
        case 'skip':
          title = '⏸️ تأجيل $typeLabel';
          body = 'تم تأجيل "$keptName"\nبواسطة: ${by ?? "محاسب"}';
          break;
        default:
          title = 'تكرار';
          body = '$typeLabel: $keptName';
      }

      if (shouldNotify) {
        try {
          await NotificationService.show(title, body);
        } catch (_) {}
      }

      // سجل الأحداث (يُزامَن)
      await LoggerService.log(
        action: title,
        description: body,
        level: action == 'skip' ? LogLevel.info : LogLevel.success,
        category: LogCategory.sync,
        accountant: by,
        needsAck: action != 'skip',
        metadata: {
          'type': itemType,
          'action': action,
          'kept_name': keptName,
          'removed_name': removedName,
        },
      );
    } catch (e) {
      debugPrint('⚠️ [Resolver] _afterResolve: $e');
    }
  }
}

// Duplicate Resolver v1: منطق الدمج وإعادة التسمية والتخطي (المرحلة 4)
