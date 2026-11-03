import 'dart:io';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/pending_notification.dart';
import '../services/audio_recorder_service.dart';
import '../services/notification_action_handler.dart';
import '../services/pending_notification_service.dart';

/// شاشة الإشعارات داخل التطبيق
///
/// 4 تبويبات:
/// - الكل
/// - معلقة (تحتاج إجراءً)
/// - محفوظة
/// - ملغية/منتهية
class NotificationsScreen extends StatefulWidget {
  /// إذا مُرِّر، يُبرَز هذا الإشعار (اختياري)
  final int? highlightId;

  const NotificationsScreen({super.key, this.highlightId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _audioService = AudioRecorderService();

  List<PendingNotification> _allNotifications = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  // فلاتر
  String? _matchTypeFilter;
  String _searchQuery = '';

  // حالة التشغيل الصوتي
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _load();

    _audioService.isCompletedStream.listen((isCompleted) {
      if (isCompleted && mounted) {
        setState(() => _playingPath = null);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioService.stopPlayback();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // تحميل البيانات
  // ═══════════════════════════════════════════════════════════

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final all = await PendingNotificationService.getAll();
      final stats = await PendingNotificationService.getStats();

      if (!mounted) return;
      setState(() {
        _allNotifications = all;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [NotificationsScreen] load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الفلترة
  // ═══════════════════════════════════════════════════════════

  List<PendingNotification> _filteredList() {
    var list = _allNotifications;

    // 1. فلتر التبويب
    switch (_tabController.index) {
      case 0: // الكل
        break;
      case 1: // معلقة
        list = list.where((n) => n.isPending).toList();
        break;
      case 2: // محفوظة
        list = list.where((n) => n.isSaved).toList();
        break;
      case 3: // ملغية/منتهية
        list = list
            .where((n) => n.isCancelled || n.isDismissed || n.isExpired)
            .toList();
        break;
    }

    // 2. فلتر النوع
    if (_matchTypeFilter != null) {
      list = list.where((n) => n.matchType == _matchTypeFilter).toList();
    }

    // 3. البحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((n) {
        final text = (n.text ?? '').toLowerCase();
        final custName = (n.customerName ?? '').toLowerCase();
        final matchedName = (n.matchedCustomerName ?? '').toLowerCase();
        return text.contains(q) ||
            custName.contains(q) ||
            matchedName.contains(q);
      }).toList();
    }

    return list;
  }

  // ═══════════════════════════════════════════════════════════
  // الإجراءات
  // ═══════════════════════════════════════════════════════════

  Future<void> _saveSingle(PendingNotification n) async {
    if (n.id == null || n.matchedCustomerId == null) return;

    final confirmed = await _confirm(
      'حفظ العملية؟',
      'سيتم حفظ العملية على حساب "${n.matchedCustomerName ?? ""}".',
    );
    if (confirmed != true) return;

    final result = await NotificationActionHandler.saveToCustomer(
      notificationId: n.id!,
      customerId: n.matchedCustomerId!,
    );

    if (!mounted) return;
    _snack(
      result['message'] as String? ?? 'تم',
      result['success'] == true ? Colors.green : Colors.red,
    );
    await _load();
  }

  Future<void> _chooseAndSave(PendingNotification n) async {
    if (n.id == null) return;
    if (n.candidates.isEmpty) {
      _snack('لا توجد حسابات مرشحة', Colors.orange);
      return;
    }

    final selected = await _showCandidatePicker(n);
    if (selected == null) return;

    final confirmed = await _confirm(
      'حفظ العملية؟',
      'سيتم حفظ العملية على حساب "${selected['name']}".',
    );
    if (confirmed != true) return;

    final result = await NotificationActionHandler.saveToCustomer(
      notificationId: n.id!,
      customerId: selected['id'] as int,
    );

    if (!mounted) return;
    _snack(
      result['message'] as String? ?? 'تم',
      result['success'] == true ? Colors.green : Colors.red,
    );
    await _load();
  }

  Future<Map<String, dynamic>?> _showCandidatePicker(
      PendingNotification n) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.person_search, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'اختر الحساب (${n.candidates.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: n.candidates.length,
                  itemBuilder: (_, i) {
                    final c = n.candidates[i];
                    final name = (c['name'] as String?) ?? '';
                    final phone = (c['phone'] as String?) ?? '';
                    final accountType =
                        (c['account_type'] as String?) ?? 'customer';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          name.isNotEmpty ? name.characters.first : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: phone.isNotEmpty
                          ? Text(phone,
                              style: const TextStyle(fontSize: 11))
                          : Text(
                              _accountTypeLabel(accountType),
                              style: const TextStyle(fontSize: 11),
                            ),
                      trailing:
                          const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(PendingNotification n) async {
    if (n.id == null) return;

    final confirmed = await _confirm(
      'إلغاء الإشعار؟',
      'لن تُحفظ العملية. سيُسجَّل الإلغاء في السجل.',
    );
    if (confirmed != true) return;

    await PendingNotificationService.markCancelled(n.id!);
    if (!mounted) return;
    _snack('تم إلغاء الإشعار', Colors.orange);
    await _load();
  }

  Future<void> _dismiss(PendingNotification n) async {
    if (n.id == null) return;

    await PendingNotificationService.markDismissed(n.id!);
    if (!mounted) return;
    _snack('تم التمييز كمقروءة', Colors.blue);
    await _load();
  }

  Future<void> _delete(PendingNotification n) async {
    if (n.id == null) return;

    final confirmed = await _confirm(
      'حذف الإشعار؟',
      'سيُحذف الإشعار نهائياً من السجل (لا يمكن التراجع).',
      destructive: true,
    );
    if (confirmed != true) return;

    await PendingNotificationService.delete(n.id!);
    if (!mounted) return;
    _snack('تم حذف الإشعار', Colors.red);
    await _load();
  }

  Future<void> _play(PendingNotification n) async {
    if (n.audioPath == null || n.audioPath!.isEmpty) {
      _snack('لا يوجد تسجيل صوتي', Colors.orange);
      return;
    }

    final exists = await AudioRecorderService.fileExists(n.audioPath!);
    if (!exists) {
      _snack('❌ ملف الصوت غير موجود', Colors.red);
      return;
    }

    if (_playingPath == n.audioPath) {
      await _audioService.stopPlayback();
      if (mounted) setState(() => _playingPath = null);
      return;
    }

    final ok = await _audioService.play(n.audioPath!);
    if (!mounted) return;
    if (ok) {
      setState(() => _playingPath = n.audioPath);
    } else {
      _snack('فشل التشغيل', Colors.red);
    }
  }

  Future<void> _createAccount(PendingNotification n) async {
    if (n.customerName == null || n.customerName!.isEmpty) {
      _snack('اسم العميل غير معروف', Colors.orange);
      return;
    }

    final confirmed = await _confirm(
      'إنشاء حساب؟',
      'سيُإنشاء حساب باسم "${n.customerName}" ثم تُحفظ العملية عليه.',
    );
    if (confirmed != true) return;

    try {
      final db = DatabaseHelper.instance;

      // تحقق: ربما أُنشئ الحساب بالفعل
      final existing = await db.findExactCustomer(n.customerName!);
      int customerId;
      if (existing != null) {
        customerId = existing.id!;
      } else {
        customerId = await db.insertCustomer(Customer(
          name: n.customerName!,
          accountType: n.accountType ?? 'customer',
          createdAt: DateTime.now().toIso8601String(),
        ));
      }

      if (n.id == null) return;

      final result = await NotificationActionHandler.saveToCustomer(
        notificationId: n.id!,
        customerId: customerId,
      );

      if (!mounted) return;
      _snack(
        result['message'] as String? ?? 'تم',
        result['success'] == true ? Colors.green : Colors.red,
      );
      await _load();
    } catch (e) {
      debugPrint('❌ [createAccount] error: $e');
      if (mounted) _snack('خطأ: $e', Colors.red);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // أدوات مساعدة
  // ═══════════════════════════════════════════════════════════

  Future<bool?> _confirm(String title, String message,
      {bool destructive = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                destructive ? Icons.warning_amber : Icons.check_circle,
                color: destructive ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: destructive ? Colors.red : Colors.blue,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(destructive ? 'حذف' : 'تأكيد'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  String _accountTypeLabel(String t) {
    return {
          'customer': 'عميل',
          'supplier': 'مورد',
          'other': 'أخرى',
        }[t] ??
        'عميل';
  }

  String _formatDateTime(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d $h:$min';
    } catch (_) {
      return iso;
    }
  }

  String _relativeTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ثانية';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
      if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
      return _formatDateTime(iso);
    } catch (_) {
      return '';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الواجهة
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الإشعارات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _load,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: [
              Tab(text: 'الكل (${_allNotifications.length})'),
              Tab(text: 'معلقة (${_stats['pending'] ?? 0})'),
              Tab(text: 'محفوظة (${_stats['saved'] ?? 0})'),
              Tab(
                  text:
                      'ملغية (${(_stats['cancelled'] ?? 0) + (_stats['dismissed'] ?? 0) + (_stats['expired'] ?? 0)})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildStatsBar(),
                  _buildFilterChips(),
                  _buildSearchBar(),
                  const Divider(height: 1),
                  Expanded(child: _buildList()),
                ],
              ),
      ),
    );
  }

  Widget _buildStatsBar() {
    final cancelled = (_stats['cancelled'] ?? 0) +
        (_stats['dismissed'] ?? 0) +
        (_stats['expired'] ?? 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          _statChip('معلقة', _stats['pending'] ?? 0, Colors.orange),
          const SizedBox(width: 6),
          _statChip('محفوظة', _stats['saved'] ?? 0, Colors.green),
          const SizedBox(width: 6),
          _statChip('ملغية', cancelled, Colors.grey),
          const SizedBox(width: 6),
          _statChip('الكل', _stats['total'] ?? 0, Colors.blue),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = <MapEntry<String?, String>>[
      const MapEntry(null, 'الكل'),
      const MapEntry('single', '🟢 حساب واحد'),
      const MapEntry('multiple', '🟡 أكثر من حساب'),
      const MapEntry('unclear', '⚪ غير مفهوم'),
      const MapEntry('no_account', '🟠 لا يوجد حساب'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: filters.map((f) {
          final selected = _matchTypeFilter == f.key;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: FilterChip(
              label: Text(
                f.value,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : null,
                ),
              ),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _matchTypeFilter = f.key;
                });
              },
              selectedColor: Colors.blue,
              checkmarkColor: Colors.white,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'ابحث بالاسم أو النص...',
          hintStyle: const TextStyle(fontSize: 12),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (v) {
          setState(() => _searchQuery = v.trim());
        },
      ),
    );
  }

  Widget _buildList() {
    final list = _filteredList();

    if (list.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: list.length,
        itemBuilder: (_, i) => _NotificationCard(
          notification: list[i],
          isPlaying: _playingPath == list[i].audioPath,
          isHighlighted: widget.highlightId == list[i].id,
          onSave: () => _saveSingle(list[i]),
          onChoose: () => _chooseAndSave(list[i]),
          onCancel: () => _cancel(list[i]),
          onDismiss: () => _dismiss(list[i]),
          onDelete: () => _delete(list[i]),
          onPlay: () => _play(list[i]),
          onCreateAccount: () => _createAccount(list[i]),
          relativeTime: _relativeTime(list[i].createdAt),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final tabIndex = _tabController.index;
    String message;
    switch (tabIndex) {
      case 1:
        message = 'لا توجد إشعارات معلقة';
        break;
      case 2:
        message = 'لا توجد إشعارات محفوظة';
        break;
      case 3:
        message = 'لا توجد إشعارات ملغية';
        break;
      default:
        message = 'لا توجد إشعارات';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ستظهر هنا الإشعارات الصوتية',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// بطاقة إشعار واحدة
// ═══════════════════════════════════════════════════════════

class _NotificationCard extends StatelessWidget {
  final PendingNotification notification;
  final bool isPlaying;
  final bool isHighlighted;
  final VoidCallback onSave;
  final VoidCallback onChoose;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final VoidCallback onDelete;
  final VoidCallback onPlay;
  final VoidCallback onCreateAccount;
  final String relativeTime;

  const _NotificationCard({
    required this.notification,
    required this.isPlaying,
    required this.isHighlighted,
    required this.onSave,
    required this.onChoose,
    required this.onCancel,
    required this.onDismiss,
    required this.onDelete,
    required this.onPlay,
    required this.onCreateAccount,
    required this.relativeTime,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final theme = Theme.of(context);
    final matchColor = Color(n.matchTypeColor);
    final statusColor = Color(n.statusColor);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isHighlighted
          ? matchColor.withOpacity(0.1)
          : (n.isPending ? null : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الرأس: أيقونة النوع + العنوان + الوقت
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: matchColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    n.matchTypeEmoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(n),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            relativeTime,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              n.statusLabel,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // الوصف / التفاصيل
            if (n.text != null && n.text!.isNotEmpty && n.isUnclear)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  n.text!,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            if (n.isNoAccount)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'لا يوجد حساب باسم "${n.customerName ?? ""}"',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // الأزرار
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  String _title(PendingNotification n) {
    switch (n.matchType) {
      case 'single':
        return '${n.intentLabel} ${(n.amount ?? 0).toStringAsFixed(0)} ${n.currency} — ${n.matchedCustomerName ?? ""}';
      case 'multiple':
        return '${n.intentLabel} ${(n.amount ?? 0).toStringAsFixed(0)} ${n.currency} — "${n.customerName ?? ""}"';
      case 'unclear':
        return 'تسجيل صوتي غير مفهوم';
      case 'no_account':
        return '${n.intentLabel} ${(n.amount ?? 0).toStringAsFixed(0)} ${n.currency} — "${n.customerName ?? ""}"';
      default:
        return 'إشعار';
    }
  }

  Widget _buildActions(BuildContext context) {
    final n = notification;

    // ─── pending + single ───
    if (n.isPending && n.isSingle) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('حفظ', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('إلغاء', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _deleteButton(),
        ],
      );
    }

    // ─── pending + multiple ───
    if (n.isPending && n.isMultiple) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.person_search, size: 16),
              label: const Text('حدد الحساب',
                  style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('إلغاء', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _deleteButton(),
        ],
      );
    }

    // ─── pending + unclear ───
    if (n.isPending && n.isUnclear) {
      return Row(
        children: [
          if (n.audioPath != null && n.audioPath!.isNotEmpty) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPlay,
                icon: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  isPlaying ? 'إيقاف' : 'تشغيل',
                  style: const TextStyle(fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 34),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: onDismiss,
              icon: const Icon(Icons.done, size: 16),
              label: const Text('تمييز', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _deleteButton(),
        ],
      );
    }

    // ─── pending + no_account ───
    if (n.isPending && n.isNoAccount) {
      return Row(
        children: [
          if (n.audioPath != null && n.audioPath!.isNotEmpty)
            _miniActionButton(
              icon: isPlaying ? Icons.stop : Icons.play_arrow,
              color: Colors.blue,
              onTap: onPlay,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: FilledButton.icon(
              onPressed: onCreateAccount,
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('إنشاء حساب',
                  style: TextStyle(fontSize: 10)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDismiss,
              icon: const Icon(Icons.done, size: 16),
              label: const Text('تمييز', style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 34),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _deleteButton(),
        ],
      );
    }

    // ─── محلول (saved/cancelled/dismissed/expired) ───
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (n.audioPath != null && n.audioPath!.isNotEmpty && !n.isSaved)
          _miniActionButton(
            icon: isPlaying ? Icons.stop : Icons.play_arrow,
            color: Colors.blue,
            onTap: onPlay,
          ),
        const SizedBox(width: 4),
        _deleteButton(),
      ],
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _deleteButton() {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onDelete,
        tooltip: 'حذف',
      ),
    );
  }
}

// Notifications Screen v1: شاشة عرض الإشعارات (4 تبويبات: الكل/معلقة/محفوظة/ملغية) + إجراءات كاملة
