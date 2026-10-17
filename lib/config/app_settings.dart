/// ═══════════════════════════════════════════════════════════
/// مفاتيح الإعدادات الموحّدة
/// ═══════════════════════════════════════════════════════════
class AppSettings {
  // ═══════════════════════════════════════════════════════════
  // 🗑️ مجموعة الحذف
  // ═══════════════════════════════════════════════════════════

  static const String blockDeleteNonzeroBalance =
      'block_delete_nonzero_balance';
  static const String blockDeleteWithTransactions =
      'block_delete_with_transactions';
  static const String softDeleteEnabled = 'soft_delete_enabled';
  static const String retentionDays = 'retention_days';
  static const String autoCleanupDeleted = 'auto_cleanup_deleted';

  /// 🆕 السماح بحذف العمليات
  static const String allowDeleteTransactions =
      'allow_delete_transactions';

  // ═══════════════════════════════════════════════════════════
  // ✏️ مجموعة التعديل
  // ═══════════════════════════════════════════════════════════

  static const String allowEditCustomers = 'allow_edit_customers';
  static const String allowEditTransactions = 'allow_edit_transactions';
  static const String allowEditCustomerBalance =
      'allow_edit_customer_balance';
  static const String trackEdits = 'track_edits';
  static const String requireEditReason = 'require_edit_reason';

  // ═══════════════════════════════════════════════════════════
  // 🔄 مجموعة المزامنة
  // ═══════════════════════════════════════════════════════════

  static const String syncEnabled = 'sync_enabled';
  static const String syncIntervalMinutes = 'sync_interval_minutes';
  static const String syncOnDataChange = 'sync_on_data_change';
  static const String syncOnAppOpen = 'sync_on_app_open';
  static const String autoResolveConflicts = 'auto_resolve_conflicts';
  static const String conflictNotification = 'conflict_notification';
  static const String deletionConflictRestore =
      'deletion_conflict_restore';
  static const String syncLogs = 'sync_logs';

  // ═══════════════════════════════════════════════════════════
  // 📜 مجموعة السجل
  // ═══════════════════════════════════════════════════════════

  static const String logEnabled = 'log_enabled';
  static const String logRetentionDays = 'log_retention_days';
  static const String logMaxCount = 'log_max_count';
  static const String logAutoCleanup = 'log_auto_cleanup';
  static const String logRemoteActivity = 'log_remote_activity';
  static const String logTransactionEdits = 'log_transaction_edits';
  static const String logRequiresAckForWarnings =
      'log_requires_ack_for_warnings';

  // ═══════════════════════════════════════════════════════════
  // 🎤 مجموعة الصوت
  // ═══════════════════════════════════════════════════════════

  static const String voiceEnabled = 'voice_enabled';
  static const String voiceAutoSaveHighConfidence =
      'voice_auto_save_high_confidence';
  static const String voiceConfirmBeforeSave = 'voice_confirm_before_save';
  static const String voicePendingAutoExpireDays =
      'voice_pending_auto_expire_days';
  static const String voiceFilterEmpty = 'voice_filter_empty';
  static const String voiceFilterUnclear = 'voice_filter_unclear';

  // ═══════════════════════════════════════════════════════════
  // 💰 مجموعة الرصيد والحدود
  // ═══════════════════════════════════════════════════════════

  static const String enforceMaxBalance = 'enforce_max_balance';
  static const String warnOnExceed = 'warn_on_exceed';
  static const String blockOnExceed = 'block_on_exceed';
  static const String allowDebtOnInactive = 'allow_debt_on_inactive';
  static const String notifyDebtOnInactive = 'notify_debt_on_inactive';

  // ═══════════════════════════════════════════════════════════
  // 🔒 مجموعة الأمان
  // ═══════════════════════════════════════════════════════════

  static const String lockEnabled = 'lock_enabled';
  static const String lockTimeoutMinutes = 'lock_timeout_minutes';
  static const String requirePasswordForDelete =
      'require_password_for_delete';
  static const String requirePasswordForRestore =
      'require_password_for_restore';
  static const String requirePasswordForDangerousSettings =
      'require_password_for_dangerous_settings';

  // ═══════════════════════════════════════════════════════════
  // 📱 مجموعة الواجهة
  // ═══════════════════════════════════════════════════════════

