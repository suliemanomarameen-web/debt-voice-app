import 'dart:convert';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/duplicate_pair.dart';
import '../services/accountant_service.dart';
import '../services/duplicate_resolver.dart';

/// الشاشة الإلزامية لحل التكرارات
///
/// - 🟢 مؤكد: تطابق تام
/// - 🟡 محتمل: بادئة 2+ كلمات
/// - 🟠 تشابه حرفي: Levenshtein=1
/// - ⚪ ضعيف: بادئة كلمة واحدة
///
/// [forceBlock] = true  → لا يمكن الإغلاق إلا بعد حلّ كل التكرارات
///                         (يُستخدم عند الفتح التلقائي من main.dart)
/// [forceBlock] = false → يمكن الإغلاق (يُستخدم عند الفتح من الإعدادات)
class DuplicatesScreen extends StatefulWidget {
  final bool forceBlock;
  const DuplicatesScreen({super.key, this.forceBlock = true});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  final _db = DatabaseHelper.instance;

  List<DuplicatePair> _duplicates = [];
  bool _loading = true;
  bool _resolving = false;
  int? _resolvingId;

  // ═══════════════════════════════════════════════════════════
  // التحميل
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final rows = await _db.getUnresolvedDuplicatesRaw();
      final list = rows.map((r) => DuplicatePair.fromMap(r)).toList();

      // ترتيب: مؤكد → محتمل → تشابه → ضعيف، ثم بحسب درجة التشابه
      list.sort((a, b) {
        final levelOrder = {
          'confirmed': 0,
          'likely': 1,
          'similar': 2,
          'weak': 3,
        };
        final aOrder = levelOrder[a.similarityLevel] ?? 99;
        final bOrder = levelOrder[b.similarityLevel] ?? 99;
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
        return b.similarityScore.compareTo(a.similarityScore);
      });

      if (!mounted) return;
      setState(() {
        _duplicates = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('خطأ في التحميل: $e', Colors.red);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // حلّ تكرار واحد
  // ═══════════════════════════════════════════════════════════

  Future<void> _resolveMerge(DuplicatePair dup) async {
    final keepWhich = await _askKeepWhich(dup);
    if (keepWhich == null) return;

    await _runResolve(
      dup: dup,
      action: () async {
        final by = await _getAccountant();
        return dup.isCustomer
            ? DuplicateResolver.mergeCustomer(
                duplicateId: dup.id!,
                keepWhich: keepWhich,
                by: by,
              )
            : DuplicateResolver.mergeTransaction(
                duplicateId: dup.id!,
                keepWhich: keepWhich,
                by: by,
              );
      },
    );
  }

  Future<void> _resolveRename(DuplicatePair dup) async {
    if (!dup.isCustomer) {
      _snack('لا يمكن إعادة تسمية العمليات', Colors.orange);
      return;
    }

    final metadata = _decodeMetadata(dup.metadata);
    final currentName = (metadata?['cloud_name'] as String?) ?? '';
    final suggested =
        await DuplicateResolver.findAvailableName(currentName);

    if (!mounted) return;
    final newName = await _askName(suggested, currentName);
    if (newName == null || newName.trim().isEmpty) return;

    await _runResolve(
      dup: dup,
      action: () async {
        final by = await _getAccountant();
        return DuplicateResolver.renameCustomer(
          duplicateId: dup.id!,
          newName: newName,
          by: by,
        );
      },
    );
  }

  Future<void> _resolveSkip(DuplicatePair dup) async {
    await _runResolve(
      dup: dup,
      action: () async {
        final by = await _getAccountant();
        return DuplicateResolver.skip(
          duplicateId: dup.id!,
          by: by,
        );
      },
    );
  }

  Future<void> _runResolve({
    required DuplicatePair dup,
    required Future<Map<String, dynamic>> Function() action,
  }) async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _resolvingId = dup.id;
    });

