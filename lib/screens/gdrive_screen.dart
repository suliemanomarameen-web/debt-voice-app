import 'package:flutter/material.dart';
import '../services/gdrive_service.dart';
import '../services/backup_service.dart';
import '../services/sync_service.dart';
import '../services/cloud_backup_service.dart';

class GDriveScreen extends StatefulWidget {
  const GDriveScreen({super.key});
  @override
  State<GDriveScreen> createState() => _GDriveScreenState();
}

class _GDriveScreenState extends State<GDriveScreen> {
  bool _busy = false;
  String _status = '';
  List<Map<String, dynamic>> _backups = [];

  // ===== معلومات المزامنة =====
  DateTime? _lastSync;
  DateTime? _lastUpload;
  DateTime? _lastDownload;
  SyncStatus _syncStatus = SyncStatus.idle;
  bool _hasPending = false;

  // ===== معلومات النسخ السحابي =====
  bool _cloudBackupEnabled = false;
  BackupFrequency _cloudFrequency = BackupFrequency.daily;
  int _cloudMaxBackups = 10;
  DateTime? _lastCloudBackup;

  @override
  void initState() {
    super.initState();
    _init();
    // الاستماع لحالة المزامنة
    SyncService.statusStream.listen((s) {
      if (mounted) setState(() => _syncStatus = s);
    });
  }

  Future<void> _init() async {
    setState(() => _busy = true);
    await GDriveService.trySilentSignIn();
    await _refreshSyncInfo();
    await _refreshCloudInfo();
    await _refreshList();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refreshSyncInfo() async {
    final lastSync = await SyncService.getLastSyncTime();
    final lastUpload = await SyncService.getLastUploadTime();
    final lastDownload = await SyncService.getLastDownloadTime();
    final pending = await SyncService.hasPendingChanges();
    if (!mounted) return;
    setState(() {
      _lastSync = lastSync;
      _lastUpload = lastUpload;
      _lastDownload = lastDownload;
      _hasPending = pending;
    });
  }

  Future<void> _refreshCloudInfo() async {
    final enabled = await CloudBackupService.isEnabled();
    final freq = await CloudBackupService.getFrequency();
    final max = await CloudBackupService.getMaxBackups();
    final lastBackup = await CloudBackupService.getLastBackupTime();
    if (!mounted) return;
    setState(() {
      _cloudBackupEnabled = enabled;
      _cloudFrequency = freq;
      _cloudMaxBackups = max;
      _lastCloudBackup = lastBackup;
    });
  }

  Future<void> _refreshList() async {
    if (!GDriveService.isSignedIn) {
      if (mounted) setState(() => _backups = []);
      return;
    }
    final list = await GDriveService.listBackups();
    if (!mounted) return;
    setState(() => _backups = list);
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _status = 'جاري تسجيل الدخول...';
    });