  static const String showDeletedBin = 'show_deleted_bin';
  static const String showTrackingInfo = 'show_tracking_info';
  static const String showCloudId = 'show_cloud_id';
  static const String compactMode = 'compact_mode';

  // ═══════════════════════════════════════════════════════════
  // 📋 القيم الافتراضية
  // ═══════════════════════════════════════════════════════════

  static const Map<String, dynamic> defaults = {
    // 🗑️ الحذف
    blockDeleteNonzeroBalance: true,
    blockDeleteWithTransactions: true,
    softDeleteEnabled: true,
    retentionDays: 30,
    autoCleanupDeleted: true,
    allowDeleteTransactions: true, // 🆕

    // ✏️ التعديل
    allowEditCustomers: true,
    allowEditTransactions: true,
    allowEditCustomerBalance: false,
    trackEdits: true,
    requireEditReason: false,

    // 🔄 المزامنة
    syncEnabled: true,
    syncIntervalMinutes: 5,
    syncOnDataChange: true,
    syncOnAppOpen: true,
    autoResolveConflicts: true,
    conflictNotification: true,
    deletionConflictRestore: true,
    syncLogs: true,

    // 📜 السجل
    logEnabled: true,
    logRetentionDays: 30,
    logMaxCount: 5000,
    logAutoCleanup: true,
    logRemoteActivity: true,
    logTransactionEdits: true,
    logRequiresAckForWarnings: true,

    // 🎤 الصوت
    voiceEnabled: true,
    voiceAutoSaveHighConfidence: true,
    voiceConfirmBeforeSave: true,
    voicePendingAutoExpireDays: 30,
    voiceFilterEmpty: true,
    voiceFilterUnclear: true,

    // 💰 الرصيد
    enforceMaxBalance: true,
    warnOnExceed: true,
    blockOnExceed: false,
    allowDebtOnInactive: true,
    notifyDebtOnInactive: true,

    // 🔒 الأمان
    lockEnabled: false,
    lockTimeoutMinutes: 30,
    requirePasswordForDelete: false,
    requirePasswordForRestore: false,
    requirePasswordForDangerousSettings: true,

    // 📱 الواجهة
    showDeletedBin: true,
    showTrackingInfo: true,
    showCloudId: false,
    compactMode: false,
  };

  // ═══════════════════════════════════════════════════════════
  // 📊 مجموعات للعرض والتحكم
  // ═══════════════════════════════════════════════════════════

  static const Set<String> dangerousSettings = {
    blockDeleteNonzeroBalance,
    blockDeleteWithTransactions,
    softDeleteEnabled,
    syncEnabled,
    autoResolveConflicts,
    deletionConflictRestore,
  };

  static const Set<String> sharedSettings = {
    blockDeleteNonzeroBalance,
    blockDeleteWithTransactions,
    softDeleteEnabled,
    retentionDays,
    autoCleanupDeleted,
    allowDeleteTransactions, // 🆕
    allowEditCustomers,
    allowEditTransactions,
    allowEditCustomerBalance,
    trackEdits,
    requireEditReason,
    logEnabled,
    logRetentionDays,
    logMaxCount,
    logRemoteActivity,
    logTransactionEdits,
    logRequiresAckForWarnings,
    enforceMaxBalance,
    warnOnExceed,
    blockOnExceed,
    allowDebtOnInactive,
    notifyDebtOnInactive,
  };

  static const Set<String> localSettings = {
    syncEnabled,
    syncIntervalMinutes,
    syncOnDataChange,
    syncOnAppOpen,
    autoResolveConflicts,
    conflictNotification,
    deletionConflictRestore,
    syncLogs,
    voiceEnabled,
    voiceAutoSaveHighConfidence,
    voiceConfirmBeforeSave,
    voicePendingAutoExpireDays,
    voiceFilterEmpty,
    voiceFilterUnclear,
    lockEnabled,
    lockTimeoutMinutes,
    requirePasswordForDelete,
    requirePasswordForRestore,
    requirePasswordForDangerousSettings,
    showDeletedBin,
    showTrackingInfo,
    showCloudId,
    compactMode,
  };

  static bool isShared(String key) => sharedSettings.contains(key);
  static bool isLocal(String key) => localSettings.contains(key);
  static bool isDangerous(String key) => dangerousSettings.contains(key);
}
