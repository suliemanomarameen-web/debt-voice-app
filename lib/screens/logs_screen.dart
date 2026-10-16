import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/log_event.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/notification_dispatcher.dart';

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
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
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
          title: const Text('سجل الأحداث'),
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
            _AllLogsTab(theme: theme),
            _PendingVoiceTab(theme: theme),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 📑 التبويب 1: كل الأحداث
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

  Future<void> _togglePlay(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('التسجيل الصوتي غير متوفر',
                style: TextStyle(fontSize: 12)),
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
            content: Text('❌ الملف الصوتي غير موجود',
                style: TextStyle(fontSize: 12)),
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
    }
  }

  Future<void> _acknowledge(LogEvent e) async {
    if (e.id == null) return;
    final ok = await LoggerService.acknowledge(e.id!);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('✅ تم الاعتراف', style: TextStyle(fontSize: 11)),
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
              Icon(Icons.done_all, color: Colors.green, size: 20),
              SizedBox(width: 6),
              Text('الاعتراف بالكل',
                  style: TextStyle(fontSize: 15)),
            ],
          ),
          content: const Text(
            'سيتم إيقاف كل التنبيهات المعلقة.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontSize: 12)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد',
                  style: TextStyle(fontSize: 12)),
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
        content: Text('✅ تم الاعتراف بـ $count حدث',
            style: const TextStyle(fontSize: 11)),
        backgroundColor: Colors.green,
      ),
    );
    _loadLogs();
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

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final pendingCount = (_stats['pending'] as int?) ?? 0;

    return Column(
      children: [
        // ===== الإحصائيات المضغوطة =====
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

        // ===== البحث =====
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
                borderRadius: BorderRadius.circular(8),
              ),
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

        // ===== الفلاتر =====
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

        // ===== المستوى + التاريخ =====
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

        // ===== قائمة الأحداث =====
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
                          Text(
                            'لا توجد أحداث',
                            style: TextStyle(
                                color: theme.disabledColor,
                                fontSize: 12),
                          ),
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

  // ═══════════════════════════════════════════════════════════
  // بطاقة الحدث
  // ═══════════════════════════════════════════════════════════
  Widget _buildCompactCard(LogEvent e, ThemeData theme, bool isDark) {
    final levelColor = Color(e.levelColor);
    final needsAck = e.isPendingAck; // ✅ v11
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;
    final isVoiceLog = e.category == LogCategory.voice;
    final hasAudio = e.audioPath != null && e.audioPath!.isNotEmpty;

    // 🆕 تمييز بصري للإشعارات
    Color? bgColor;
    if (e.isDeletionConflict) {
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
            // ===== Row 1: التاريخ + الفئة + المستوى =====
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
                  child: Text(
                    e.levelEmoji,
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
                // 🆕 شارات الحالة
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

            // ===== Row 2: الإجراء + الحذف =====
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

            // ===== Row 3: الوصف + الأزرار =====
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.description.replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                if (isVoiceLog)
                  _miniIconButton(
                    icon: isPlaying ? Icons.stop : Icons.play_arrow,
                    color: hasAudio ? Colors.green : Colors.grey,
                    onPressed:
                        hasAudio ? () => _togglePlay(e) : null,
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

  // ═══════════════════════════════════════════════════════════
  // Widgets مساعدة
  // ═══════════════════════════════════════════════════════════

  Widget _statCard(
      String label, int value, Color color, bool isDark) {
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
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
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
// 📑 التبويب 2: التسجيلات المعلّقة
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

  // 🆕 فلاتر
  bool _filterEmptyVoice = true;
  bool _filterUnclearText = true;

  @override
  void initState() {
    super.initState();
    _loadFilters();
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

  Future<void> _loadFilters() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _filterEmptyVoice = sp.getBool('pending_filter_empty') ?? true;
        _filterUnclearText = sp.getBool('pending_filter_unclear') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final list = await LoggerService.getPendingVoiceLogs();

    // 🆕 فلترة
    final filtered = list.where((e) {
      try {
        final meta = e.metadataMap;
        final rawText = (meta?['raw_text'] as String?) ?? '';

        final isEmpty = rawText.isEmpty ||
            rawText == '(تسجيل صوتي محفوظ - بانتظار المراجعة)';

        if (isEmpty && !_filterEmptyVoice) return false;
        if (!isEmpty && !_filterUnclearText) return false;

        return true;
      } catch (_) {
        return true;
      }
    }).toList();

    if (!mounted) return;
    setState(() {
      _pending = filtered;
      _loading = false;
    });
  }

  Future<void> _togglePlay(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التسجيل الصوتي غير متوفر',
              style: TextStyle(fontSize: 11)),
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
          content: Text('❌ الملف الصوتي غير موجود',
              style: TextStyle(fontSize: 11)),
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

  Future<void> _openAddDialog(LogEvent e) async {
    Map<String, dynamic>? partial;
    try {
      final meta = e.metadataMap;
      if (meta != null && meta['partial'] is Map) {
        partial = Map<String, dynamic>.from(meta['partial'] as Map);
      }
    } catch (_) {}

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
                const Icon(Icons.add_card,
                    color: Colors.teal, size: 20),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('إضافة عملية',
                      style: TextStyle(fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '🔴 معلّق',
                    style: TextStyle(
                      fontSize: 9,
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
                    if (rawText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(6),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'النص: "$rawText"',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // نوع العملية
                    SegmentedButton<String>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 11),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'debt',
                          label: Text('دين'),
                          icon: Icon(Icons.arrow_upward, size: 14),
                        ),
                        ButtonSegment(
                          value: 'payment',
                          label: Text('سداد'),
                          icon: Icon(Icons.payments, size: 14),
                        ),
                        ButtonSegment(
                          value: 'return',
                          label: Text('مرتجع'),
                          icon: Icon(Icons.keyboard_return, size: 14),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (v) {
                        setStateDialog(
                            () => selectedType = v.first);
                      },
                    ),

                    const SizedBox(height: 10),

                    // العميل
                    if (selectedCustomer != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.teal, width: 0.7),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.teal, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                selectedCustomer!.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    size: 14),
                                padding: EdgeInsets.zero,
                                constraints:
                                    const BoxConstraints(),
                                onPressed: () {
                                  setStateDialog(() {
                                    selectedCustomer = null;
                                    searchCtrl.clear();
                                    filtered =
                                        List.from(customers);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (selectedCustomer == null) ...[
                      TextField(
                        controller: searchCtrl,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'ابحث عن عميل...',
                          hintStyle: const TextStyle(fontSize: 11),
                          prefixIcon:
                              const Icon(Icons.search, size: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                        ),
                        onChanged: (v) {
                          setStateDialog(() {
                            filtered = customers
                                .where((c) =>
                                    c.name.contains(v.trim()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints:
                            const BoxConstraints(maxHeight: 120),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: Text('لا توجد نتائج',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey)),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return ListTile(
                                    dense: true,
                                    visualDensity:
                                        VisualDensity.compact,
                                    leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Theme.of(ctx)
                                          .colorScheme
                                          .primary,
                                      child: Text(
                                        c.name.characters.first,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10),
                                      ),
                                    ),
                                    title: Text(c.name,
                                        style: const TextStyle(
                                            fontSize: 12)),
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

                    const SizedBox(height: 8),

                    // المبلغ
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        labelStyle: const TextStyle(fontSize: 11),
                        prefixIcon: const Icon(Icons.attach_money,
                            size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // الأصناف / البيان
                    TextField(
                      controller: itemsCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: selectedType == 'payment'
                            ? 'البيان'
                            : 'الأصناف',
                        labelStyle: const TextStyle(fontSize: 11),
                        hintText: selectedType == 'payment'
                            ? 'مثال: دفعة...'
                            : 'مثال: رز، شاي...',
                        prefixIcon: Icon(
                          selectedType == 'payment'
                              ? Icons.description_outlined
                              : Icons.inventory_2_outlined,
                          size: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء',
                    style: TextStyle(fontSize: 12)),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (selectedCustomer == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('اختر عميلاً',
                                  style: TextStyle(fontSize: 11)),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }
                        final amt = double.tryParse(amountCtrl.text);
                        if (amt == null || amt <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'أدخل مبلغاً صحيحاً',
                                  style: TextStyle(fontSize: 11)),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);

                        try {
                          final storedType =
                              (selectedType == 'return')
                                  ? 'payment'
                                  : selectedType;

                          final isDuplicate = await db
                              .transactionExistsRecent(
                            customerId: selectedCustomer!.id!,
                            amount: amt,
                            type: storedType,
                            window: const Duration(seconds: 30),
                          );

                          if (isDuplicate) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '⚠️ العملية مسجلة بالفعل',
                                    style: TextStyle(
                                        fontSize: 11)),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            setStateDialog(
                                () => isSaving = false);
                            return;
                          }

                          String? code;
                          try {
                            code = await CodeService.generateCode(
                                selectedType);
                          } catch (_) {}

                          final accountant = await AccountantService
                              .getAccountantName();

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

                          const sourceValue = 'voice+manual';

                          await db.insertTransaction(Transaction(
                            customerId: selectedCustomer!.id!,
                            code: code,
                            accountant: accountant,
                            source: sourceValue,
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now()
                                .toIso8601String(),
                          ));

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
                            source: sourceValue,
                          );

                          final newBalance = await db
                              .customerBalance(selectedCustomer!.id!);

                          final normalizedType =
                              CodeService.normalizeType(
                                  selectedType);

                          await NotificationDispatcher
                              .afterTransactionAdded(
                            customerId: selectedCustomer!.id!,
                            customerName: selectedCustomer!.name,
                            phone: selectedCustomer!.phone,
                            type: normalizedType,
                            amount: amt,
                            newBalance: newBalance,
                            source: sourceValue,
                          );

                          if (e.id != null) {
                            await LoggerService.acknowledge(e.id!);
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, true);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '✅ تم تسجيل $typeLabel بقيمة ${amt.toStringAsFixed(0)} ريال',
                                  style: const TextStyle(
                                      fontSize: 11)),
                              backgroundColor: Colors.green,
                            ),
                          );

                          await _load();
                        } finally {
                          if (mounted) {
                            setStateDialog(
                                () => isSaving = false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ',
                    style: const TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _discard(LogEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              SizedBox(width: 6),
              Text('تجاهل التسجيل؟',
                  style: TextStyle(fontSize: 15)),
            ],
          ),
          content: const Text(
            'سيتم حذف التسجيل المعلّق نهائياً.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontSize: 12)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تجاهل',
                  style: TextStyle(fontSize: 12)),
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

  Future<void> _shareVoice(LogEvent e) async {
    if (e.audioPath == null || e.audioPath!.isEmpty) return;
    if (!await AudioRecorderService.fileExists(e.audioPath!)) return;

    try {
      await Share.shareXFiles(
        [XFile(e.audioPath!)],
        text: 'تسجيل صوتي',
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل المشاركة: $err',
              style: const TextStyle(fontSize: 11)),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                size: 50, color: Colors.green.withOpacity(0.5)),
            const SizedBox(height: 10),
            const Text(
              'لا توجد تسجيلات معلّقة',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              'كل التسجيلات تمت مراجعتها 🎉',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: _pending.length,
        itemBuilder: (_, i) => _buildCard(_pending[i], theme),
      ),
    );
  }

  Widget _buildCard(LogEvent e, ThemeData theme) {
    final isPlaying = _playingPath != null && _playingPath == e.audioPath;
    final hasAudio = e.audioPath != null && e.audioPath!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      color: Colors.orange.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '⚠️ معلّق',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(e.createdAt),
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (e.accountant != null && e.accountant!.isNotEmpty)
                  Text(
                    '👤 ${e.accountant}',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 2),

            Text(
              e.description.replaceAll('\n', ' '),
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                if (hasAudio)
                  _miniButton(
                    icon: isPlaying ? Icons.stop : Icons.play_arrow,
                    label: isPlaying ? 'إيقاف' : 'تشغيل',
                    color: Colors.blue,
                    onPressed: () => _togglePlay(e),
                  ),
                const SizedBox(width: 4),
                if (hasAudio)
                  _miniButton(
                    icon: Icons.share,
                    label: 'مشاركة',
                    color: Colors.purple,
                    onPressed: () => _shareVoice(e),
                  ),
                const SizedBox(width: 4),
                _miniButton(
                  icon: Icons.add_card,
                  label: 'إضافة',
                  color: Colors.teal,
                  onPressed: () => _openAddDialog(e),
                  filled: true,
                ),
                const Spacer(),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _discard(e),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    if (filled) {
      return SizedBox(
        height: 28,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 14),
          label:
              Text(label, style: const TextStyle(fontSize: 10)),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 28),
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
    }
    return SizedBox(
      height: 28,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label,
            style: TextStyle(fontSize: 10, color: color)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 28),
          visualDensity: VisualDensity.compact,
          side: BorderSide(
              color: color.withOpacity(0.5), width: 0.7),
        ),
      ),
    );
  }
}
