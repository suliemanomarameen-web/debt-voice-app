import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/pending_notification.dart';
import 'logger_service.dart';
import 'notification_service.dart';

/// خدمة إدارة الإشعارات المعلّقة
///
/// - إنشاء إشعارات في DB + شريط Android
/// - عرض الإشعارات بأزرار تفاعلية
/// - معالجة الإجراءات (حفظ/إلغاء/تمييز)
/// - إدارة المجموعات
/// - تطبيق الاحتفاظ
class PendingNotificationService {
  static final _db = DatabaseHelper.instance;

  static const String groupVoiceKey = 'debt_group_voice';
  static const String groupUnclearKey = 'debt_group_unclear';

  static final _pendingCountController = StreamController<int>.broadcast();
  static Stream<int> get pendingCountStream => _pendingCountController.stream;

  // ═══════════════════════════════════════════════════════════
  // إنشاء إشعار
  // ═══════════════════════════════════════════════════════════

  static Future<int> create(PendingNotification notif) async {
    final id = await _db.insertPendingNotification(notif.toMap());

    if (id <= 0) {
      debugPrint('❌ [PendingNotif] Failed to create');
      return 0;
    }

    final saved = notif.copyWith(id: id);

    await LoggerService.logVoiceNotificationCreated(
      notificationId: id,
      text: notif.text ?? '',
      matchType: notif.matchType,
      audioPath: notif.audioPath,
    );

    await _showAndroidNotification(saved);

    await _notifyPendingCount();

    return id;
  }

  // ═══════════════════════════════════════════════════════════
  // عرض إشعار على شريط Android
  // ═══════════════════════════════════════════════════════════

  static Future<void> _showAndroidNotification(
      PendingNotification n) async {
    if (n.id == null) return;

    final title = _buildTitle(n);
    final body = _buildBody(n);
    final actions = _buildActions(n);
    final groupKey = _groupKeyFor(n.matchType);
    final payload = _buildPayload(n.id!);

    if (actions.isEmpty) {
      await NotificationService.show(
        title,
        body,
        payload: payload,
        notificationId: n.id,
        groupKey: groupKey,
      );
    } else {
      await NotificationService.showWithActions(
        title: title,
        body: body,
        actions: actions,
        payload: payload,
        notificationId: n.id,
        groupKey: groupKey,
      );
    }
  }

  static String _buildTitle(PendingNotification n) {
    switch (n.matchType) {
      case 'single':
        return '🟢 ${n.summary}';
      case 'multiple':
        return '🟡 ${n.summary}';
      case 'unclear':
        return '⚪ تسجيل صوتي غير مفهوم';
      case 'no_account':
        return '🟠 ${n.summary}';
      default:
        return '🔔 إشعار';
    }
  }

  static String _buildBody(PendingNotification n) {
    switch (n.matchType) {
      case 'single':
        return 'حساب: ${n.matchedCustomerName ?? ""}\n'
            'اضغط [حفظ] للتأكيد أو [إلغاء] للتجاهل';
      case 'multiple':
        return 'يوجد ${n.candidates.length} حساب مطابق\n'
            'اضغط [حدد الحساب] للاختيار';
      case 'unclear':
        return (n.text ?? '').length > 100
            ? '${n.text!.substring(0, 100)}...'
            : (n.text ?? 'لم أفهم التسجيل');
      case 'no_account':
        return 'لا يوجد حساب باسم "${n.customerName ?? ""}"\n'
            'اضغط [إنشاء حساب] أو تجاهل';
      default:
        return '';
    }
  }

  static List<NotificationAction> _buildActions(PendingNotification n) {
    switch (n.matchType) {
      case 'single':
        return const [
          NotificationAction(id: 'save', title: '✓ حفظ'),
          NotificationAction(id: 'cancel', title: '✗ إلغاء'),
        ];
      case 'multiple':
        return const [
          NotificationAction(id: 'choose', title: 'حدد الحساب'),
          NotificationAction(id: 'cancel', title: '✗ إلغاء'),
        ];
      case 'unclear':
        return const [
          NotificationAction(id: 'dismiss', title: 'تمييز كمقروءة'),
        ];
      case 'no_account':
        return const [
          NotificationAction(id: 'create_account', title: 'إنشاء حساب'),
          NotificationAction(id: 'dismiss', title: 'تمييز كمقروءة'),
        ];
      default:
        return const [];
    }
  }

  static String _groupKeyFor(String matchType) {
    if (matchType == 'unclear' || matchType == 'no_account') {
      return groupUnclearKey;
    }
    return groupVoiceKey;
  }

  static String _buildPayload(int id) => 'voice_notif:$id';

  // ═══════════════════════════════════════════════════════════
  // الحصول على إشعار
  // ═══════════════════════════════════════════════════════════

  static Future<PendingNotification?> getById(int id) async {
    final row = await _db.getPendingNotification(id);
    if (row == null) return null;
    return PendingNotification.fromMap(row);
  }

  static Future<List<PendingNotification>> getAll({
    String? status,
    String? matchType,
    int? limit,
  }) async {
    final rows = await _db.getPendingNotifications(
      status: status,
      matchType: matchType,
      limit: limit,
    );
    return rows.map((r) => PendingNotification.fromMap(r)).toList();
  }

