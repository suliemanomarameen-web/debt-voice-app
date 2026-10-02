import 'package:flutter/material.dart';
import '../services/gdrive_service.dart';
import '../services/backup_service.dart';

class GDriveScreen extends StatefulWidget {
  const GDriveScreen({super.key});
  @override
  State<GDriveScreen> createState() => _GDriveScreenState();
}

class _GDriveScreenState extends State<GDriveScreen> {
  bool _busy = false;
  String _status = '';
  List<Map<String, dynamic>> _backups = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _busy = true);
    // حاول استرجاع الجلسة
    await GDriveService.trySilentSignIn();
    await _refreshList();
    if (mounted) setState(() => _busy = false);
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
    final ok = await GDriveService.signIn();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = ok ? '✅ تم تسجيل الدخول' : '❌ فشل تسجيل الدخول';
    });
    if (ok) await _refreshList();
  }

  Future<void> _signOut() async {
    final ok = await _confirm('تسجيل الخروج؟', 'سيتم فصل الحساب من التطبيق.');
    if (!ok) return;
    await GDriveService.signOut();
    if (!mounted) return;
    setState(() {
      _backups = [];
      _status = 'تم تسجيل الخروج';
    });
  }

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

    // اسأل: دمج أم استبدال؟
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
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = GDriveService.isSignedIn;

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
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        signedIn ? Icons.cloud_done : Icons.cloud_off,
                        color: signedIn
                            ? theme.colorScheme.primary
                            : Colors.grey,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              signedIn
                                  ? (GDriveService.userName ?? 'مستخدم Google')
                                  : 'غير متصل',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (signedIn)
                              Text(
                                GDriveService.userEmail ?? '',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      if (signedIn)
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'تسجيل الخروج',
                          onPressed: _busy ? null : _signOut,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ========== أزرار الإجراءات ==========
              if (!signedIn)
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('تسجيل الدخول بـ Google'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),

              if (signedIn) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('رفع نسخة احتياطية الآن'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshList,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث القائمة'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
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
                        ? Colors.green.shade50
                        : _status.startsWith('❌')
                            ? Colors.red.shade50
                            : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _status.startsWith('✅')
                          ? Colors.green.shade300
                          : _status.startsWith('❌')
                              ? Colors.red.shade300
                              : theme.colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
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
                              ? Colors.green
                              : _status.startsWith('❌')
                                  ? Colors.red
                                  : Colors.blue,
                        ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_status)),
                    ],
                  ),
                ),
              ],

              // ========== قائمة النسخ ==========
              if (signedIn && _backups.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.folder, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'النسخ على Drive (${_backups.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ..._backups.map((b) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.cloud, color: Colors.blue),
                        title: Text(
                          b['name'] ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          _fmtDate(b['created']),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download,
                                  color: Colors.green),
                              tooltip: 'تنزيل واستعادة',
                              onPressed: _busy
                                  ? null
                                  : () => _download(b['id'], b['name']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red),
                              tooltip: 'حذف من Drive',
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
                const SizedBox(height: 50),
                const Center(
                  child: Column(
                    children: [
                      Icon(Icons.cloud_queue, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('لا توجد نسخ على Drive',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('اضغط "رفع نسخة احتياطية الآن" للبدء',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],

              // ========== تلميحات ==========
              const SizedBox(height: 24),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text('كيف يعمل؟',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. سجّل الدخول بحساب Google\n'
                        '2. ارفع نسخة احتياطية → تُحفظ في Drive\n'
                        '3. من أي جهاز آخر: سجّل الدخول → حمّل → استعد',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue.shade900),
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
}
