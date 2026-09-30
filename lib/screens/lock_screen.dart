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
  bool _obscure = true;
  bool _showRecovery = false;
  DateTime? _lastPaused;
  final _passwordCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  String? _error;
  String? _securityQuestion;
  final _newPwd1 = TextEditingController();
  final _newPwd2 = TextEditingController();
  bool _recoveryVerified = false;

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
    _answerCtrl.dispose();
    _newPwd1.dispose();
    _newPwd2.dispose();
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
          _showRecovery = false;
          _recoveryVerified = false;
          _passwordCtrl.clear();
          _answerCtrl.clear();
          _newPwd1.clear();
          _newPwd2.clear();
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _enabled = false;
          _checking = false;
        });
      }
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

  Future<void> _openRecovery() async {
    final q = await AuthService.getSecurityQuestion();
    if (q == null) {
      setState(() => _error = 'لا يوجد سؤال أمان. اتصل بالمسؤول.');
      return;
    }
    setState(() {
      _showRecovery = true;
      _recoveryVerified = false;
      _securityQuestion = q;
      _error = null;
      _answerCtrl.clear();
      _newPwd1.clear();
      _newPwd2.clear();
    });
  }

  Future<void> _verifyAnswer() async {
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) {
      setState(() => _error = 'أدخل الإجابة');
      return;
    }
    final ok = await AuthService.verifySecurityAnswer(ans);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _recoveryVerified = true;
        _error = null;
      });
    } else {
      setState(() => _error = 'الإجابة غير صحيحة');
      _answerCtrl.clear();
    }
  }

  Future<void> _resetPassword() async {
    final p1 = _newPwd1.text.trim();
    final p2 = _newPwd2.text.trim();
    if (p1.length < 4) {
      setState(() => _error = 'على الأقل 4 أرقام');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    await AuthService.setPassword(p1);
    if (!mounted) return;
    setState(() {
      _unlocked = true;
      _showRecovery = false;
      _recoveryVerified = false;
      _error = null;
    });
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
            child: _showRecovery ? _buildRecovery() : _buildLock(),
          ),
        ),
      ),
    );
  }

  // ============ شاشة القفل ============
  Widget _buildLock() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline,
          size: 100,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        const Text('التطبيق مقفل',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('أدخل كلمة المرور للمتابعة',
            style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 30),
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
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 48),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _openRecovery,
          icon: const Icon(Icons.help_outline),
          label: const Text('نسيت كلمة المرور؟'),
        ),
      ],
    );
  }

  // ============ شاشة الاستعادة ============
  Widget _buildRecovery() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_reset,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        const Text('استعادة كلمة المرور',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),

        if (!_recoveryVerified) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text('سؤال الأمان:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_securityQuestion ?? ''),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _answerCtrl,
              textAlign: TextAlign.center,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'الإجابة',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _verifyAnswer(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _verifyAnswer,
            icon: const Icon(Icons.check),
            label: const Text('تحقق'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(220, 48),
            ),
          ),
        ] else ...[
          const Text('✅ الإجابة صحيحة — أدخل كلمة المرور الجديدة',
              style: TextStyle(color: Colors.green)),
          const SizedBox(height: 20),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _newPwd1,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 20,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 280,
            child: TextField(
              controller: _newPwd2,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: const OutlineInputBorder(),
                counterText: '',
                errorText: _error,
              ),
              onSubmitted: (_) => _resetPassword(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _resetPassword,
            icon: const Icon(Icons.save),
            label: const Text('حفظ كلمة المرور'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(220, 48),
            ),
          ),
        ],

        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _showRecovery = false;
              _recoveryVerified = false;
              _error = null;
              _answerCtrl.clear();
              _newPwd1.clear();
              _newPwd2.clear();
            });
          },
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
      ],
    );
  }
}
