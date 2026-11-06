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

  static const String blockCustomerDeletion = 'block_customer_deletion';
  static const String blockTransactionDeletion =
      'block_transaction_deletion';

  static const String permanentDeleteAlwaysWins =
      'permanent_delete_always_wins';
  static const String modificationAlwaysWins =
      'modification_always_wins';

  // ═══════════════════════════════════════════════════════════
  // ✏️ مجموعة التعديل
  // ═══════════════════════════════════════════════════════════

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
  static const String syncDeletedBin = 'sync_deleted_bin';

  // ═══════════════════════════════════════════════════════════
  // 🔀 مجموعة كشف التكرار (v2.4)
  // ═══════════════════════════════════════════════════════════

  static const String duplicateDetectionEnabled =
      'duplicate_detection_enabled';
  static const String duplicateDetectionLevel =
      'duplicate_detection_level';
  static const String compoundNameHandling = 'compound_name_handling';
  static const String detectHighSimilarity = 'detect_high_similarity';
  static const String normalizeHamza = 'normalize_hamza';
  static const String normalizeTaaMarbuta = 'normalize_taa_marbuta';
  static const String blockSyncOnConfirmed = 'block_sync_on_confirmed';
  static const String blockSyncOnLikely = 'block_sync_on_likely';
  static const String blockSyncOnWeak = 'block_sync_on_weak';
  static const String blockSyncOnSimilar = 'block_sync_on_similar';
  static const String transactionDuplicateMode =
      'transaction_duplicate_mode';
  static const String transactionWindowMinutes =
      'transaction_window_minutes';
  static const String autoRenameFormat = 'auto_rename_format';
  static const String maxDuplicatesPerSync = 'max_duplicates_per_sync';
  static const String notifyOnMerge = 'notify_on_merge';
  static const String notifyOnRename = 'notify_on_rename';
  static const String notifyOnSkip = 'notify_on_skip';
  static const String notifyOnDuplicateDetected =
      'notify_on_duplicate_detected';

  // ═══════════════════════════════════════════════════════════
  // 🔔 مجموعة الإشعارات (v2.5)
  // ═══════════════════════════════════════════════════════════

  static const String notificationsRetentionMode =
      'notifications_retention_mode';
  static const String notificationsRetentionDays =
      'notifications_retention_days';
  static const String notificationsRetentionCount =
      'notifications_retention_count';
  static const String notificationsKeepPending =
      'notifications_keep_pending';
  static const String notificationsDeleteAudio =
      'notifications_delete_audio';

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

  // 🆕 الحوار الصوتي التفاعلي (v6)
  static const String voiceConversationEnabled =
      'voice_conversation_enabled';
  static const String voiceAlwaysAskForItems = 'voice_always_ask_for_items';
  static const String voiceMaxConversationRounds =
      'voice_max_conversation_rounds';

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
  // رمز المحاسب في العمليات
  // ═══════════════════════════════════════════════════════════

  static const String codeIncludeAccountant = 'code_include_accountant';
  static const String codeAccountantPosition = 'code_accountant_position';
  static const String codeAccountantSeparator = 'code_accountant_separator';

  // ═══════════════════════════════════════════════════════════
  // 🖼️ مجموعة الزر العائم
  // ═══════════════════════════════════════════════════════════

  static const String overlayRecordMode = 'overlay_record_mode';
  static const String overlayAutoStart = 'overlay_auto_start';

  // 🆕 أزرار الإشعار الدائم (3 كحد أقصى في Android)
  static const String overlayNotifBtnRecord = 'overlay_notif_btn_record';
  static const String overlayNotifBtnQuickTx = 'overlay_notif_btn_quick_tx';
  static const String overlayNotifBtnNotifications =
      'overlay_notif_btn_notifications';
  static const String overlayNotifBtnNewCustomer =
      'overlay_notif_btn_new_customer';
  static const String overlayNotifBtnStats = 'overlay_notif_btn_stats';
  static const String overlayNotifBtnStopOverlay =
      'overlay_notif_btn_stop_overlay';

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
    blockCustomerDeletion: false,
    blockTransactionDeletion: false,

    // إعدادات التعارض
    permanentDeleteAlwaysWins: true,
    modificationAlwaysWins: false,

    // ✏️ التعديل
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
    syncDeletedBin: true,

    // 🔀 كشف التكرار
    duplicateDetectionEnabled: true,
    duplicateDetectionLevel: 'balanced',
    compoundNameHandling: 'auto',
    detectHighSimilarity: true,
    normalizeHamza: true,
    normalizeTaaMarbuta: true,
    blockSyncOnConfirmed: true,
    blockSyncOnLikely: false,
    blockSyncOnWeak: false,
    blockSyncOnSimilar: false,
    transactionDuplicateMode: 'code',
    transactionWindowMinutes: 30,
    autoRenameFormat: '(2)',
    maxDuplicatesPerSync: 50,
    notifyOnMerge: true,
    notifyOnRename: true,
    notifyOnSkip: false,
    notifyOnDuplicateDetected: true,

    // 🔔 الإشعارات
    notificationsRetentionMode: 'days',
    notificationsRetentionDays: 30,
    notificationsRetentionCount: 100,
    notificationsKeepPending: true,
    notificationsDeleteAudio: true,

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

    // 🆕 الحوار الصوتي التفاعلي
    voiceConversationEnabled: true,
    voiceAlwaysAskForItems: false,
    voiceMaxConversationRounds: 3,

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

    // رمز المحاسب
    codeIncludeAccountant: false,
    codeAccountantPosition: 'suffix',
    codeAccountantSeparator: '',

    // 🖼️ الزر العائم
    overlayRecordMode: 'long_press',
    overlayAutoStart: true,
    overlayNotifBtnRecord: true,
    overlayNotifBtnQuickTx: false,
    overlayNotifBtnNotifications: false,
    overlayNotifBtnNewCustomer: false,
    overlayNotifBtnStats: false,
    overlayNotifBtnStopOverlay: false,
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
    blockCustomerDeletion,
    blockTransactionDeletion,
    permanentDeleteAlwaysWins,
    modificationAlwaysWins,
  };

  static const Set<String> sharedSettings = {
    blockDeleteNonzeroBalance,
    blockDeleteWithTransactions,
    softDeleteEnabled,
    retentionDays,
    autoCleanupDeleted,
    blockCustomerDeletion,
    blockTransactionDeletion,
    permanentDeleteAlwaysWins,
    modificationAlwaysWins,
    // 🔀 كشف التكرار — مُزامَن
    duplicateDetectionEnabled,
    duplicateDetectionLevel,
    compoundNameHandling,
    detectHighSimilarity,
    normalizeHamza,
    normalizeTaaMarbuta,
    blockSyncOnConfirmed,
    blockSyncOnLikely,
    blockSyncOnWeak,
    blockSyncOnSimilar,
    transactionDuplicateMode,
    transactionWindowMinutes,
    autoRenameFormat,
    maxDuplicatesPerSync,
    notifyOnMerge,
    notifyOnRename,
    notifyOnSkip,
    notifyOnDuplicateDetected,
    // ✏️ التعديل
    allowEditTransactions,
    allowEditCustomerBalance,
    trackEdits,
    requireEditReason,
    // المزامنة والسجل
    syncDeletedBin,
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
    // 🆕 الحوار الصوتي
    voiceConversationEnabled,
    voiceAlwaysAskForItems,
    voiceMaxConversationRounds,
    lockEnabled,
    lockTimeoutMinutes,
    requirePasswordForDelete,
    requirePasswordForRestore,
    requirePasswordForDangerousSettings,
    showDeletedBin,
    showTrackingInfo,
    showCloudId,
    compactMode,
    codeIncludeAccountant,
    codeAccountantPosition,
    codeAccountantSeparator,
    // 🔔 الإشعارات
    notificationsRetentionMode,
    notificationsRetentionDays,
    notificationsRetentionCount,
    notificationsKeepPending,
    notificationsDeleteAudio,
    // 🖼️ الزر العائم
    overlayRecordMode,
    overlayAutoStart,
    overlayNotifBtnRecord,
    overlayNotifBtnQuickTx,
    overlayNotifBtnNotifications,
    overlayNotifBtnNewCustomer,
    overlayNotifBtnStats,
    overlayNotifBtnStopOverlay,
  };

  static bool isShared(String key) => sharedSettings.contains(key);
  static bool isLocal(String key) => localSettings.contains(key);
  static bool isDangerous(String key) => dangerousSettings.contains(key);
}

// الإعدادات v2: إضافة permanentDeleteAlwaysWins (خيار الحذف النهائي يفوز دائماً)
// الإعدادات v2.2: إضافة modificationAlwaysWins (حصري مع permanentDeleteAlwaysWins — لا يُفعّلان معاً)
// الإعدادات v2.4: إضافة 18 إعداداً شاملاً لنظام التكرار (تشغيل، مستوى، تطبيع، إيقاف، إشعارات، سلوك تلقائي)
// الإعدادات v2.5: إضافة 5 إعدادات للإشعارات (وضع الاحتفاظ، المدة، العدد، احتفظ بالمعلقة، احذف الصوت)

// الإعدادات v6: إضافة 3 إعدادات للحوار الصوتي التفاعلي + overlayRecordMode

// الإعدادات v7: إضافة overlayAutoStart + 6 إعدادات لأزرار الإشعار الدائم
