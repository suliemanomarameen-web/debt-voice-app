import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../services/gdrive_service.dart';
import '../services/sync_service.dart';
import '../services/logger_service.dart';
import '../models/log_event.dart';

class SyncDebugScreen extends StatefulWidget {
  const SyncDebugScreen({super.key});

  @override
  State<SyncDebugScreen> createState() => _SyncDebugScreenState();
}

class _SyncDebugScreenState extends State<SyncDebugScreen> {
  bool _loading = true;
  bool _busy = false;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final db = DatabaseHelper.instance;
    final result = <String, dynamic>{};

    try {
      // 1) حالة Google
      result['isSignedIn'] = GDriveService.isSignedIn;
      result['userEmail'] = GDriveService.userEmail ?? '—';

      // 2) المحلي
      final localCustomers = await db.allCustomersRaw();
      final localTransactions = await db.allTransactionsRaw();
      final localLogs = await db.allLogEventsRaw();
      final localCodes = await db.allUsedCodesRaw();

      result['localCustomers'] = localCustomers.length;
      result['localTransactions'] = localTransactions.length;
      result['localLogs'] = localLogs.length;
      result['localCodes'] = localCodes.length;

      result['localDeletedCustomers'] =
          localCustomers.where((c) => c['is_deleted'] == 1).length;
      result['localDeletedTransactions'] =
          localTransactions.where((t) => t['is_deleted'] == 1).length;

      // 3) السحابة
      try {
        final fileId = await GDriveService.getSyncFileId();
        result['syncFileId'] = fileId ?? '❌ غير موجود';

        final modified = await GDriveService.getSyncFileModifiedTime();
        result['lastModified'] = modified?.toIso8601String() ?? '—';

        final cloudData = await GDriveService.downloadSyncFile();
        if (cloudData != null) {
          final cloudCustomers = (cloudData['customers'] as List?) ?? [];
          final cloudTransactions =
              (cloudData['transactions'] as List?) ?? [];
          final cloudLogs = (cloudData['log_events'] as List?) ?? [];
          final cloudCodes = (cloudData['used_codes'] as List?) ?? [];

          result['cloudCustomers'] = cloudCustomers.length;
          result['cloudTransactions'] = cloudTransactions.length;
          result['cloudLogs'] = cloudLogs.length;
          result['cloudCodes'] = cloudCodes.length;

          result['cloudCreatedAt'] = cloudData['created_at'] ?? '—';
          result['cloudVersion'] = cloudData['version'] ?? '—';

          result['cloudDeletedCustomers'] = cloudCustomers
              .where((c) => c['is_deleted'] == 1)
              .length;
          result['cloudDeletedTransactions'] = cloudTransactions
              .where((t) => t['is_deleted'] == 1)
              .length;

          // الفروق
          result['diffCustomers'] =
              localCustomers.length - cloudCustomers.length;
          result['diffTransactions'] =
              localTransactions.length - cloudTransactions.length;
          result['diffLogs'] = localLogs.length - cloudLogs.length;
          result['diffCodes'] = localCodes.length - cloudCodes.length;
        } else {
          result['cloudData'] = '❌ null';
        }
      } catch (e) {
        result['cloudError'] = e.toString();
      }
    } catch (e) {
      result['error'] = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _data = result;
      _loading = false;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // إصلاح الرموز المكررة
  // ═══════════════════════════════════════════════════════════
  Future<void> _fixDuplicateCodes() async {
    final confirm = await _confirmDialog(
      title: '🔧 إصلاح الرموز المكررة',
      message:
          'سيتم:\n'
          '1. مسح جدول "used_codes" بالكامل\n'
          '2. إعادة بنائه من المعاملات الحالية فقط\n'
          '3. حذف أي رموز يتيمة (بدون معاملة)\n\n'
          '✅ آمن — لن تحذف أي معاملة',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final db = DatabaseHelper.instance;

      // 1) احفظ عدد الرموز القديمة
      final oldCodes = await db.allUsedCodesRaw();
      final oldCount = oldCodes.length;

      // 2) امسح كل الرموز
      await db.database.then((d) => d.delete('used_codes'));

      // 3) اقرأ كل المعاملات
      final transactions = await db.allTransactionsRaw();

      // 4) أعد بناء الرموز من المعاملات
      int rebuilt = 0;
      for (final t in transactions) {
        final code = t['code'] as String?;
        if (code == null || code.isEmpty) continue;

        try {
          await db.database.then((d) => d.insert('used_codes', {
                'code': code,
                'type': t['type'] as String? ?? 'debt',
                'created_at': t['created_at'] as String? ??
                    DateTime.now().toIso8601String(),
              }));
          rebuilt++;
        } catch (e) {
          // مكرر في المعاملات — تجاهل
        }
      }

      // 5) سجّل النتيجة
      await LoggerService.log(
        action: '🔧 إصلاح الرموز',
        description: 'تم مسح $oldCount رمز وإعادة بناء $rebuilt رمز',
        level: LogLevel.info,
        category: LogCategory.system,
      );

      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(true, '✅ تم الإصلاح: $oldCount → $rebuilt رمز');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, 'خطأ: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // مسح الرموز اليتيمة فقط (بدون لمس الصحيحة)
  // ═══════════════════════════════════════════════════════════
  Future<void> _cleanOrphanCodes() async {
    final confirm = await _confirmDialog(
      title: '🗑️ مسح الرموز اليتيمة',
      message:
          'سيتم حذف الرموز التي لا تقابلها معاملة في جدول transactions.\n\n'
          '✅ آمن — الرموز المستخدمة في معاملات حقيقية تبقى.',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final db = DatabaseHelper.instance;
      final dbi = await db.database;

      // 1) كل الرموز في used_codes
      final usedCodes = await dbi.query('used_codes');
      final usedCodesSet =
          usedCodes.map((r) => r['code'] as String).toSet();

      // 2) كل الرموز في transactions
      final txCodes = await dbi.query(
        'transactions',
        columns: ['code'],
        where: 'code IS NOT NULL AND code != ""',
      );
      final txCodesSet =
          txCodes.map((r) => r['code'] as String).toSet();

      // 3) الرموز اليتيمة = في used_codes لكن ليس في transactions
      final orphans = usedCodesSet.difference(txCodesSet);

      // 4) احذفها
      int deleted = 0;
      for (final code in orphans) {
        try {
          await dbi.delete('used_codes',
              where: 'code = ?', whereArgs: [code]);
          deleted++;
        } catch (_) {}
      }

      await LoggerService.log(
        action: '🗑️ مسح الرموز اليتيمة',
        description: 'تم حذف $deleted رمز يتيم',
        level: LogLevel.info,
        category: LogCategory.system,
      );

      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(true, '✅ تم حذف $deleted رمز يتيم');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, 'خطأ: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 تشخيص المعاملات الناقصة (موجودة محلياً وليس في السحابة)
  // ═══════════════════════════════════════════════════════════
  Future<void> _diagnoseMissingTransactions() async {
    setState(() => _busy = true);

    try {
      final db = DatabaseHelper.instance;
      final localTransactions = await db.allTransactionsRaw();

      // قراءة السحابة
      final cloudData = await GDriveService.downloadSyncFile();
      if (cloudData == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showResult(false, '❌ لا توجد بيانات في السحابة');
        return;
      }

      final cloudTransactions =
          (cloudData['transactions'] as List?)?.cast<Map>() ?? [];

      // إنشاء مجموعة من cloud_ids الموجودة في السحابة
      final Set<String> cloudIds = {};
      final Set<String> cloudKeys = {};
      for (final t in cloudTransactions) {
        final cloudId = t['cloud_id'] as String?;
        if (cloudId != null && cloudId.isNotEmpty) {
          cloudIds.add(cloudId);
        }
        final code = t['code'] as String? ?? '';
        final customerId = t['customer_id']?.toString() ?? '';
        final amount = t['amount']?.toString() ?? '';
        final created = t['created_at'] as String? ?? '';
        cloudKeys.add('code_${code}_${customerId}_${amount}_$created');
      }

      // إيجاد المعاملات المحلية الناقصة في السحابة
      final List<Map<String, dynamic>> missing = [];
      for (final t in localTransactions) {
        final cloudId = t['cloud_id'] as String?;
        final isDeleted = t['is_deleted'] == 1;
        final isPermanent = t['is_permanently_deleted'] == 1;

        if (isDeleted == true || isPermanent == true) {
          continue; // تجاهل المحذوفة
        }

        bool foundInCloud = false;
        if (cloudId != null && cloudId.isNotEmpty) {
          foundInCloud = cloudIds.contains(cloudId);
        } else {
          final code = t['code'] as String? ?? '';
          final customerId = t['customer_id']?.toString() ?? '';
          final amount = t['amount']?.toString() ?? '';
          final created = t['created_at'] as String? ?? '';
          foundInCloud = cloudKeys
              .contains('code_${code}_${customerId}_${amount}_$created');
        }

        if (!foundInCloud) {
          missing.add(t);
        }
      }

      if (!mounted) return;
      setState(() => _busy = false);

      // عرض النتيجة
      await _showMissingDialog(missing);
    } catch (e) {
      debugPrint('❌ diagnoseMissingTransactions: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, '❌ خطأ: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 عرض تفاصيل المعاملات الناقصة
  // ═══════════════════════════════════════════════════════════
  Future<void> _showMissingDialog(List<Map<String, dynamic>> missing) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                missing.isEmpty ? Icons.check_circle : Icons.warning_amber,
                color: missing.isEmpty ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  missing.isEmpty
                      ? '✅ لا توجد معاملات ناقصة'
                      : '⚠️ ${missing.length} معاملة ناقصة',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: missing.isEmpty
                ? const Text(
                    'كل المعاملات المحلية موجودة في السحابة.',
                    style: TextStyle(fontSize: 13),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: missing.map((t) {
                        final id = t['id'];
                        final code = t['code'] ?? 'بدون رمز';
                        final amount = t['amount'];
                        final type = t['type'];
                        final cloudId = t['cloud_id'];
                        final customerId = t['customer_id'];
                        final createdAt = t['created_at'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🔹 معاملة #$id',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('• الرمز: $code',
                                  style: const TextStyle(fontSize: 11)),
                              Text('• المبلغ: $amount',
                                  style: const TextStyle(fontSize: 11)),
                              Text('• النوع: $type',
                                  style: const TextStyle(fontSize: 11)),
                              Text(
                                  '• cloud_id: ${cloudId ?? "❌ فارغ"}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cloudId == null
                                        ? Colors.red
                                        : Colors.green,
                                  )),
                              Text('• العميل: #$customerId',
                                  style: const TextStyle(fontSize: 11)),
                              Text('• التاريخ: $createdAt',
                                  style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            if (missing.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _fixMissingTransactions(missing);
                },
                icon: const Icon(Icons.build_circle, size: 16),
                label: const Text('🔧 إصلاح تلقائي'),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 إصلاح المعاملات الناقصة (توليد cloud_id جديد)
  // ═══════════════════════════════════════════════════════════
  Future<void> _fixMissingTransactions(
      List<Map<String, dynamic>> missing) async {
    final confirm = await _confirmDialog(
      title: '🔧 إصلاح المعاملات الناقصة',
      message:
          'سيتم توليد cloud_id جديد لكل معاملة ناقصة (${missing.length} معاملة).\n\n'
          'هذا سيسمح برفعها للسحابة في المزامنة التالية.\n\n'
          '⚠️ لا يمكن التراجع — تأكد أنك عملت نسخة احتياطية.',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final db = DatabaseHelper.instance;
      final dbi = await db.database;
      const uuid = Uuid();

      int fixed = 0;
      for (final t in missing) {
        final id = t['id'] as int?;
        if (id == null) continue;

        try {
          await dbi.update(
            'transactions',
            {
              'cloud_id': uuid.v4(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          fixed++;
        } catch (e) {
          debugPrint('❌ Failed to fix tx $id: $e');
        }
      }

      await LoggerService.log(
        action: '🔧 إصلاح المعاملات الناقصة',
        description:
            'تم توليد cloud_id جديد لـ $fixed معاملة (من ${missing.length})',
        level: LogLevel.info,
        category: LogCategory.system,
      );

      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(
        true,
        '✅ تم إصلاح $fixed معاملة — اضغط "⬆️ رفع" الآن',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, '❌ خطأ: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الإجراءات الأصلية
  // ═══════════════════════════════════════════════════════════

  Future<void> _forceSync() async {
    final confirm = await _confirmDialog(
      title: '🔄 مزامنة كاملة',
      message:
          'سيتم:\n1. قراءة السحابة\n2. حل التعارضات\n3. دمج البيانات\n4. رفع الحالة الكاملة',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final result = await SyncService.forceSync();
      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(result.success, result.message);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, 'خطأ: $e');
    }
  }

  Future<void> _forceUpload() async {
    final confirm = await _confirmDialog(
      title: '⬆️ رفع قسري',
      message:
          'سيتم دمج البيانات المحلية مع السحابة (بدون حذف أي شيء).\n\n'
          '✅ آمن — لا يمسح بيانات الآخرين.',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final ok = await SyncService.forceUpload();
      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(ok, ok ? '✅ تم الرفع' : '❌ فشل الرفع');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, 'خطأ: $e');
    }
  }

  Future<void> _forceDownload() async {
    final confirm = await _confirmDialog(
      title: '⬇️ تنزيل قسري',
      message:
          'سيتم تنزيل البيانات من السحابة ودمجها مع المحلي.\n\n'
          '⚠️ قد يؤدي إلى فقدان بيانات محلية غير مرفوعة.',
    );
    if (!confirm) return;

    setState(() => _busy = true);

    try {
      final result = await SyncService.forceDownload();
      if (!mounted) return;
      setState(() => _busy = false);

      _showResult(result.success, result.message);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showResult(false, 'خطأ: $e');
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message, style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تنفيذ'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  void _showResult(bool success, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تشخيص المزامنة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _load,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildStatusCard(),
                      const SizedBox(height: 12),
                      _buildLocalCard(),
                      const SizedBox(height: 12),
                      _buildCloudCard(),
                      const SizedBox(height: 12),
                      _buildDiffCard(),
                      const SizedBox(height: 16),
                      _buildMainActions(),
                      const SizedBox(height: 16),
                      _buildMaintenanceActions(),
                      const SizedBox(height: 24),
                    ],
                  ),
                  if (_busy)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('جاري التنفيذ...',
                                    style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final signedIn = _data['isSignedIn'] == true;
    return Card(
      color: signedIn
          ? Colors.green.withOpacity(0.1)
          : Colors.red.withOpacity(0.1),
      child: ListTile(
        leading: Icon(
          signedIn ? Icons.cloud_done : Icons.cloud_off,
          color: signedIn ? Colors.green : Colors.red,
          size: 32,
        ),
        title: Text(
          signedIn ? 'متصل بـ Google Drive' : 'غير متصل',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _data['userEmail']?.toString() ?? '—',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildLocalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📱 المحلي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            _row('العملاء', _data['localCustomers']),
            _row('المعاملات', _data['localTransactions']),
            _row('الأحداث', _data['localLogs']),
            _row('الرموز', _data['localCodes']),
            const Divider(),
            _row('عملاء محذوفون', _data['localDeletedCustomers'],
                color: Colors.red),
            _row('معاملات محذوفة', _data['localDeletedTransactions'],
                color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('☁️ السحابة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            _row('العملاء', _data['cloudCustomers']),
            _row('المعاملات', _data['cloudTransactions']),
            _row('الأحداث', _data['cloudLogs']),
            _row('الرموز', _data['cloudCodes']),
            const Divider(),
            _row('عملاء محذوفون', _data['cloudDeletedCustomers'],
                color: Colors.red),
            _row('معاملات محذوفة', _data['cloudDeletedTransactions'],
                color: Colors.red),
            const Divider(),
            _rowText('معرف الملف', _data['syncFileId']),
            _rowText('آخر تعديل', _data['lastModified']),
            _rowText('created_at', _data['cloudCreatedAt']),
            _rowText('version', _data['cloudVersion']),
            if (_data['cloudError'] != null)
              _rowText('خطأ', _data['cloudError'], color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffCard() {
    final diffCustomers = (_data['diffCustomers'] as int?) ?? 0;
    final diffTransactions = (_data['diffTransactions'] as int?) ?? 0;
    final diffLogs = (_data['diffLogs'] as int?) ?? 0;
    final diffCodes = (_data['diffCodes'] as int?) ?? 0;

    final hasDiff = diffCustomers != 0 ||
        diffTransactions != 0 ||
        diffLogs != 0 ||
        diffCodes != 0;

    return Card(
      color: hasDiff
          ? Colors.orange.withOpacity(0.15)
          : Colors.green.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasDiff ? Icons.warning_amber : Icons.check_circle,
                  color: hasDiff ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  hasDiff
                      ? '⚠️ فروق بين المحلي والسحابة'
                      : '✅ متطابق',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: hasDiff ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
            const Divider(),
            _row('فرق العملاء', diffCustomers,
                color: diffCustomers != 0 ? Colors.orange : Colors.green),
            _row('فرق المعاملات', diffTransactions,
                color: diffTransactions != 0 ? Colors.orange : Colors.green),
            _row('فرق الأحداث', diffLogs,
                color: diffLogs != 0 ? Colors.orange : Colors.green),
            _row('فرق الرموز', diffCodes,
                color: diffCodes != 0 ? Colors.orange : Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _forceSync,
            icon: const Icon(Icons.sync),
            label: const Text('🔄 مزامنة كاملة (موصى به)'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              minimumSize: const Size(0, 50),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _forceUpload,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('⬆️ رفع'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(0, 50),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _forceDownload,
                icon: const Icon(Icons.cloud_download),
                label: const Text('⬇️ تنزيل'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(0, 50),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMaintenanceActions() {
    return Card(
      color: Colors.orange.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.build, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  '🔧 أدوات الصيانة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'استخدم هذه الأدوات إذا واجهت مشاكل في الرموز أو التكرار',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _fixDuplicateCodes,
                icon: const Icon(Icons.build_circle, color: Colors.orange),
                label: const Text('🔧 إصلاح الرموز المكررة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  minimumSize: const Size(0, 45),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _cleanOrphanCodes,
                icon: const Icon(Icons.cleaning_services, color: Colors.red),
                label: const Text('🗑️ مسح الرموز اليتيمة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(0, 45),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 🆕 زر تشخيص المعاملات الناقصة
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _diagnoseMissingTransactions,
                icon: const Icon(Icons.search, color: Colors.purple),
                label: const Text('🔍 تشخيص المعاملات الناقصة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                  side: const BorderSide(color: Colors.purple),
                  minimumSize: const Size(0, 45),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final json = _data.toString();
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ تم نسخ التقرير')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('نسخ التقرير'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            '${value ?? "—"}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowText(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            '${value ?? "—"}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