  static Future<List<PendingNotification>> getPending() async {
    return getAll(status: 'pending');
  }

  static Future<int> getPendingCount() async {
    final rows = await _db.getPendingNotifications(status: 'pending');
    return rows.length;
  }

  static Future<Map<String, int>> getStats() async {
    return _db.getNotificationsStats();
  }

  // ═══════════════════════════════════════════════════════════
  // إعادة العرض
  // ═══════════════════════════════════════════════════════════

  static Future<int> replayPending() async {
    try {
      final pending = await getPending();
      int replayed = 0;

      for (final n in pending) {
        if (n.id == null) continue;
        await _showAndroidNotification(n);
        replayed++;
      }

      if (replayed > 0) {
        debugPrint('🔔 [PendingNotif] Replayed $replayed notifications');
      }
      return replayed;
    } catch (e) {
      debugPrint('❌ [PendingNotif] replayPending: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // حل إشعار
  // ═══════════════════════════════════════════════════════════

  static Future<bool> markSaved(int id) async {
    await _db.markNotificationSaved(id);
    await _cancelNotification(id);
    await _notifyPendingCount();
    return true;
  }

  static Future<bool> markCancelled(int id) async {
    final n = await getById(id);
    await _db.markNotificationCancelled(id);
    await _cancelNotification(id);
    await LoggerService.logVoiceNotificationCancelled(
      notificationId: id,
      text: n?.text ?? '',
    );
    await _notifyPendingCount();
    return true;
  }

  static Future<bool> markDismissed(int id) async {
    final n = await getById(id);
    await _db.markNotificationDismissed(id);
    await _cancelNotification(id);
    await LoggerService.logVoiceNotificationDismissed(
      notificationId: id,
      text: n?.text ?? '',
    );
    await _notifyPendingCount();
    return true;
  }

  static Future<bool> markExpired(int id) async {
    final n = await getById(id);
    await _db.markNotificationExpired(id);
    await _cancelNotification(id);
    await LoggerService.logVoiceNotificationExpired(
      notificationId: id,
      text: n?.text ?? '',
    );
    await _notifyPendingCount();
    return true;
  }

  static Future<void> _cancelNotification(int id) async {
    try {
      await NotificationService.cancel(id);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════
  // حذف يدوي
  // ═══════════════════════════════════════════════════════════

  static Future<bool> delete(int id) async {
    final n = await getById(id);
    if (n == null) return false;

    await _db.deletePendingNotification(id);
    await _cancelNotification(id);

    await LoggerService.logVoiceNotificationDeleted(
      notificationId: id,
      text: n.text ?? '',
      previousStatus: n.status,
    );

    await _notifyPendingCount();
    return true;
  }

  // ═══════════════════════════════════════════════════════════
  // الانتهاء التلقائي
  // ═══════════════════════════════════════════════════════════

  static Future<int> expireOldNotifications() async {
    try {
      final expired = await _db.getExpiredUnclear();

      for (final row in expired) {
        final id = row['id'] as int?;
        if (id == null) continue;
        await markExpired(id);
      }

      return expired.length;
    } catch (e) {
      debugPrint('❌ [PendingNotif] expireOld: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الاحتفاظ
  // ═══════════════════════════════════════════════════════════

  static Future<int> applyRetention() async {
    final deleted = await _db.applyNotificationsRetention();
    if (deleted > 0) {
      await _notifyPendingCount();
    }
    return deleted;
  }

  // ═══════════════════════════════════════════════════════════
  // ملخص المجموعة
  // ═══════════════════════════════════════════════════════════

  static Future<void> updateGroupSummaries() async {
    try {
      final pending = await getPending();

      final voicePending =
          pending.where((n) => n.isSingle || n.isMultiple).toList();
      if (voicePending.isNotEmpty) {
        await NotificationService.showGroupSummary(
          groupKey: groupVoiceKey,
          title: '🎤 ${voicePending.length} تسجيل صوتي',
          body: 'اضغط للفتح',
          payload: 'open_notifications',
        );
      }

      final unclearPending = pending
          .where((n) => n.isUnclear || n.isNoAccount)
          .toList();
      if (unclearPending.isNotEmpty) {
        await NotificationService.showGroupSummary(
          groupKey: groupUnclearKey,
          title: '⚪ ${unclearPending.length} تسجيل غير مفهوم',
          body: 'اضغط للفتح',
          payload: 'open_notifications',
        );
      }
    } catch (e) {
      debugPrint('❌ [PendingNotif] updateGroupSummaries: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // عدّاد pending
  // ═══════════════════════════════════════════════════════════

  static Future<void> _notifyPendingCount() async {
    try {
      final count = await getPendingCount();
      if (!_pendingCountController.isClosed) {
        _pendingCountController.add(count);
      }
    } catch (_) {}
  }

  static Future<void> refreshPendingCount() async {
    await _notifyPendingCount();
  }
}

// Pending Notification Service v1: إدارة كاملة لدورة حياة إشعارات الصوت
