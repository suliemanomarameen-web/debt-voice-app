import 'dart:async';
import 'package:flutter/material.dart';
import '../models/log_event.dart';
import '../services/logger_service.dart';
import '../screens/logs_screen.dart';

/// تبويب السجل — يعرض شارة عدد التنبيهات المعلقة
class LogsTab extends StatefulWidget {
  const LogsTab({super.key});

  static final GlobalKey<LogsTabState> globalKey =
      GlobalKey<LogsTabState>();

  @override
  State<LogsTab> createState() => LogsTabState();
}

class LogsTabState extends State<LogsTab> {
  int _pendingCount = 0;
  StreamSubscription<int>? _pendingSub;
  StreamSubscription<LogEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();

    // الاستماع لعدد التنبيهات
    _pendingSub =
        LoggerService.pendingCountStream.listen((count) {
      if (mounted) setState(() => _pendingCount = count);
    });

    // الاستماع للأحداث الجديدة
    _eventSub = LoggerService.eventStream.listen((_) {
      // لا حاجة لعمل شيء — العدد يُحدَّث عبر pendingCountStream
    });
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPendingCount() async {
    final count = await LoggerService.getPendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  /// 🆕 دالة عامة للتحديث من الخارج
  Future<void> reload() async {
    await _loadPendingCount();
  }

  @override
  Widget build(BuildContext context) {
    return LogsScreen();
  }
}

/// 🆕 أيقونة التبويب مع الشارة
class LogsTabIcon extends StatelessWidget {
  final bool selected;
  const LogsTabIcon({super.key, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: LoggerService.pendingCountStream,
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        if (count == 0) {
          return Icon(
            selected ? Icons.history : Icons.history_outlined,
          );
        }

        return Badge(
          label: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red,
          child: Icon(
            selected ? Icons.history : Icons.history_outlined,
          ),
        );
      },
    );
  }
}
