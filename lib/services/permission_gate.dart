import 'package:flutter/material.dart';
import 'accountants_service.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'settings_service.dart';
import '../config/app_settings.dart';

/// بوابة الصلاحيات — تُطبَّق على كل إجراء حساس
class PermissionGate {
  static Future<bool> check(String permission) async {
    try {
      if (await DeviceService.isPrimaryDevice()) return true;
      return await AccountantsService.hasPermission(permission);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> require(
    BuildContext context,
    String permission, {
    String? message,
  }) async {
    if (await check(permission)) return true;
    if (context.mounted) _showDenied(context, message);
    return false;
  }

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

  /// 🆕 طلب كلمة المرور — يتخطى تلقائيًا إذا القفل معطل
  static Future<bool> requirePassword(
    BuildContext context, {
    String? title,
    String? message,
  }) async {
    try {
      final enabled = await AuthService.isEnabled();
      if (!enabled) return true;

      final hasPwd = await AuthService.hasPassword();
      if (!hasPwd) return true;

      if (!context.mounted) return false;

      final ctrl = TextEditingController();
      String? error;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (ctx, setSt) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(title ?? 'تأكيد الهوية'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message ?? 'أدخل كلمة المرور للمتابعة',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      border: const OutlineInputBorder(),
                      errorText: error,
                      prefixIcon: const Icon(Icons.lock),
                    ),
                    onSubmitted: (v) async {
                      final ok = await AuthService.verifyPassword(v.trim());
                      if (ok) {
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } else {
                        setSt(() => error = 'كلمة المرور غير صحيحة');
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    final pwd = ctrl.text.trim();
                    if (pwd.isEmpty) {
                      setSt(() => error = 'أدخل كلمة المرور');
                      return;
                    }
                    final ok = await AuthService.verifyPassword(pwd);
                    if (ok) {
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } else {
                      setSt(() => error = 'كلمة المرور غير صحيحة');
                      ctrl.clear();
                    }
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ),
        ),
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// 🆕 طلب سبب التعديل — يتخطى تلقائيًا إذا الإعداد معطل
  ///
  /// القيم المرجعة:
  /// - `null` = المستخدم ألغى → لا تكمل
  /// - `''`   = الإعداد معطل → أكمل بدون سبب
  /// - نص    = السبب → أكمل مع تسجيله
  static Future<String?> requireReason(
    BuildContext context, {
    String? title,
    String? hint,
  }) async {
    final enabled = SettingsService.getBool(
      AppSettings.requireEditReason,
      defaultValue: false,
    );
    if (!enabled) return '';

    if (!context.mounted) return null;

    final ctrl = TextEditingController();
    String? error;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.blue),
                const SizedBox(width: 8),
                Text(title ?? 'سبب التعديل'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'يرجى كتابة سبب التعديل (سيُسجَّل في السجل)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'السبب',
                    hintText: hint ?? 'مثال: خطأ في المبلغ',
                    border: const OutlineInputBorder(),
                    errorText: error,
                    prefixIcon: const Icon(Icons.edit_note),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final v = ctrl.text.trim();
                  if (v.isEmpty) {
                    setSt(() => error = 'أدخل السبب');
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
    return result;
  }

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

class PermissionCache {
  static Map<String, bool> _cache = {};
  static String? _cachedDeviceId;
  static bool _isPrimary = false;

  static const List<String> _allPermissions = [
    'add_customers', 'edit_customers', 'delete_customers',
    'toggle_customer_active', 'edit_max_balance',
    'add_transactions', 'edit_transactions', 'delete_transactions',
    'view_all_transactions', 'view_stats', 'export_data',
    'view_logs', 'access_advanced_settings', 'manage_backups',
    'manage_accountants', 'can_become_primary',
  ];

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

  static bool has(String permission) {
    if (_isPrimary) return true;
    return _cache[permission] == true;
  }

  static bool get isPrimary => _isPrimary;

  static Future<bool> needsRefresh() async {
    try {
      final currentDeviceId = await DeviceService.getDeviceId();
      return _cachedDeviceId != currentDeviceId || _cache.isEmpty;
    } catch (_) {
      return true;
    }
  }

  static void clear() {
    _cache = {};
    _cachedDeviceId = null;
    _isPrimary = false;
  }
}

// بوابة الصلاحيات v1 — ملف جديد
// بوابة الصلاحيات v2: إضافة requirePassword وrequireReason
