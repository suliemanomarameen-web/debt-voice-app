import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'accountant_service.dart';
import 'code_service.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'pending_notification_service.dart';

/// معالج الإجراءات على الإشعارات
///
/// - يُستدعى من `NotificationService.onAction` عند الضغط على زر
/// - يُستدعى من `NotificationService.onTap` عند فتح الإشعار
class NotificationActionHandler {
  static final _db = DatabaseHelper.instance;

  /// يُستدعى من main.dart عند ضغط زر في الإشعار
  static Future<void> handleAction(String actionId, String? payload) async {
    if (payload == null || payload.isEmpty) return;

    final notificationId = _parseId(payload);
    if (notificationId == null) return;

    debugPrint(
        '🔔 [ActionHandler] Action=$actionId, notificationId=$notificationId');

    switch (actionId) {
      case 'save':
        await _handleSave(notificationId);
        break;
      case 'cancel':
        await _handleCancel(notificationId);
        break;
      case 'choose':
        await _handleChoose(notificationId);
        break;
      case 'dismiss':
        await _handleDismiss(notificationId);
        break;
      case 'create_account':
        await _handleCreateAccount(notificationId);
        break;
      default:
        debugPrint('⚠️ [ActionHandler] Unknown action: $actionId');
    }
  }

  /// يُستدعى عند الضغط على الإشعار نفسه (فتح التطبيق)
  static Future<void> handleTap(String? payload) async {
    if (payload == null || payload.isEmpty) return;

    if (payload == 'open_notifications') {
      debugPrint('🔔 [ActionHandler] open_notifications');
      return;
    }

    final notificationId = _parseId(payload);
    if (notificationId == null) return;

    debugPrint('🔔 [ActionHandler] Tap on notification #$notificationId');
  }

  // ═══════════════════════════════════════════════════════════
  // حفظ (single)
  // ═══════════════════════════════════════════════════════════

  static Future<void> _handleSave(int notificationId) async {
    try {
      final n = await PendingNotificationService.getById(notificationId);
      if (n == null) return;
      if (!n.isSingle) {
        debugPrint('⚠️ Cannot save: not single');
        return;
      }
      if (n.matchedCustomerId == null || n.intent == null) return;

      final customer = await _db.getCustomer(n.matchedCustomerId!);
      if (customer == null) {
        debugPrint('⚠️ Customer not found');
        await PendingNotificationService.markCancelled(notificationId);
        return;
      }

      final accountant = await AccountantService.getAccountantName();
      final normalizedType = CodeService.normalizeType(n.intent!);
      final storedType =
          (normalizedType == 'return') ? 'payment' : normalizedType;

      String? code;
      try {
        code = await CodeService.generateCode(normalizedType);
      } catch (_) {}

      final txId = await _db.insertTransaction(Transaction(
        customerId: customer.id!,
        code: code,
        accountant: accountant,
        source: 'notification',
        amount: n.amount ?? 0,
        currency: n.currency,
        type: storedType,
        items: normalizedType == 'return'
            ? 'مرتجع${(n.items ?? "").isEmpty ? "" : ": ${n.items}"}'
            : (n.items ?? ''),
        createdAt: DateTime.now().toIso8601String(),
      ));

      final typeLabel = {
        'debt': 'دين',
        'payment': 'سداد',
        'return': 'مرتجع',
      }[normalizedType] ?? 'عملية';

      await LoggerService.logTransactionAdded(
        typeLabel: typeLabel,
        customerName: customer.name,
        amount: n.amount ?? 0,
        currency: n.currency,
        code: code,
        accountant: accountant,
        source: 'notification',
      );

      await LoggerService.logVoiceNotificationSaved(
        notificationId: notificationId,
        typeLabel: typeLabel,
        customerName: customer.name,
        amount: n.amount ?? 0,
        currency: n.currency,
        transactionId: txId,
        accountant: accountant,
      );

      await PendingNotificationService.markSaved(notificationId);

      await NotificationService.show(
        '✅ تم الحفظ',
        '$typeLabel ${(n.amount ?? 0).toStringAsFixed(0)} ${n.currency} — ${customer.name}',
      );

      await PendingNotificationService.updateGroupSummaries();
    } catch (e) {
      debugPrint('❌ [ActionHandler] save: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // إلغاء
  // ═══════════════════════════════════════════════════════════

  static Future<void> _handleCancel(int notificationId) async {
    await PendingNotificationService.markCancelled(notificationId);
    await PendingNotificationService.updateGroupSummaries();
  }

  // ═══════════════════════════════════════════════════════════
  // حدد الحساب (multiple)
  // ═══════════════════════════════════════════════════════════

  static Future<void> _handleChoose(int notificationId) async {
    debugPrint(
        '🔔 [ActionHandler] choose → will open CustomerPicker for #$notificationId');
  }

  // ═══════════════════════════════════════════════════════════
  // تمييز كمقروءة
  // ═══════════════════════════════════════════════════════════

  static Future<void> _handleDismiss(int notificationId) async {
    await PendingNotificationService.markDismissed(notificationId);
    await PendingNotificationService.updateGroupSummaries();
  }

  // ═══════════════════════════════════════════════════════════
  // إنشاء حساب (no_account)
  // ═══════════════════════════════════════════════════════════

  static Future<void> _handleCreateAccount(int notificationId) async {
    debugPrint(
        '🔔 [ActionHandler] create_account → will open AddAccount for #$notificationId');
  }

  // ═══════════════════════════════════════════════════════════
  // helpers
  // ═══════════════════════════════════════════════════════════

  static int? _parseId(String payload) {
    try {
      if (payload.startsWith('voice_notif:')) {
        return int.tryParse(payload.substring('voice_notif:'.length));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

// Notification Action Handler v1: معالجة أزرار الإشعارات (save/cancel/choose/dismiss/create_account)