    try {
      final result = await action();
      if (!mounted) return;
      if (result['success'] == true) {
        _snack(result['message'] ?? 'تم', Colors.green);
        await _load();
      } else {
        _snack(result['message'] ?? 'فشل', Colors.red);
      }
    } catch (e) {
      if (mounted) _snack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
          _resolvingId = null;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // حلّ الكل
  // ═══════════════════════════════════════════════════════════

  Future<void> _resolveAllMerge() async {
    final keepWhich = await _askKeepWhich(null);
    if (keepWhich == null) return;
    await _runBulk('merge', keepWhich);
  }

  Future<void> _resolveAllRename() async {
    final ok = await _confirm(
      'إعادة تسمية الكل؟',
      'سيتم إعادة تسمية كل الحسابات المكررة تلقائياً (أحمد → أحمد (2) → ...).',
    );
    if (!ok) return;
    await _runBulk('rename', 'cloud');
  }

  Future<void> _resolveAllSkip() async {
    final ok = await _confirm(
      'تخطي الكل؟',
      'سيتم تأجيل كل التكرارات — ستعود للمراجعة عند المزامنة القادمة.',
    );
    if (!ok) return;
    await _runBulk('skip', 'cloud');
  }

  Future<void> _runBulk(String action, String keepWhich) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final by = await _getAccountant();
      final result = await DuplicateResolver.resolveAll(
        action: action,
        keepWhich: keepWhich,
        by: by,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        _snack(result['message'] ?? 'تم', Colors.green);
        await _load();
      } else {
        _snack(result['message'] ?? 'فشل', Colors.red);
      }
    } catch (e) {
      if (mounted) _snack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الحوارات
  // ═══════════════════════════════════════════════════════════

  Future<String?> _askKeepWhich(DuplicatePair? dup) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.merge_type, color: Colors.blue),
              SizedBox(width: 8),
              Text('أي نسخة تبقى؟'),
            ],
          ),
          content: const Text(
            'سيتم الاحتفاظ بنسخة واحدة ودمج الأخرى.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'local'),
              icon: const Icon(Icons.phone_android, size: 16),
              label: const Text('المحلية'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cloud'),
              icon: const Icon(Icons.cloud, size: 16),
              label: const Text('السحابية'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(String suggested, String current) async {
    final ctrl = TextEditingController(text: suggested);
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text('إعادة تسمية'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الاسم الحالي: $current',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الاسم الجديد',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final r = await showDialog<bool>(
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
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
    return r == true;
  }

  // ═══════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════

  Future<String?> _getAccountant() async {
    try {
      return await AccountantService.getAccountantName();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeMetadata(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  /// هل يمكن إغلاق الشاشة؟
  ///
  /// - إذا [forceBlock] = false → نعم (فتح يدوي من الإعدادات)
  /// - إذا [forceBlock] = true  → فقط عندما لا توجد تكرارات
  bool get _canPop {
    if (!widget.forceBlock) return true;
    if (_loading) return true;
    return _duplicates.isEmpty;
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // تجميع بحسب المستوى
    final grouped = <String, List<DuplicatePair>>{
      'confirmed': [],
      'likely': [],
      'similar': [],
      'weak': [],
    };
    for (final dup in _duplicates) {
      grouped[dup.similarityLevel]?.add(dup);
    }

    final pending = _duplicates.where((d) => d.isPending).length;
    final skipped = _duplicates.where((d) => d.isSkipped).length;
    final total = _duplicates.length;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _duplicates.isNotEmpty) {
          _snack('يجب حل التكرارات أولاً', Colors.orange);
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('🔀 تكرارات تحتاج مراجعة'),
            automaticallyImplyLeading: false,
            actions: [
              // زر الإغلاق يظهر فقط عندما لا يوجد إلزام أو لا توجد تكرارات
              if (!widget.forceBlock || _duplicates.isEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, true),
                ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _duplicates.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(
                      theme: theme,
                      grouped: grouped,
                      pending: pending,
                      skipped: skipped,
                      total: total,
                    ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              '✅ لا توجد تكرارات',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك الآن متابعة المزامنة',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.sync),
              label: const Text('متابعة'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required ThemeData theme,
    required Map<String, List<DuplicatePair>> grouped,
    required int pending,
    required int skipped,
    required int total,
  }) {
    return Column(
      children: [
        _buildHeader(pending: pending, skipped: skipped, total: total),
        _buildBulkActions(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (grouped['confirmed']!.isNotEmpty) ...[
                _buildSectionHeader(
                  emoji: '🟢',
                  title: 'تكرار مؤكد',
                  count: grouped['confirmed']!.length,
                  color: Colors.green,
                  subtitle: 'تطابق تام — يجب الحل',
                ),
                ...grouped['confirmed']!.map((d) => _buildCard(d)),
              ],
              if (grouped['likely']!.isNotEmpty) ...[
                _buildSectionHeader(
                  emoji: '🟡',
                  title: 'تشابه محتمل',
                  count: grouped['likely']!.length,
                  color: Colors.amber.shade800,
                  subtitle: 'اسم مشترك + اسم أب',
                ),
                ...grouped['likely']!.map((d) => _buildCard(d)),
              ],
              if (grouped['similar']!.isNotEmpty) ...[
                _buildSectionHeader(
                  emoji: '🟠',
                  title: 'تشابه حرفي',
                  count: grouped['similar']!.length,
                  color: Colors.orange,
                  subtitle: 'حرف واحد مختلف',
                ),
                ...grouped['similar']!.map((d) => _buildCard(d)),
              ],
              if (grouped['weak']!.isNotEmpty) ...[
                _buildSectionHeader(
                  emoji: '⚪',
                  title: 'تشابه ضعيف',
                  count: grouped['weak']!.length,
                  color: Colors.grey,
                  subtitle: 'كلمة واحدة فقط',
                ),
                ...grouped['weak']!.map((d) => _buildCard(d)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({
    required int pending,
    required int skipped,
    required int total,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.orange.withOpacity(0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'لا يمكن المزامنة حتى تحلّها',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatChip('المجموع', total, Colors.blue),
              const SizedBox(width: 6),
              _buildStatChip('قيد الانتظار', pending, Colors.orange),
              const SizedBox(width: 6),
              _buildStatChip('مؤجلة', skipped, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBulkActions() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: _resolving ? null : _resolveAllMerge,
              icon: const Icon(Icons.merge, size: 16),
              label: const Text('دمج الكل',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _resolving ? null : _resolveAllRename,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('إعادة تسمية الكل',
                  style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: _resolving ? null : _resolveAllSkip,
              icon: const Icon(Icons.skip_next, size: 16),
              label: const Text('تخطي الكل',
                  style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String emoji,
    required String title,
    required int count,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($count)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(DuplicatePair dup) {
    final theme = Theme.of(context);
    final meta = _decodeMetadata(dup.metadata);
    final localName = (meta?['local_name'] as String?) ?? '';
    final cloudName = (meta?['cloud_name'] as String?) ?? '';
    final localPhone = (meta?['local_phone'] as String?) ?? '';
    final cloudPhone = (meta?['cloud_phone'] as String?) ?? '';
    final code = (meta?['code'] as String?) ?? '';
    final amount = meta?['amount'];
    final txType = (meta?['type'] as String?) ?? '';

    final isResolving = _resolvingId == dup.id;
    final isSkipped = dup.isSkipped;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isSkipped
          ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الرأس
            Row(
              children: [
                Text(dup.typeEmoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dup.isCustomer ? 'حساب: $cloudName' : 'عملية: $code',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isSkipped)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'مؤجل',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // المقارنة (جانب إلى جانب)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSide(
                      title: 'محلي',
                      icon: Icons.phone_android,
                      color: Colors.teal,
                      value: dup.isCustomer
                          ? localName
                          : (amount is num
                              ? '${amount.toStringAsFixed(0)} $txType'
                              : ''),
                      subtitle: dup.isCustomer
                          ? (localPhone.isNotEmpty ? localPhone : '—')
                          : '',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: theme.dividerColor,
                  ),
                  Expanded(
                    child: _buildSide(
                      title: 'سحابي',
                      icon: Icons.cloud,
                      color: Colors.blue,
                      value: dup.isCustomer
                          ? cloudName
                          : (amount is num
                              ? '${amount.toStringAsFixed(0)} $txType'
                              : ''),
                      subtitle: dup.isCustomer
                          ? (cloudPhone.isNotEmpty ? cloudPhone : '—')
                          : '',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // الأزرار
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _resolving || isResolving
                        ? null
                        : () => _resolveMerge(dup),
                    icon: isResolving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.merge, size: 16),
                    label: const Text('دمج',
                        style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                    ),
                  ),
                ),
                if (dup.isCustomer) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _resolving || isResolving
                          ? null
                          : () => _resolveRename(dup),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('تسمية',
                          style: TextStyle(fontSize: 11)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 34),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resolving || isResolving
                        ? null
                        : () => _resolveSkip(dup),
                    icon: const Icon(Icons.skip_next, size: 16),
                    label: const Text('تخطي',
                        style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 34),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSide({
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// Duplicates Screen v1: الشاشة الإلزامية لحل التكرارات (المرحلة 3)
// Duplicates Screen v1.1: إضافة forceBlock للسماح بالإغلاق عند الفتح اليدوي من الإعدادات (المرحلة 5)
