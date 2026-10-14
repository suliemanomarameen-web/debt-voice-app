import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/recovery_service.dart';

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
          _showRecovery = false;
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

  void _openRecovery() {
    setState(() {
      _showRecovery = true;
      _error = null;
      _passwordCtrl.clear();
    });
  }

  void _closeRecovery() {
    setState(() {
      _showRecovery = false;
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
            child: _showRecovery
                ? _RecoveryOptions(
                    onSuccess: () {
                      setState(() {
                        _unlocked = true;
                        _showRecovery = false;
                      });
                    },
                    onBack: _closeRecovery,
                  )
                : _buildLock(),
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
                icon:
                    Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
}

// ═══════════════════════════════════════════════════════════════
// 🆕 شاشة الاستعادة (3 خيارات)
// ═══════════════════════════════════════════════════════════════
class _RecoveryOptions extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onBack;

  const _RecoveryOptions({
    required this.onSuccess,
    required this.onBack,
  });

  @override
  State<_RecoveryOptions> createState() => _RecoveryOptionsState();
}

class _RecoveryOptionsState extends State<_RecoveryOptions> {
  int _step = 0; // 0 = قائمة الخيارات، 1 = سؤال، 2 = رمز، 3 = واتساب

  @override
  Widget build(BuildContext context) {
    if (_step == 0) return _buildOptionsList();
    if (_step == 1) return _buildSecurityQuestion();
    if (_step == 2) return _buildRecoveryCodeInput();
    if (_step == 3) return _buildWhatsAppSend();
    return _buildOptionsList();
  }

  // ═══════════════════════════════════════════════════════════
  // 0. قائمة الخيارات
  // ═══════════════════════════════════════════════════════════
  Widget _buildOptionsList() {
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
        const SizedBox(height: 8),
        const Text('اختر طريقة الاستعادة:',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 24),

        // خيار 1: سؤال الأمان
        _recoveryOption(
          icon: Icons.help_outline,
          color: Colors.blue,
          title: 'سؤال الأمان',
          subtitle: 'أجب على السؤال الذي اخترته',
          onTap: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 10),

        // خيار 2: إرسال للواتساب
        _recoveryOption(
          icon: Icons.send,
          color: Colors.green,
          title: 'إرسال الرمز للواتساب',
          subtitle: 'أرسل رمز الاسترداد لهاتفك الآخر',
          onTap: () => setState(() => _step = 3),
        ),
        const SizedBox(height: 10),

        // خيار 3: رمز الاسترداد المحفوظ
        _recoveryOption(
          icon: Icons.vpn_key,
          color: Colors.deepPurple,
          title: 'رمز الاسترداد المحفوظ',
          subtitle: 'أدخل الرمز الذي حفظته عند الإعداد',
          onTap: () => setState(() => _step = 2),
        ),
        const SizedBox(height: 24),

        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
      ],
    );
  }

  Widget _recoveryOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 320,
      child: Card(
        elevation: 1,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: onTap,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 1. سؤال الأمان
  // ═══════════════════════════════════════════════════════════
  Widget _buildSecurityQuestion() {
    return _SecurityQuestionStep(
      onVerified: widget.onSuccess,
      onBack: () => setState(() => _step = 0),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 2. إدخال رمز الاسترداد
  // ═══════════════════════════════════════════════════════════
  Widget _buildRecoveryCodeInput() {
    return _RecoveryCodeStep(
      onVerified: widget.onSuccess,
      onBack: () => setState(() => _step = 0),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 3. إرسال للواتساب
  // ═══════════════════════════════════════════════════════════
  Widget _buildWhatsAppSend() {
    return _WhatsAppSendStep(
      onSuccess: widget.onSuccess,
      onBack: () => setState(() => _step = 0),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// خطوة 1: سؤال الأمان
// ═══════════════════════════════════════════════════════════
class _SecurityQuestionStep extends StatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onBack;

  const _SecurityQuestionStep({
    required this.onVerified,
    required this.onBack,
  });

  @override
  State<_SecurityQuestionStep> createState() =>
      _SecurityQuestionStepState();
}

class _SecurityQuestionStepState extends State<_SecurityQuestionStep> {
  final _answerCtrl = TextEditingController();
  String? _question;
  String? _error;
  bool _verified = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestion();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuestion() async {
    final q = await RecoveryService.getSecurityQuestion();
    if (!mounted) return;
    setState(() {
      _question = q;
      _loading = false;
    });
  }

  Future<void> _verifyAnswer() async {
    final ans = _answerCtrl.text.trim();
    if (ans.isEmpty) {
      setState(() => _error = 'أدخل الإجابة');
      return;
    }

    final ok = await RecoveryService.verifySecurityAnswer(ans);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _verified = true;
        _error = null;
      });
      // الانتقال لخطوة إعادة التعيين
    } else {
      setState(() => _error = 'الإجابة غير صحيحة');
      _answerCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_question == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 60, color: Colors.orange.withOpacity(0.7)),
          const SizedBox(height: 12),
          const Text('لا يوجد سؤال أمان',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('لم يتم إعداد سؤال الأمان',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('رجوع'),
          ),
        ],
      );
    }

    if (_verified) {
      return _ResetPasswordForm(
        onSuccess: widget.onVerified,
        onBack: widget.onBack,
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.help_outline,
            size: 60, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('سؤال الأمان',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),

        // السؤال
        Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Text('السؤال:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Text(
                _question!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // الإجابة
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
              prefixIcon: const Icon(Icons.check),
            ),
            onSubmitted: (_) => _verifyAnswer(),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _verifyAnswer,
          icon: const Icon(Icons.verified_user),
          label: const Text('تحقق'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 48),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// خطوة 2: إدخال رمز الاسترداد
// ═══════════════════════════════════════════════════════════
class _RecoveryCodeStep extends StatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onBack;

  const _RecoveryCodeStep({
    required this.onVerified,
    required this.onBack,
  });

  @override
  State<_RecoveryCodeStep> createState() => _RecoveryCodeStepState();
}

class _RecoveryCodeStepState extends State<_RecoveryCodeStep> {
  final _codeCtrl = TextEditingController();
  String? _error;
  bool _verified = false;
  bool _hasCode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkCode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    final has = await RecoveryService.hasRecoveryCode();
    if (!mounted) return;
    setState(() {
      _hasCode = has;
      _loading = false;
    });
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'أدخل الرمز');
      return;
    }

    final ok = await RecoveryService.verifyRecoveryCode(code);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _verified = true;
        _error = null;
      });
    } else {
      setState(() => _error = 'الرمز غير صحيح');
      _codeCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCode) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 60, color: Colors.orange.withOpacity(0.7)),
          const SizedBox(height: 12),
          const Text('لا يوجد رمز استرداد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('لم يتم إنشاء رمز استرداد',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('رجوع'),
          ),
        ],
      );
    }

    if (_verified) {
      return _ResetPasswordForm(
        onSuccess: widget.onVerified,
        onBack: widget.onBack,
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.vpn_key,
            size: 60, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('رمز الاسترداد',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('أدخل الرمز الذي حفظته عند الإعداد',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),

        SizedBox(
          width: 320,
          child: TextField(
            controller: _codeCtrl,
            textAlign: TextAlign.center,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 18,
              letterSpacing: 2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'XXXX-XXXX-XXXX-XXXX',
              hintStyle: const TextStyle(
                fontSize: 16,
                letterSpacing: 2,
                color: Colors.grey,
              ),
              border: const OutlineInputBorder(),
              errorText: _error,
              prefixIcon: const Icon(Icons.vpn_key),
            ),
            onSubmitted: (_) => _verifyCode(),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _verifyCode,
          icon: const Icon(Icons.verified_user),
          label: const Text('تحقق'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 48),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// خطوة 3: إرسال للواتساب
// ═══════════════════════════════════════════════════════════
class _WhatsAppSendStep extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onBack;

  const _WhatsAppSendStep({
    required this.onSuccess,
    required this.onBack,
  });

  @override
  State<_WhatsAppSendStep> createState() => _WhatsAppSendStepState();
}

class _WhatsAppSendStepState extends State<_WhatsAppSendStep> {
  String? _number;
  bool _hasCode = false;
  bool _loading = true;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasCode = await RecoveryService.hasRecoveryCode();
    final num = await RecoveryService.getWhatsAppNumber();
    if (!mounted) return;
    setState(() {
      _hasCode = hasCode;
      _number = num;
      _loading = false;
    });
  }

  Future<void> _sendViaWhatsApp() async {
    final code = await RecoveryService.getRecoveryCodePlain();
    if (code == null || code.isEmpty) return;

    // إذا كان هناك رقم محفوظ → إرسال إليه
    // إذا لا → فتح واتساب عام
    final url = (_number != null && _number!.isNotEmpty)
        ? RecoveryService.buildWhatsAppNumberUrl(
            phoneNumber: _number!,
            recoveryCode: code,
          )
        : RecoveryService.buildWhatsAppRecoveryUrl(recoveryCode: code);

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        setState(() => _sent = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    }
  }

  Future<void> _copyCode() async {
    final code = await RecoveryService.getRecoveryCodePlain();
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ الرمز'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasCode) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 60, color: Colors.orange.withOpacity(0.7)),
          const SizedBox(height: 12),
          const Text('لا يوجد رمز استرداد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('رجوع'),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.send,
            size: 60, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('إرسال الرمز عبر واتساب',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'سيُفتح واتساب مع رمز الاسترداد\n'
          'أرسله إلى هاتفك الآخر أو احفظه',
          style: TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        if (_number != null && _number!.isNotEmpty)
          Container(
            width: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_android,
                    color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرقم المحفوظ:',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey)),
                      Text(
                        _number!,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_number == null || _number!.isEmpty)
          Container(
            width: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لم يتم حفظ رقم واتساب.\nسيُفتح واتساب لاختيار جهة الاتصال يدوياً.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // زر الإرسال
        SizedBox(
          width: 280,
          height: 48,
          child: FilledButton.icon(
            onPressed: _sendViaWhatsApp,
            icon: const Icon(Icons.send),
            label: Text(_sent ? 'إعادة الإرسال' : 'فتح واتساب'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // زر النسخ
        SizedBox(
          width: 280,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _copyCode,
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('نسخ الرمز يدوياً'),
          ),
        ),

        const SizedBox(height: 24),
        Container(
          width: 320,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'بعد إرسال الرمز لهاتفك الآخر:\n'
                  '1. افتح واتساب على الجهاز الآخر\n'
                  '2. انسخ الرمز من الرسالة\n'
                  '3. ارجع هنا → خيار "رمز الاسترداد المحفوظ"\n'
                  '4. أدخل الرمز',
                  style: TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // بعد الإرسال - زر "لدي الرمز الآن"
        if (_sent)
          SizedBox(
            width: 280,
            height: 44,
            child: FilledButton.icon(
              onPressed: () {
                // نعود لقائمة الخيارات مع فتح خيار الرمز يدوياً
                widget.onBack();
              },
              icon: const Icon(Icons.vpn_key),
              label: const Text('لدي الرمز - أدخله الآن'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurple,
              ),
            ),
          ),

        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// إعادة تعيين كلمة المرور
// ═══════════════════════════════════════════════════════════
class _ResetPasswordForm extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onBack;

  const _ResetPasswordForm({
    required this.onSuccess,
    required this.onBack,
  });

  @override
  State<_ResetPasswordForm> createState() => _ResetPasswordFormState();
}

class _ResetPasswordFormState extends State<_ResetPasswordForm> {
  final _newPwd1 = TextEditingController();
  final _newPwd2 = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void dispose() {
    _newPwd1.dispose();
    _newPwd2.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final p1 = _newPwd1.text.trim();
    final p2 = _newPwd2.text.trim();

    if (p1.length < 4) {
      setState(() => _error = 'كلمة المرور: 4 أرقام على الأقل');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'غير متطابقتين');
      return;
    }

    await AuthService.setPassword(p1);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم تعيين كلمة المرور الجديدة'),
        backgroundColor: Colors.green,
      ),
    );

    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle,
            size: 60, color: Colors.green.shade400),
        const SizedBox(height: 12),
        const Text('✅ تم التحقق',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green)),
        const SizedBox(height: 8),
        const Text('أدخل كلمة المرور الجديدة',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 24),

        SizedBox(
          width: 280,
          child: TextField(
            controller: _newPwd1,
            obscureText: _obscure1,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 20,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure1 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: 280,
          child: TextField(
            controller: _newPwd2,
            obscureText: _obscure2,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 20,
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure2 ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
            onSubmitted: (_) => _reset(),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.save),
          label: const Text('حفظ كلمة المرور'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 48),
          ),
        ),
      ],
    );
  }
}
