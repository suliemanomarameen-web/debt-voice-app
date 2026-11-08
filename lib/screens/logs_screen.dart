import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/log_event.dart';
import '../services/audio_recorder_service.dart';
import '../services/logger_service.dart';

class LogsScreen extends StatefulWidget {
  /// 🆕 فلتر أولي (مثلاً LogCategory.developer من وضع المطور)
  final LogCategory? initialCategory;

  const LogsScreen({super.key, this.initialCategory});

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
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
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
          title: Text(widget.initialCategory == LogCategory.developer
              ? '🔧 سجل المطور'
              : 'سجل الأحداث'),
          titleTextStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
          toolbarHeight: 44,
          bottom: TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            tabs: const [
              Tab(
                height: 40,
                icon: Icon(Icons.history, size: 18),
                text: 'كل الأحداث',
              ),
              Tab(
                height: 40,
                icon: Icon(Icons.pending_actions,
                    size: 18, color: Colors.orange),
                text: '🔴 معلقات',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _AllLogsTab(
                theme: theme,
                initialCategory: widget.initialCategory),
            _PendingVoiceTab(theme: theme),
          ],
        ),
      ),
    );
  }
}

class _AllLogsTab extends StatefulWidget {
  final ThemeData theme;
  final LogCategory? initialCategory;

  const _AllLogsTab({required this.theme, this.initialCategory});

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
    _categoryFilter = widget.initialCategory;
    _loadStats();
    _loadLogs();

