import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/log_event.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل الأحداث'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.history),
                text: 'كل الأحداث',
              ),
              Tab(
                icon: Icon(Icons.pending_actions, color: Colors.orange),
                text: '🔴 معلقات صوتية',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _AllLogsTab(theme: theme),
            _PendingVoiceTab(theme: theme),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📑 التبويب 1: كل الأحداث (السلوك الحالي)
// ═══════════════════════════════════════════════════════════════
class _AllLogsTab extends StatefulWidget {
  final ThemeData theme;
  const _AllLogsTab({required this.theme});

  @override
  State<_AllLogsTab> createState() => _AllLogsTabState();
}

class _AllLogsTabState extends State<_AllLogsTab> {
  final _searchCtrl = TextEditingController();
  final _audioService = AudioRecorderService();

  List<LogEvent> _logs = [];
  bool _loading = true;

  LogLevel? _levelFilter;
  LogCategory? _categoryFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';
  bool _onlyPending = false;

  String? _playingPath;

  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadLogs();

    _audioService.isCompletedStream.listen((isCompleted) {
      if (isCompleted && mounted) {
        setState(() => _playingPath = null);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _audioService.stopPlayback();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await LoggerService.getStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);

    final logs = await LoggerService.getLogs(
      level: _levelFilter,
      category: _categoryFilter,
      fromDate: _fromDate,
      toDate: _toDate,
      searchQuery: _searchQuery,
      onlyPending: _onlyPending,
      limit: 500,
    );

    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });

    await _loadStats();
  }

  void _clearFilters() {
    setState(() {
      _levelFilter = null;
      _categoryFilter = null;
      _fromDate = null;
      _toDate = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _onlyPending = false;
    });
    _loadLogs();
  }

  // ============ تشغيل الصوت ============
  Future<void> _togglePlay(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('التسجيل الصوتي غير متوفر لهذا الحدث'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final fileExists = await AudioRecorderService.fileExists(e.audioPath!);
    if (!fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ الملف الصوتي غير موجود'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (_playingPath == e.audioPath) {
      await _audioService.stopPlayback();
      if (mounted) setState(() => _playingPath = null);
      return;
    }

    final ok = await _audioService.play(e.audioPath!);
    if (!mounted) return;

    if (ok) {
      setState(() => _playingPath = e.audioPath);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ فشل تشغيل التسجيل'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============ الاعتراف ============
  Future<void> _acknowledge(LogEvent e) async {
    if (e.id == null) return;
    final ok = await LoggerService.acknowledge(e.id!);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم الاعتراف بالتنبيه'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      _loadLogs();
    }
  }

  Future<void> _acknowledgeAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.done_all, color: Colors.green),
              SizedBox(width: 8),
              Text('الاعتراف بالكل'),
            ],
          ),
          content: const Text(
            'سيتم إيقاف كل التنبيهات المعلقة.\n\n'
            'الأحداث نفسها لن تُحذف — فقط تُعتبر "تمت مراجعتها".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    final count = await LoggerService.acknowledgeAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم الاعتراف بـ $count حدث'),
        backgroundColor: Colors.green,
      ),
    );
    _loadLogs();
  }

  // ============ حذف ============
  Future<void> _deleteLog(LogEvent e) async {
    if (e.id == null) return;
    await LoggerService.deleteLog(e.id!);
    if (e.audioPath != null) {
      await AudioRecorderService.deleteFile(e.audioPath!);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ تم حذف الحدث'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    _loadLogs();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف كل السجل'),
            ],
          ),
          content: const Text(
            '⚠️ سيتم حذف كل الأحداث نهائياً.\n\n'
            'لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الكل'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    await LoggerService.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ تم حذف كل السجل'),
          backgroundColor: Colors.red,
        ),
      );
    }
    _loadLogs();
  }

  // ============ فلتر التاريخ ============
  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    _loadLogs();
  }

  // ============ تصدير CSV ============
  Future<void> _exportCsv() async {
    try {
      if (_logs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد أحداث للتصدير')),
        );
        return;
      }

      final sb = StringBuffer();
      sb.writeln(
          'التاريخ,المستوى,الفئة,الإجراء,الوصف,المحاسب,معرّف مرتبط,مسار الصوت,تم الاعتراف');
      for (final e in _logs) {
        sb.writeln([
          e.createdAt,
          e.levelLabel,
          e.categoryLabel,
          _csvEscape(e.action),
          _csvEscape(e.description),
          _csvEscape(e.accountant ?? ''),
          _csvEscape(e.relatedId ?? ''),
          e.audioPath ?? '',
          e.isAcknowledged ? 'نعم' : 'لا',
        ].join(','));
      }

      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/logs_${DateTime.now().millisecondsSinceEpoch}.csv');
      await f.writeAsString('\uFEFF${sb.toString()}');

      await Share.shareXFiles([XFile(f.path)], text: 'سجل الأحداث');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصدير: $e')),
        );
      }
    }
  }

  String _csvEscape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  // ============ حوار إعدادات الاحتفاظ ============
  Future<void> _showRetentionSettings() async {
    final current = await AudioRecorderService.getRetentionDays();
    if (!mounted) return;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_delete, color: Colors.blue),
              SizedBox(width: 8),
              Text('مدة الاحتفاظ'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يتم حذف التسجيلات الصوتية الأقدم من المدة المحددة تلقائياً.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              RadioListTile<int>(
                value: 7,
                groupValue: current,
                title: const Text('7 أيام'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              RadioListTile<int>(
                value: 30,
                groupValue: current,
                title: const Text('30 يوم'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              RadioListTile<int>(
                value: 90,
                groupValue: current,
                title: const Text('90 يوم'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
              RadioListTile<int>(
                value: 0,
                groupValue: current,
                title: const Text('لا تحذف تلقائياً'),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await AudioRecorderService.setRetentionDays(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم حفظ الإعداد'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d - $h:$min';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final pendingCount = (_stats['pending'] as int?) ?? 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: _statCard(
                  'الإجمالي',
                  (_stats['total'] as int?) ?? 0,
                  Colors.blue,
                  isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _statCard(
                  'اليوم',
                  (_stats['today'] as int?) ?? 0,
                  Colors.purple,
                  isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _statCard(
                  'أخطاء',
                  (_stats['errors'] as int?) ?? 0,
                  Colors.red,
                  isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _statCard(
                  'معلقة',
                  pendingCount,
                  Colors.orange,
                  isDark,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'ابحث في الأحداث...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                        _loadLogs();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v);
              _loadLogs();
            },
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilterChip(
                avatar: pendingCount > 0
                    ? CircleAvatar(
                        backgroundColor: Colors.orange,
                        radius: 8,
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                label: const Text('المعلقة'),
                selected: _onlyPending,
                onSelected: (v) {
                  setState(() => _onlyPending = v);
                  _loadLogs();
                },
              ),
              const SizedBox(width: 6),
              ...LogCategory.values.map((cat) {
                final selected = _categoryFilter == cat;
                final label = _categoryLabel(cat);
                final emoji = _categoryEmoji(cat);
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilterChip(
                    label: Text('$emoji $label'),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _categoryFilter = selected ? null : cat;
                      });
                      _loadLogs();
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<LogLevel?>(
                  value: _levelFilter,
                  decoration: const InputDecoration(
                    labelText: 'المستوى',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<LogLevel?>(
                      value: null,
                      child: Text('الكل'),
                    ),
                    ...LogLevel.values.map((l) => DropdownMenuItem<LogLevel?>(
                          value: l,
                          child: Text(_levelLabel(l)),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() => _levelFilter = v);
                    _loadLogs();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                icon: const Icon(Icons.calendar_today, size: 18),
                tooltip: _fromDate == null
                    ? 'من تاريخ'
                    : 'من: ${_fromDate!.year}/${_fromDate!.month}/${_fromDate!.day}',
                onPressed: () => _pickDate(isFrom: true),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.event, size: 18),
                tooltip: _toDate == null
                    ? 'إلى تاريخ'
                    : 'إلى: ${_toDate!.year}/${_toDate!.month}/${_toDate!.day}',
                onPressed: () => _pickDate(isFrom: false),
              ),
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: 'مسح الفلاتر',
                onPressed: _clearFilters,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox,
                              size: 64, color: theme.disabledColor),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد أحداث',
                            style: TextStyle(
                                color: theme.disabledColor, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadLogs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) =>
                            _buildLogCard(_logs[i], theme, isDark),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildLogCard(LogEvent e, ThemeData theme, bool isDark) {
    final levelColor = Color(e.levelColor);
    final needsAck = e.needsAcknowledgement;
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;

    final isVoiceLog = e.category == LogCategory.voice;
    final hasAudio = e.audioPath != null && e.audioPath!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: needsAck ? Colors.orange.withOpacity(0.06) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: levelColor.withOpacity(0.4), width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.levelEmoji,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 3),
                      Text(
                        e.levelLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: levelColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${e.categoryEmoji} ${e.categoryLabel}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(e.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              e.action,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              e.description,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if ((e.accountant != null && e.accountant!.isNotEmpty) ||
                (e.relatedId != null && e.relatedId!.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (e.accountant != null && e.accountant!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person,
                              size: 10, color: Colors.teal),
                          const SizedBox(width: 3),
                          Text(
                            e.accountant!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (e.relatedId != null && e.relatedId!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${e.relatedId}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (isVoiceLog || needsAck) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (isVoiceLog)
                    OutlinedButton.icon(
                      onPressed: () => _togglePlay(e),
                      icon: Icon(
                        isPlaying ? Icons.stop : Icons.play_arrow,
                        size: 16,
                        color: hasAudio ? null : Colors.grey,
                      ),
                      label: Text(
                        isPlaying
                            ? 'إيقاف'
                            : (hasAudio ? 'تشغيل' : 'لا يوجد صوت'),
                        style: TextStyle(
                          fontSize: 12,
                          color: hasAudio ? null : Colors.grey,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 32),
                        side: BorderSide(
                          color: hasAudio
                              ? theme.colorScheme.outline
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  if (isVoiceLog && needsAck) const SizedBox(width: 8),
                  if (needsAck)
                    FilledButton.icon(
                      onPressed: () => _acknowledge(e),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'تم التصحيح',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'حذف',
                    color: Colors.red,
                    onPressed: () => _deleteLog(e),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'حذف',
                    color: Colors.red,
                    onPressed: () => _deleteLog(e),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, int value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _levelLabel(LogLevel l) {
    switch (l) {
      case LogLevel.info:
        return 'معلومة';
      case LogLevel.success:
        return 'نجاح';
      case LogLevel.warning:
        return 'تحذير';
      case LogLevel.error:
        return 'خطأ';
    }
  }

  String _categoryLabel(LogCategory c) {
    switch (c) {
      case LogCategory.transaction:
        return 'عمليات';
      case LogCategory.sync:
        return 'مزامنة';
      case LogCategory.backup:
        return 'نسخ';
      case LogCategory.customer:
        return 'عملاء';
      case LogCategory.settings:
        return 'إعدادات';
      case LogCategory.voice:
        return 'صوتي';
      case LogCategory.security:
        return 'أمان';
      case LogCategory.code:
        return 'رموز';
      case LogCategory.system:
        return 'نظام';
    }
  }

  String _categoryEmoji(LogCategory c) {
    switch (c) {
      case LogCategory.transaction:
        return '💰';
      case LogCategory.sync:
        return '☁️';
      case LogCategory.backup:
        return '💾';
      case LogCategory.customer:
        return '👤';
      case LogCategory.settings:
        return '⚙️';
      case LogCategory.voice:
        return '🎤';
      case LogCategory.security:
        return '🔒';
      case LogCategory.code:
        return '🔢';
      case LogCategory.system:
        return '📱';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 📑 التبويب 2: التسجيلات المعلّقة (جديد)
// ═══════════════════════════════════════════════════════════════
class _PendingVoiceTab extends StatefulWidget {
  final ThemeData theme;
  const _PendingVoiceTab({required this.theme});

  @override
  State<_PendingVoiceTab> createState() => _PendingVoiceTabState();
}

class _PendingVoiceTabState extends State<_PendingVoiceTab> {
  final _audioService = AudioRecorderService();

  List<LogEvent> _pending = [];
  bool _loading = true;
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _load();
    _audioService.isCompletedStream.listen((isCompleted) {
      if (isCompleted && mounted) {
        setState(() => _playingPath = null);
      }
    });
  }

  @override
  void dispose() {
    _audioService.stopPlayback();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final list = await LoggerService.getPendingVoiceLogs();
    if (!mounted) return;
    setState(() {
      _pending = list;
      _loading = false;
    });
  }

  Future<void> _togglePlay(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التسجيل الصوتي غير متوفر'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final exists = await AudioRecorderService.fileExists(e.audioPath!);
    if (!exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ الملف الصوتي غير موجود'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_playingPath == e.audioPath) {
      await _audioService.stopPlayback();
      if (mounted) setState(() => _playingPath = null);
      return;
    }

    final ok = await _audioService.play(e.audioPath!);
    if (!mounted) return;
    if (ok) {
      setState(() => _playingPath = e.audioPath);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 فتح نافذة "إضافة عملية" مع ملء تلقائي
  // ═══════════════════════════════════════════════════════════
  Future<void> _openAddDialog(LogEvent e) async {
    // استخراج partial parse من metadata
    Map<String, dynamic>? partial;
    try {
      final meta = e.metadataMap;
      if (meta != null && meta['partial'] is Map) {
        partial = Map<String, dynamic>.from(meta['partial'] as Map);
      }
    } catch (_) {}

    // استخراج نص خام
    String rawText = '';
    try {
      final meta = e.metadataMap;
      if (meta != null) {
        rawText = (meta['raw_text'] as String?) ?? '';
      }
    } catch (_) {}
    if (rawText.isEmpty && e.description.contains('"')) {
      final m = RegExp(r'"([^"]+)"').firstMatch(e.description);
      if (m != null) rawText = m.group(1) ?? '';
    }

    // القيم الافتراضية
    String selectedType = 'debt';
    if (partial != null) {
      final t = partial['intent'] as String? ?? 'debt';
      if (t == 'payment' || t == 'debt' || t == 'return') {
        selectedType = t;
      }
    }

    Customer? selectedCustomer;
    if (partial != null) {
      final name = partial['customerName'] as String? ?? '';
      if (name.isNotEmpty) {
        final db = DatabaseHelper.instance;
        final exact = await db.findExactCustomer(name);
        if (exact != null) {
          selectedCustomer = exact;
        } else {
          final matches = await db.findCustomersContaining(name);
          if (matches.length == 1) selectedCustomer = matches.first;
        }
      }
    }

    final amountCtrl = TextEditingController(
      text: partial != null && (partial['amount'] ?? 0) > 0
          ? (partial['amount'] as num).toStringAsFixed(0)
          : '',
    );
    final itemsCtrl = TextEditingController(
      text: (partial?['items'] as String?) ?? '',
    );
    final searchCtrl = TextEditingController(
      text: selectedCustomer?.name ?? '',
    );

    final db = DatabaseHelper.instance;
    final customers = await db.activeCustomers();
    if (!mounted) return;

    List<Customer> filtered = List.from(customers);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.add_card, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(child: Text('إضافة عملية')),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '🔴 من تسجيل معلّق',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // نص التسجيل الأصلي
                    if (rawText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme_bg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'النص: "$rawText"',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // نوع العملية
                    const Text(
                      'نوع العملية:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'debt',
                          label: _SegmentLabel('دين', Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: 'payment',
                          label: _SegmentLabel('سداد', Icons.payments),
                        ),
                        ButtonSegment(
                          value: 'return',
                          label:
                              _SegmentLabel('مرتجع', Icons.keyboard_return),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (v) {
                        setStateDialog(() => selectedType = v.first);
                      },
                    ),

                    const Divider(height: 24),

                    // العميل
                    const Text(
                      'العميل:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (selectedCustomer != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.teal, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                selectedCustomer!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setStateDialog(() {
                                  selectedCustomer = null;
                                  searchCtrl.clear();
                                  filtered = List.from(customers);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (selectedCustomer == null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          setStateDialog(() {
                            filtered = customers
                                .where((c) => c.name.contains(v.trim()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: Text('لا توجد نتائج',
                                      style: TextStyle(color: Colors.grey)),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor:
                                          Theme.of(ctx).colorScheme.primary,
                                      child: Text(
                                        c.name.characters.first,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11),
                                      ),
                                    ),
                                    title: Text(c.name,
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    onTap: () {
                                      setStateDialog(() {
                                        selectedCustomer = c;
                                        searchCtrl.text = c.name;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],

                    const Divider(height: 24),

                    // المبلغ
                    const Text(
                      'المبلغ:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'أدخل المبلغ',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // الأصناف / البيان
                    Text(
                      selectedType == 'payment' ? 'البيان:' : 'الأصناف:',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: itemsCtrl,
                      decoration: InputDecoration(
                        hintText: selectedType == 'payment'
                            ? 'مثال: دفعة...'
                            : 'مثال: رز، شاي...',
                        prefixIcon: Icon(
                          selectedType == 'payment'
                              ? Icons.description_outlined
                              : Icons.inventory_2_outlined,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (selectedCustomer == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('اختر عميلاً'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        final amt = double.tryParse(amountCtrl.text);
                        if (amt == null || amt <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('أدخل مبلغاً صحيحاً'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);

                        try {
                          final storedType =
                              (selectedType == 'return') ? 'payment' : selectedType;

                          final isDuplicate =
                              await db.transactionExistsRecent(
                            customerId: selectedCustomer!.id!,
                            amount: amt,
                            type: storedType,
                            window: const Duration(seconds: 30),
                          );

                          if (isDuplicate) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('⚠️ العملية مسجلة بالفعل'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            setStateDialog(() => isSaving = false);
                            return;
                          }

                          String? code;
                          try {
                            code = await CodeService.generateCode(selectedType);
                          } catch (_) {}

                          final accountant =
                              await AccountantService.getAccountantName();

                          String extraText;
                          if (selectedType == 'payment') {
                            extraText = itemsCtrl.text.trim();
                          } else if (selectedType == 'return') {
                            extraText = itemsCtrl.text.trim().isEmpty
                                ? 'مرتجع'
                                : 'مرتجع: ${itemsCtrl.text.trim()}';
                          } else {
                            extraText = itemsCtrl.text.trim();
                          }

                          await db.insertTransaction(Transaction(
                            customerId: selectedCustomer!.id!,
                            code: code,
                            accountant: accountant,
                            source: 'voice',
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          // تسجيل الحدث (نجاح)
                          final typeLabel = {
                            'debt': 'دين',
                            'payment': 'سداد',
                            'return': 'مرتجع',
                          }[selectedType]!;

                          await LoggerService.logTransactionAdded(
                            typeLabel: typeLabel,
                            customerName: selectedCustomer!.name,
                            amount: amt,
                            currency: 'YER',
                            code: code,
                            accountant: accountant,
                            source: 'voice',
                          );

                          // 🆕 تعليم التسجيل المعلّق بأنه تم
                          if (e.id != null) {
                            await LoggerService.acknowledge(e.id!);
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '✅ تم تسجيل $typeLabel بقيمة ${amt.toStringAsFixed(0)} ريال'),
                              backgroundColor: Colors.green,
                            ),
                          );

                          await _load();
                        } finally {
                          if (mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color theme_bg(BuildContext ctx) {
    return Theme.of(ctx).colorScheme.surfaceContainerHighest;
  }

  Future<void> _discard(LogEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('تجاهل التسجيل؟'),
            ],
          ),
          content: const Text(
            'سيتم حذف التسجيل المعلّق نهائياً.\n\n'
            'يمكنك الاحتفاظ به إذا كنت تريد مراجعته لاحقاً.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تجاهل وحذف'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (e.id != null) {
      await LoggerService.deleteLog(e.id!);
      if (e.audioPath != null) {
        await AudioRecorderService.deleteFile(e.audioPath!);
      }
    }
    await _load();
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 80, color: Colors.green.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'لا توجد تسجيلات معلّقة',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'كل التسجيلات تمت مراجعتها 🎉',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _pending.length,
        itemBuilder: (_, i) => _buildCard(_pending[i], theme),
      ),
    );
  }

  Widget _buildCard(LogEvent e, ThemeData theme) {
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;
    final hasAudio = e.audioPath != null && e.audioPath!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      color: Colors.orange.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.orange.withOpacity(0.4), width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('⚠️', style: TextStyle(fontSize: 12)),
                      SizedBox(width: 3),
                      Text(
                        'معلّق',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDateTime(e.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              e.action,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              e.description,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (e.accountant != null && e.accountant!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 10, color: Colors.teal),
                    const SizedBox(width: 3),
                    Text(
                      e.accountant!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // أزرار
            Row(
              children: [
                // تشغيل الصوت
                OutlinedButton.icon(
                  onPressed: hasAudio ? () => _togglePlay(e) : null,
                  icon: Icon(
                    isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 16,
                    color: hasAudio ? null : Colors.grey,
                  ),
                  label: Text(
                    isPlaying
                        ? 'إيقاف'
                        : (hasAudio ? 'تشغيل' : 'لا يوجد صوت'),
                    style: TextStyle(
                      fontSize: 12,
                      color: hasAudio ? null : Colors.grey,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 36),
                  ),
                ),
                const SizedBox(width: 8),
                // إضافة عملية
                FilledButton.icon(
                  onPressed: () => _openAddDialog(e),
                  icon: const Icon(Icons.add_card, size: 16),
                  label: const Text('إضافة عملية',
                      style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 36),
                  ),
                ),
                const Spacer(),
                // تجاهل
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'تجاهل',
                  color: Colors.red,
                  onPressed: () => _discard(e),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 🆕 Widget مساعد للـ SegmentedButton
// ═══════════════════════════════════════════════════════════════
class _SegmentLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SegmentLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Icon(icon, size: 16),
        ],
      ),
    );
  }
}
