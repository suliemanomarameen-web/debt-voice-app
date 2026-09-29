import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LockScreen extends StatefulWidget {
  final Widget child;
  const LockScreen({super.key, required this.child});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _enabled = false;
  bool _checking = true;
  DateTime? _lastPaused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkEnabled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastPaused = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastPaused != null &&
          DateTime.now().difference(_lastPaused!).inSeconds > 30) {
        setState(() => _unlocked = false);
        _checkEnabled();
      }
    }
  }

  Future<void> _checkEnabled() async {
    final enabled = await AuthService.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _checking = false;
    });
    if (enabled && !_unlocked) _unlock();
  }

  Future<void> _unlock() async {
    final ok = await AuthService.authenticate();
    if (!mounted) return;
    if (ok) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_enabled || _unlocked) return widget.child;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 100,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                const Text('التطبيق مقفل',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('افتح ببصمة الإصبع للمتابعة'),
                const SizedBox(height: 30),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('فتح'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