    final err = await GDriveService.signInWithError();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = err == null ? '✅ تم تسجيل الدخول' : '❌ $err';
    });

    if (err == null) {
      await _refreshList();
      await _refreshSyncInfo();
      await _refreshCloudInfo();
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm('تسجيل الخروج؟', 'سيتم فصل الحساب من التطبيق.');
    if (!ok) return;
    await GDriveService.signOut();
    if (!mounted) return;
    setState(() {
      _backups = [];
      _status = 'تم تسجيل الخروج';
      _lastSync = null;
      _lastUpload = null;
      _lastDownload = null;
      _lastCloudBackup = null;
    });
  }

  // ============================================================
  // ============ المزامنة الثنائية ============================
  // ============================================================
  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _status = 'جاري المزامنة...';
    });

    final result = await SyncService.manualSync();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _status = '✅ ${result.message}\n'
            '${result.customersAdded > 0 ? "حسابات جديدة: ${result.customersAdded}\n" : ""}'
            '${result.transactionsAdded > 0 ? "عمليات جديدة: ${result.transactionsAdded}" : ""}';
      });
      await _refreshSyncInfo();

      if (result.hasConflict && mounted) {
        _showConflictDialog();
      }
    } else {
      setState(() => _status = '❌ ${result.message}');
    }

    if (mounted) setState(() => _busy = false);
  }

  void _showConflictDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('تعارض في المزامنة'),
            ],
          ),
          content: const Text(
            'تم اكتشاف تعارض بين هذا الجهاز والنسخة السحابية.\n\n'
            'تم دمج البيانات تلقائياً (لم تُفقد أي عملية).\n\n'
            'البيانات الموجودة على السحابة تم تحديثها الآن بأحدث نسخة.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ============ النسخ السحابي ============================
  // ============================================================
  Future<void> _runCloudBackupNow() async {
    setState(() {
      _busy = true;
      _status = 'جاري النسخ السحابي...';
    });

    await CloudBackupService.runNow();
    await _refreshCloudInfo();
    await _refreshList();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '✅ تم النسخ السحابي';
    });
  }

  Future<void> _toggleCloudBackup(bool v) async {
    await CloudBackupService.setEnabled(v);
    await _refreshCloudInfo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v
            ? 'تم تفعيل النسخ السحابي التلقائي'
            : 'تم إيقاف النسخ السحابي'),
        backgroundColor: v ? Colors.green : Colors.grey,
      ),
    );
  }

  // ============================================================
  // ============ النسخ الاحتياطي اليدوي ============================
  // ============================================================
  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _status = 'جاري الرفع...';
    });
    final result = await GDriveService.uploadBackup();
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _status = '✅ تم الرفع بنجاح\n'
            'الحسابات: ${result['customers'] ?? 0}\n'
            'العمليات: ${result['transactions'] ?? 0}';
      });
      await _refreshList();
    } else {
      setState(() => _status = '❌ ${result['message'] ?? 'فشل الرفع'}');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _download(String fileId, String name) async {
    setState(() {
      _busy = true;
      _status = 'جاري التحميل...';
    });

    final result = await GDriveService.downloadBackup(fileId);

    if (!mounted) return;
    if (result['success'] != true) {
      setState(() {
        _status = '❌ ${result['message'] ?? 'فشل التحميل'}';
        _busy = false;
      });
      return;
    }

    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة من Drive'),
          content: Text('الملف: $name\n\nكيف تريد الاستعادة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('استبدال كامل'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('دمج'),
            ),
          ],
        ),
      ),
    );

    if (mode == null) {
      setState(() => _busy = false);
      return;
    }

    final restore = await BackupService.restoreFromFile(
      result['file_path'],
      mode: mode,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = restore.success
          ? '✅ ${restore.message}\n'
              'حسابات: ${restore.customersAdded}\n'
              'عمليات: ${restore.transactionsAdded}'
          : '❌ ${restore.message}';
    });
  }

  Future<void> _delete(String fileId) async {
    final ok = await _confirm('حذف نسخة؟', 'سيتم حذفها من Google Drive.');
    if (!ok) return;

    setState(() => _busy = true);
    await GDriveService.deleteBackup(fileId);
    await _refreshList();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<bool> _confirm(String title, String message) async {
    final theme = Theme.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title,
              style: TextStyle(color: theme.colorScheme.onSurface)),
          content: Text(message,
              style: TextStyle(color: theme.colorScheme.onSurface)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('نعم'),
            ),
          ],
        ),
      ),
    );
    return r ?? false;
  }

  // ========== أدوات مساعدة ==========
  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return 'لم تحدث بعد';
    final local = dt.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} - '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _fmtRelative(DateTime? dt) {
    if (dt == null) return 'أبداً';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'قبل ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return _fmtDateTime(dt);
  }

  String _syncStatusLabel(SyncStatus s) {
    switch (s) {
      case SyncStatus.idle:
        return 'جاهز';
      case SyncStatus.uploading:
        return 'جاري الرفع...';
      case SyncStatus.downloading:
        return 'جاري التنزيل...';
      case SyncStatus.syncing:
        return 'جاري المزامنة...';
      case SyncStatus.conflict:
        return '⚠️ تعارض';
      case SyncStatus.error:
        return '❌ خطأ';
    }
  }

  Color _syncStatusColor(SyncStatus s) {
    switch (s) {
      case SyncStatus.idle:
        return Colors.green;
      case SyncStatus.uploading:
      case SyncStatus.downloading:
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.conflict:
        return Colors.orange;
      case SyncStatus.error:
        return Colors.red;
    }
  }

  String _cloudFreqLabel(BackupFrequency f) {
    return CloudBackupService.frequencyLabel(f);
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} - '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final signedIn = GDriveService.isSignedIn;

    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLow;
    final onCard = isDark ? Colors.white : theme.colorScheme.onSurface;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('Google Drive')),
        body: RefreshIndicator(
          onRefresh: _init,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ========== حالة الحساب ==========
              Card(
                color: signedIn
                    ? (isDark
                        ? Colors.green.shade900.withOpacity(0.4)
                        : theme.colorScheme.primaryContainer)
                    : cardBg,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        signedIn ? Icons.cloud_done : Icons.cloud_off,
                        color: signedIn
                            ? (isDark
                                ? Colors.green.shade300
                                : theme.colorScheme.primary)
                            : (isDark ? Colors.grey.shade400 : Colors.grey),
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              signedIn
                                  ? (GDriveService.userName ??
                                      'مستخدم Google')
                                  : 'غير متصل',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: onCard,
                              ),
                            ),
                            if (signedIn)
                              Text(
                                GDriveService.userEmail ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: onCard.withOpacity(0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (signedIn)
                        IconButton(
                          icon: Icon(Icons.logout, color: onCard),
                          tooltip: 'تسجيل الخروج',
                          onPressed: _busy ? null : _signOut,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ========== زر تسجيل الدخول ==========
              if (!signedIn)
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('تسجيل الدخول بـ Google'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),

              // ========== محتوى المسجل ==========
              if (signedIn) ...[
                // ===== بطاقة المزامنة =====
                Card(
                  elevation: 3,
                  color: isDark
                      ? Colors.blue.shade900.withOpacity(0.25)
                      : Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.sync,
                              color: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade700,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'المزامنة الثنائية',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.blue.shade100
                                    : Colors.blue.shade900,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _syncStatusColor(_syncStatus)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _syncStatusColor(_syncStatus),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_syncStatus == SyncStatus.syncing ||
                                      _syncStatus == SyncStatus.uploading ||
                                      _syncStatus ==
                                          SyncStatus.downloading)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  else
                                    Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: _syncStatusColor(_syncStatus),
                                    ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _syncStatusLabel(_syncStatus),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _syncStatusColor(_syncStatus),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        _infoRow(
                          Icons.sync,
                          'آخر مزامنة',
                          _fmtRelative(_lastSync),
                          onCard,
                        ),
                        const SizedBox(height: 6),
                        _infoRow(
                          Icons.cloud_upload,
                          'آخر رفع',
                          _fmtRelative(_lastUpload),
                          onCard,
                        ),
                        const SizedBox(height: 6),
                        _infoRow(
                          Icons.cloud_download,
                          'آخر تنزيل',
                          _fmtRelative(_lastDownload),
                          onCard,
                        ),

                        if (_hasPending) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.pending_actions,
                                    size: 16, color: Colors.orange.shade800),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'هناك تغييرات لم تُزامن بعد',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        FilledButton.icon(
                          onPressed: _busy ? null : _syncNow,
                          icon: const Icon(Icons.sync),
                          label: const Text('مزامنة الآن'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            backgroundColor:
                                isDark ? Colors.blue.shade700 : Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ===== بطاقة النسخ السحابي =====
                Card(
                  elevation: 3,
                  color: isDark
                      ? Colors.deepPurple.shade900.withOpacity(0.25)
                      : Colors.deepPurple.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              color: isDark
                                  ? Colors.deepPurple.shade200
                                  : Colors.deepPurple.shade700,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'النسخ السحابي التلقائي',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark
                                      ? Colors.deepPurple.shade100
                                      : Colors.deepPurple.shade900,
                                ),
                              ),
                            ),
                            Switch(
                              value: _cloudBackupEnabled,
                              onChanged: _busy ? null : _toggleCloudBackup,
                              activeColor: Colors.deepPurple,
                            ),
                          ],
                        ),
                        const Divider(height: 20),

                        if (_cloudBackupEnabled) ...[
                          _infoRow(
                            Icons.schedule,
                            'التكرار',
                            _cloudFreqLabel(_cloudFrequency),
                            onCard,
                          ),
                          const SizedBox(height: 6),
                          _infoRow(
                            Icons.storage,
                            'عدد النسخ المحفوظة',
                            _cloudMaxBackups < 0
                                ? 'غير نهائي'
                                : 'آخر $_cloudMaxBackups نسخة',
                            onCard,
                          ),
                          const SizedBox(height: 6),
                          _infoRow(
                            Icons.history,
                            'آخر نسخة سحابية',
                            _fmtRelative(_lastCloudBackup),
                            onCard,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _busy ? null : _runCloudBackupNow,
                            icon: const Icon(Icons.cloud_upload),
                            label: const Text('رفع نسخة الآن'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              backgroundColor: Colors.deepPurple,
                            ),
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'عند التفعيل، يتم رفع نسخة احتياطية تلقائياً إلى Drive حسب التكرار المحدد في الإعدادات.',
                              style: TextStyle(
                                fontSize: 12,
                                color: onCard.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ===== الأزرار اليدوية =====
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.backup),
                  label: const Text('إنشاء نسخة منفصلة الآن'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshList,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث قائمة النسخ'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],

              // ========== الحالة ==========
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _status.startsWith('✅')
                        ? (isDark
                            ? Colors.green.shade900.withOpacity(0.4)
                            : Colors.green.shade50)
                        : _status.startsWith('❌')
                            ? (isDark
                                ? Colors.red.shade900.withOpacity(0.4)
                                : Colors.red.shade50)
                            : cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _status.startsWith('✅')
                          ? Colors.green.shade400
                          : _status.startsWith('❌')
                              ? Colors.red.shade400
                              : theme.colorScheme.outline,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_busy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _status.startsWith('✅')
                              ? Icons.check_circle
                              : _status.startsWith('❌')
                                  ? Icons.error
                                  : Icons.info,
                          color: _status.startsWith('✅')
                              ? (isDark
                                  ? Colors.green.shade300
                                  : Colors.green)
                              : _status.startsWith('❌')
                                  ? (isDark
                                      ? Colors.red.shade300
                                      : Colors.red)
                                  : (isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          _status,
                          style: TextStyle(
                            fontSize: 13,
                            color: _status.startsWith('✅')
                                ? (isDark
                                    ? Colors.green.shade100
                                    : Colors.green.shade900)
                                : _status.startsWith('❌')
                                    ? (isDark
                                        ? Colors.red.shade100
                                        : Colors.red.shade900)
                                    : onCard,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ========== قائمة النسخ ==========
              if (signedIn && _backups.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(Icons.folder,
                        color:
                            isDark ? Colors.blue.shade300 : Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'النسخ المحفوظة على Drive (${_backups.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: onCard,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._backups.map((b) => Card(
                      color: cardBg,
                      child: ListTile(
                        leading: Icon(Icons.cloud,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue),
                        title: Text(
                          b['name'] ?? '',
                          style:
                              TextStyle(fontSize: 13, color: onCard),
                        ),
                        subtitle: Text(
                          _fmtDate(b['created']),
                          style: TextStyle(
                            fontSize: 11,
                            color: onCard.withOpacity(0.7),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.download,
                                  color: isDark
                                      ? Colors.green.shade300
                                      : Colors.green),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                      _download(b['id'], b['name']),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete,
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red),
                              onPressed:
                                  _busy ? null : () => _delete(b['id']),
                            ),
                          ],
                        ),
                      ),
                    )),
              ],

              // ========== حالة فارغة ==========
              if (signedIn && _backups.isEmpty && !_busy) ...[
                const SizedBox(height: 30),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.cloud_queue,
                          size: 60,
                          color: isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('لا توجد نسخ منفصلة',
                          style: TextStyle(color: onCard, fontSize: 14)),
                      const SizedBox(height: 6),
                      Text(
                        'المزامنة التلقائية تعمل في الخلفية',
                        style: TextStyle(
                          color: onCard.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ========== التلميحات ==========
              const SizedBox(height: 24),
              Card(
                color: isDark
                    ? Colors.blue.shade900.withOpacity(0.3)
                    : Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'كيف يعمل؟',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.blue.shade100
                                  : Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '🔄 المزامنة الثنائية:\n'
                        '  • عند إضافة عملية → يُرفع تلقائياً بعد 5 ثوانٍ\n'
                        '  • عند فتح التطبيق → تُنزَّل التحديثات تلقائياً\n'
                        '  • كل 5 دقائق مزامنة دورية في الخلفية\n\n'
                        '☁️ النسخ السحابي:\n'
                        '  • رفع نسخة احتياطية منفصلة حسب التكرار المحدد\n'
                        '  • يحفظ عدد محدد من النسخ أو غير نهائي\n\n'
                        '📱 النسخ المنفصلة:\n'
                        '  • تُنشأ يدوياً لاستعادة إصدارات محددة',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: isDark
                              ? Colors.blue.shade100
                              : Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, Color onCard) {
    return Row(
      children: [
        Icon(icon, size: 16, color: onCard.withOpacity(0.6)),
        const SizedBox(width: 6),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 12,
            color: onCard.withOpacity(0.7),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: onCard,
            ),
          ),
        ),
      ],
    );
  }
}