    _audioService.isCompletedStream.listen((isCompleted) {
      if (isCompleted && mounted) setState(() => _playingPath = null);
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
      _categoryFilter = widget.initialCategory;
      _fromDate = null;
      _toDate = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _onlyPending = false;
    });
    _loadLogs();
  }

  Future<void> _togglePlay(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) {
      if (mounted) _snack('التسجيل الصوتي غير متوفر', Colors.orange);
      return;
    }
    final exists = await AudioRecorderService.fileExists(e.audioPath!);
    if (!exists) {
      if (mounted) _snack('❌ الملف الصوتي غير موجود', Colors.red);
      return;
    }
    if (_playingPath == e.audioPath) {
      await _audioService.stopPlayback();
      if (mounted) setState(() => _playingPath = null);
      return;
    }
    final ok = await _audioService.play(e.audioPath!);
    if (!mounted) return;
    if (ok) setState(() => _playingPath = e.audioPath);
  }

  Future<void> _acknowledge(LogEvent e) async {
    if (e.id == null) return;
    final ok = await LoggerService.acknowledge(e.id!);
    if (!mounted) return;
    if (ok) {
      _snack('✅ تم الاعتراف', Colors.green);
      _loadLogs();
    }
  }

  Future<void> _deleteLog(LogEvent e) async {
    if (e.id == null) return;
    await LoggerService.deleteLog(e.id!);
    if (e.audioPath != null) {
      await AudioRecorderService.deleteFile(e.audioPath!);
    }
    _loadLogs();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate =
            DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    _loadLogs();
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$d/$m $h:$min';
    } catch (_) {
      return iso;
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 12)),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final pendingCount = (_stats['pending'] as int?) ?? 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: _statCard('الإجمالي',
                    (_stats['total'] as int?) ?? 0, Colors.blue, isDark),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _statCard('اليوم',
                    (_stats['today'] as int?) ?? 0, Colors.purple, isDark),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _statCard('أخطاء',
                    (_stats['errors'] as int?) ?? 0, Colors.red, isDark),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _statCard(
                    'معلقة', pendingCount, Colors.orange, isDark),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'ابحث...',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                        _loadLogs();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v);
              _loadLogs();
            },
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _compactChip(
                label:
                    'المعلقة${pendingCount > 0 ? " ($pendingCount)" : ""}',
                selected: _onlyPending,
                onSelected: (v) {
                  setState(() => _onlyPending = v);
                  _loadLogs();
                },
                color: Colors.orange,
              ),
              const SizedBox(width: 4),
              ...LogCategory.values.map((cat) {
                final selected = _categoryFilter == cat;
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _compactChip(
                    label:
                        '${_categoryEmoji(cat)} ${_categoryLabel(cat)}',
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 32,
                  child: DropdownButtonFormField<LogLevel?>(
                    value: _levelFilter,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: 'المستوى',
                      labelStyle: TextStyle(fontSize: 10),
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                    ),
                    items: [
                      const DropdownMenuItem<LogLevel?>(
                        value: null,
                        child: Text('الكل',
                            style: TextStyle(fontSize: 11)),
                      ),
                      ...LogLevel.values.map(
                          (l) => DropdownMenuItem<LogLevel?>(
                                value: l,
                                child: Text(_levelLabel(l),
                                    style: const TextStyle(
                                        fontSize: 11)),
                              )),
                    ],
                    onChanged: (v) {
                      setState(() => _levelFilter = v);
                      _loadLogs();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _compactIconButton(
                icon: Icons.calendar_today,
                tooltip: _fromDate == null
                    ? 'من'
                    : 'من: ${_fromDate!.day}/${_fromDate!.month}',
                onPressed: () => _pickDate(isFrom: true),
                active: _fromDate != null,
              ),
              const SizedBox(width: 2),
              _compactIconButton(
                icon: Icons.event,
                tooltip: _toDate == null
                    ? 'إلى'
                    : 'إلى: ${_toDate!.day}/${_toDate!.month}',
                onPressed: () => _pickDate(isFrom: false),
                active: _toDate != null,
              ),
              const SizedBox(width: 2),
              _compactIconButton(
                icon: Icons.clear_all,
                tooltip: 'مسح',
                onPressed: _clearFilters,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
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
                              size: 40,
                              color: theme.disabledColor),
                          const SizedBox(height: 6),
                          Text('لا توجد أحداث',
                              style: TextStyle(
                                  color: theme.disabledColor,
                                  fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadLogs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(4),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) =>
                            _buildCompactCard(_logs[i], theme, isDark),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(LogEvent e, ThemeData theme, bool isDark) {
    final levelColor = Color(e.levelColor);
    final needsAck = e.isPendingAck;
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;
    final isVoiceLog = e.category == LogCategory.voice;
    final isDeveloper = e.category == LogCategory.developer;
    final hasAudio = e.audioPath != null && e.audioPath!.isNotEmpty;

    Color? bgColor;
    if (isDeveloper) {
      bgColor = Colors.purple.withOpacity(0.06);
    } else if (e.isDeletionConflict) {
      bgColor = Colors.red.withOpacity(0.08);
    } else if (e.isRemoteActivity) {
      bgColor = Colors.purple.withOpacity(0.06);
    } else if (e.isSyncConflict || e.isSyncFailure) {
      bgColor = Colors.orange.withOpacity(0.08);
    } else if (needsAck) {
      bgColor = Colors.orange.withOpacity(0.06);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _formatDateTime(e.createdAt),
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${e.categoryEmoji} ${e.categoryLabel}',
                    style: TextStyle(
                      fontSize: 8,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: levelColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(e.levelEmoji,
                      style: const TextStyle(fontSize: 9)),
                ),
                if (e.isDeletionConflict)
                  Container(
                    margin: const EdgeInsets.only(right: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('⚠️ حذف',
                        style: TextStyle(
                            fontSize: 8,
                            color: Colors.red,
                            fontWeight: FontWeight.bold)),
                  ),
                if (e.isRemoteActivity)
                  Container(
                    margin: const EdgeInsets.only(right: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('📡 جهاز آخر',
                        style: TextStyle(
                            fontSize: 8,
                            color: Colors.purple,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                if (e.accountant != null && e.accountant!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '👤 ${e.accountant}',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.action,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _miniIconButton(
                  icon: Icons.delete_outline,
                  color: Colors.red,
                  onPressed: () => _deleteLog(e),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.description.replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: isDeveloper ? 5 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                if (isVoiceLog)
                  _miniIconButton(
                    icon: isPlaying ? Icons.stop : Icons.play_arrow,
                    color: hasAudio ? Colors.green : Colors.grey,
                    onPressed: hasAudio ? () => _togglePlay(e) : null,
                  ),
                if (needsAck)
                  _miniIconButton(
                    icon: Icons.check_circle,
                    color: Colors.green,
                    onPressed: () => _acknowledge(e),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, int value, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 8,
                  color: isDark ? Colors.white70 : Colors.black54)),
          Text('$value',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _compactChip({
    required String label,
    required bool selected,
    required void Function(bool) onSelected,
    Color? color,
  }) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      onSelected: onSelected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      side: color != null
          ? BorderSide(color: color.withOpacity(0.5), width: 0.5)
          : null,
    );
  }

  Widget _compactIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          backgroundColor:
              active ? Colors.blue.withOpacity(0.15) : null,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _miniIconButton({
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onPressed,
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
      case LogCategory.developer:
        return 'مطور';
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
      case LogCategory.developer:
        return '🔧';
      case LogCategory.system:
        return '📱';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// التبويب 2: التسجيلات المعلّقة
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
      if (isCompleted && mounted) setState(() => _playingPath = null);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 50, color: Colors.green.withOpacity(0.5)),
            const SizedBox(height: 10),
            const Text('لا توجد تسجيلات معلّقة',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: _pending.length,
        itemBuilder: (_, i) {
          final e = _pending[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            color: Colors.orange.withOpacity(0.06),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.pending_actions, color: Colors.orange),
              title: Text(e.description,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(e.createdAt,
                  style: const TextStyle(fontSize: 9)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Colors.red),
                onPressed: () async {
                  if (e.id != null) {
                    await LoggerService.deleteLog(e.id!);
                    if (e.audioPath != null) {
                      await AudioRecorderService.deleteFile(e.audioPath!);
                    }
                    await _load();
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// Logs Screen v1: النسخة الأساسية
// Logs Screen v2: قراءة فلاتر المعلقات من الإعدادات
// Logs Screen v3: دعم فئة developer + initialCategory
// - LogCategory.developer في الفلاتر
// - initialCategory: فتح الشاشة مفلترة مسبقاً
// - isDeveloper: وصف بعدة أسطر + لون بنفسجي
