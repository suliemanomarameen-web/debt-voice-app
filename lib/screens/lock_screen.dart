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
  bool _showPassword = false;
  bool _obscure = true;
  bool _biometricAvailable = true;
  DateTime? _lastPaused;
  final _passwordCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkEnabled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastPaused = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastPaused != null &&
          DateTime.now().difference(_lastPaused!).inSeconds > 30) {
        setState(() {
          _unlocked = false;
          _showPassword = false;
          _passwordCtrl.clear();
          _error = null;
        });
        _checkEnabled();
      }
    }
  }

  Future<void> _checkEnabled() async {
    try {
      final enabled = await AuthService.isEnabled();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _checking = false;
      });
      // ⚠️ لا نستدعي authenticate تلقائياً — نعرض الزر فقط
    } catch (e) {
      if (mounted) {
        setState(() {
          _enabled = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _tryBiometric() async {
    // تأخير بسيط للتأكد من الاستقرار
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final ok = await AuthService.authenticate();
      if (!mounted) return;
      if (ok) {
        setState(() => _unlocked = true);
      } else {
        setState(() => _showPassword = true);
      }
    } catch (e) {
      if (mounted) setState(() => _showPassword = true);
    }
  }

  Future<void> _tryPassword() async {
    final pwd = _passwordCtrl.text.trim();
    if (pwd.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
      return;
    }
    try {
      final ok = await AuthService.verifyPassword(pwd);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _unlocked = true;
          _error = null;
        });
      } else {
        setState(() => _error = 'كلمة المرور غير صحيحة');
        _passwordCtrl.clear();
      }
    } catch (e) {
      setState(() => _error = 'حدث خطأ');
    }
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
          child: SingleChildScrollView(
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
                Text(
                  _showPassword
                      ? 'أدخل كلمة المرور للمتابعة'
                      : 'اختر طريقة الفتح',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 30),

                // ========== وضع البصمة + كلمة المرور ==========
                if (!_showPassword) ...[
                  // زر البصمة — المستخدم يضغط بنفسه
                  FilledButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('افتح ببصمة الإصبع'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showPassword = true;
                        _error = null;
                      });
                    },
                    icon: const Icon(Icons.password),
                    label: const Text('استخدم كلمة المرور'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(220, 48),
                    ),
                  ),
                ],

                // ========== وضع كلمة المرور ==========
                if (_showPassword) ...[
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 20,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        border: const OutlineInputBorder(),
                        counterText: '',
                        errorText: _error,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () {
                            setState(() => _obscure = !_obscure);
                          },
                        ),
                      ),
                      onSubmitted: (_) => _tryPassword(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _tryPassword,
                    icon: const Icon(Icons.login),
                    label: const Text('فتح'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _showPassword = false;
                        _error = null;
                        _passwordCtrl.clear();
                      });
                    },
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('استخدم البصمة'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
