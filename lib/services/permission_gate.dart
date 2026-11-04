import 'package:flutter/material.dart';
import 'accountants_service.dart';
import 'device_service.dart';

/// ═══════════════════════════════════════════════════════════
/// بوابة الصلاحيات — تُطبَّق على كل إجراء حساس
///
/// المبدأ:
/// - المحاسب الأساسي (isPrimary) له كل الصلاحيات تلقائيًا
/// - المحاسب الثانوي يعتمد على صلاحياته المعيّنة من الأساسي
/// - الفحص في طبقتين:
///   1. الواجهة: إخفاء الأزرار (PermissionGateWidget)
///   2. الدالة: رفض التنفيذ (PermissionGate.check)
///
/// هذا يُوفّر الحماية حتى لو تلاعب المستخدم بالواجهة.
/// ═══════════════════════════════════════════════════════════
class PermissionGate {
  /// فحص صلاحية واحدة — بدون واجهة
  ///
  /// يُستخدم داخل الدوال قبل تنفيذ أي إجراء حساس.
  static Future<bool> check(String permission) async {
    try {
      // 👑 الأساسي له كل الصلاحيات دائمًا
      if (await DeviceService.isPrimaryDevice()) return true;

      // تحقق من صلاحيات المحاسب الحالي
      return await AccountantsService.hasPermission(permission);
    } catch (_) {
      // عند أي خطأ → ارفض (fail-safe)
      return false;
    }
  }

  /// فحص + عرض رسالة عند الرفض
  ///
  /// يُستخدم في بداية كل دالة يمكن للمستخدم استدعاؤها.
  static Future<bool> require(
    BuildContext context,
    String permission, {
    String? message,
  }) async {
    if (await check(permission)) return true;

    if (context.mounted) {
      _showDenied(context, message);
    }
    return false;
  }

  /// فحص + حوار تأكيد قبل الإجراءات الخطيرة
  ///
  /// يُستخدم للحذف النهائي، أو أي إجراء لا رجعة فيه.
  static Future<bool> requireWithConfirm(
    BuildContext context,
    String permission, {
    String? denyMessage,
    required String confirmTitle,
    required String confirmMessage,
    String confirmText = 'متابعة',
    String cancelText = 'إلغاء',
    Color? confirmColor,
  }) async {
    if (!await check(permission)) {
      if (context.mounted) _showDenied(context, denyMessage);
      return false;
    }

    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelText),
            ),
            FilledButton(
              style: confirmColor != null
                  ? FilledButton.styleFrom(backgroundColor: confirmColor)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmText),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  /// عرض رسالة الرفض
  static void _showDenied(BuildContext context, String? customMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                customMessage ?? 'ليس لديك صلاحية لهذا الإجراء',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════
/// Widget يخفي محتواه إذا لم تكن الصلاحية متاحة
///
/// الاستخدام:
/// ```dart
/// PermissionGateWidget(
///   permission: 'delete_customers',
///   child: IconButton(
///     icon: Icon(Icons.delete, color: Colors.red),
///     onPressed: () => _delete(),
///   ),
/// )
/// ```
/// ═══════════════════════════════════════════════════════════
class PermissionGateWidget extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;
  final bool showLoading;

  const PermissionGateWidget({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PermissionGate.check(permission),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return showLoading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox.shrink();
        }
        if (snap.data == true) return child;
        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}

/// ═══════════════════════════════════════════════════════════
/// Cache للصلاحيات — يُستخدم في القوائم الطويلة
///
/// بدلًا من FutureBuilder لكل صف (يسبب تأخيرًا)، نُحمّل كل
/// الصلاحيات مرة واحدة عند الدخول للشاشة ونستخدمها مباشرة.
///
/// يجب استدعاء refresh() في initState للشاشة.
/// ═══════════════════════════════════════════════════════════
class PermissionCache {
  static Map<String, bool> _cache = {};
  static String? _cachedDeviceId;
  static bool _isPrimary = false;

  /// كل الصلاحيات المعرّفة
  static const List<String> _allPermissions = [
    'add_customers',
    'edit_customers',
    'delete_customers',
    'toggle_customer_active',
    'edit_max_balance',
    'add_transactions',
    'edit_transactions',
    'delete_transactions',
    'view_all_transactions',
    'view_stats',
    'export_data',
    'view_logs',
    'access_advanced_settings',
    'manage_backups',
    'manage_accountants',
    'can_become_primary',
  ];

  /// تحديث الـ cache — استدعِ هذا في initState
  static Future<void> refresh() async {
    try {
      _cachedDeviceId = await DeviceService.getDeviceId();

      if (await DeviceService.isPrimaryDevice()) {
        _isPrimary = true;
        _cache = {for (final key in _allPermissions) key: true};
        return;
      }

      _isPrimary = false;
      final current = await AccountantsService.getCurrentAccountant();
      if (current == null) {
        _cache = {};
        return;
      }
      _cache = Map<String, bool>.from(current.permissions);
    } catch (_) {
      _isPrimary = false;
      _cache = {};
    }
  }

  /// فحص سريع من الذاكرة — بدون async
  static bool has(String permission) {
    if (_isPrimary) return true;
    return _cache[permission] == true;
  }

  /// هل المستخدم أساسي؟
  static bool get isPrimary => _isPrimary;

  /// هل يجب تجديد الـ cache؟
  static Future<bool> needsRefresh() async {
    try {
      final currentDeviceId = await DeviceService.getDeviceId();
      return _cachedDeviceId != currentDeviceId || _cache.isEmpty;
    } catch (_) {
      return true;
    }
  }

  /// مسح الـ cache — استدعِ هذا بعد تغيير المحاسب/الصلاحيات
  static void clear() {
    _cache = {};
    _cachedDeviceId = null;
    _isPrimary = false;
  }
}

// ═══════════════════════════════════════════════════════════
// بوابة الصلاحيات v1 — ملف جديد
// - PermissionGate:     فحص (check / require / requireWithConfirm)
// - PermissionGateWidget: إخفاء عناصر الواجهة حسب الصلاحية
// - PermissionCache:    تحميل مسبق للصلاحيات لتسريع القوائم
//
// الهدف: إغلاق ثغرة الصلاحيات الشكلية في accountants_service
// حيث كانت 16 صلاحية معرّفة و1 فقط مستخدمة فعليًا.
// ═══════════════════════════════════════════════════════════
