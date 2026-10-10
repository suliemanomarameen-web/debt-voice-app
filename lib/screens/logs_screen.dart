import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/log_event.dart';
import '../services/logger_service.dart';
import '../services/audio_recorder_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
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
    // 🆕 إذا لم يوجد مسار صوت → نبه المستخدم
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

    // 🆕 التحقق من وجود الملف فعلياً
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

  // ============================================================
  // ============ البناء ============================
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pendingCount = (_stats['pending'] as int?) ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل الأحداث'),
          actions: [
            if (pendingCount > 0)
              IconButton(
                icon: const Icon(Icons.done_all, color: Colors.green),
                tooltip: 'الاعتراف بالكل ($pendingCount)',
                onPressed: _acknowledgeAll,
              ),
            IconButton(
              icon: const Icon(Icons.auto_delete),
              tooltip: 'مدة الاحتفاظ',
              onPressed: _showRetentionSettings,
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'تصدير CSV',
              onPressed: _exportCsv,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'clear') _clearAll();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('حذف كل السجل',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
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
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
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
            const Divider(height: 1),
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
        ),
      ),
    );
  }

  // ============================================================
  // ============ بطاقة الحدث ============================
  // ============================================================
  Widget _buildLogCard(LogEvent e, ThemeData theme, bool isDark) {
    final levelColor = Color(e.levelColor);
    final needsAck = e.needsAcknowledgement;
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;

    // 🆕 هل هذا حدث صوتي؟ (يظهر زر التشغيل دائماً)
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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

            // ═══ 🆕 الأزرار: يظهر زر التشغيل دائماً للأحداث الصوتية ═══
            if (isVoiceLog || needsAck) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  // 🆕 زر التشغيل (يظهر دائماً لأحداث "صوتي")
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
                  // زر الاعتراف (إذا كان الحدث يحتاج اعترافاً)
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
