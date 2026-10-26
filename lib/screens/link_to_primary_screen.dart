import 'package:flutter/material.dart';
import '../services/primary_link_service.dart';

class LinkToPrimaryScreen extends StatefulWidget {
  const LinkToPrimaryScreen({super.key});
  @override
  State<LinkToPrimaryScreen> createState() => _LinkToPrimaryScreenState();
}

class _LinkToPrimaryScreenState extends State<LinkToPrimaryScreen> {
  // مراحل الشاشة
  static const int _stepEmail = 0;
  static const int _stepPassword = 1;
  static const int _stepSuccess = 2;
  int _step = _stepEmail;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _linkCodeCtrl = TextEditingController();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _infoMessage;

  // نتيجة النجاح
  String? _successName;
  String? _successCode;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _linkCodeCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // الخطوة 1: التحقق من الملف
  // ═══════════════════════════════════════════════════════════
  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'أدخل إيميلاً صحيحاً');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _infoMessage = null;
    });

    final init = await PrimaryLinkService.requestLinkInit(email);

    if (!mounted) return;

    if (!init.success) {
      setState(() {
        _busy = false;
        _error = init.message;
      });
      return;
    }

    // الملف مشفر → الخطوة 2 (كلمة مرور + رمز ربط)
    if (init.needsPassword) {
      setState(() {
        _busy = false;
        _step = _stepPassword;
      });
      return;
    }

    // الملف غير مشفر → أكمل الربط مباشرة
    if (init.plainData != null) {
      final result = await PrimaryLinkService.completeLink(
        primaryEmail: email,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _busy = false;
          _error = result.message;
        });
        return;
      }

      setState(() {
        _busy = false;
        _step = _stepSuccess;
        _successName = result.accountantName;
        _successCode = result.accountantCode;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // الخطوة 2: كلمة المرور + رمز الربط
  // ═══════════════════════════════════════════════════════════
  Future<void> _submitPasswordAndCode() async {
    final password = _passwordCtrl.text.trim();
    final linkCode = _linkCodeCtrl.text.trim();

    if (password.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
      return;
    }
    if (linkCode.isEmpty) {
      setState(() => _error = 'أدخل رمز الربط');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _infoMessage = null;
    });

    final result = await PrimaryLinkService.completeLink(
      primaryEmail: _emailCtrl.text.trim(),
      password: password,
      linkCode: linkCode,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }

    setState(() {
      _busy = false;
      _step = _stepSuccess;
      _successName = result.accountantName;
      _successCode = result.accountantCode;
    });
  }

  // ═══════════════════════════════════════════════════════════
  // البناء الرئيسي
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_step == _stepSuccess
              ? 'تم الربط'
              : _step == _stepPassword
                  ? 'الخطوة 2 من 2'
                  : 'الخطوة 1 من 2'),
          leading: _step == _stepPassword
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _step = _stepEmail;
                            _error = null;
                            _passwordCtrl.clear();
                            _linkCodeCtrl.clear();
                          });
                        },
                )
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStepIndicator(theme),
            const SizedBox(height: 20),

            if (_step == _stepEmail) ...[
              _buildIntroCard(theme),
              const SizedBox(height: 16),
              _buildPrerequisiteWarning(),
              const SizedBox(height: 20),
              _buildEmailField(),
              const SizedBox(height: 16),
              _buildSubmitButton(
                label: 'متابعة',
                icon: Icons.arrow_forward,
                onPressed: _submitEmail,
              ),
              _buildErrorBox(),
            ],

            if (_step == _stepPassword) ...[
              _buildPasswordInfoCard(theme),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 12),
              _buildLinkCodeField(),
              const SizedBox(height: 16),
              _buildSubmitButton(
                label: 'ربط',
                icon: Icons.link,
                onPressed: _submitPasswordAndCode,
              ),
              _buildErrorBox(),
            ],

            if (_step == _stepSuccess) ...[
              _buildSuccessBox(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('تم'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // المكونات
  // ═══════════════════════════════════════════════════════════

  Widget _buildStepIndicator(ThemeData theme) {
    Widget circle(int n, bool active, bool done) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? Colors.green
              : active
                  ? theme.colorScheme.primary
                  : Colors.grey.shade300,
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text(
                  '$n',
                  style: TextStyle(
                    color: active || done ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      );
    }

    Widget line(bool active) => Container(
          width: 40,
          height: 2,
          color: active ? theme.colorScheme.primary : Colors.grey.shade300,
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        circle(1, _step == _stepEmail, _step == _stepPassword || _step == _stepSuccess),
        line(_step == _stepPassword || _step == _stepSuccess),
        circle(2, _step == _stepPassword, _step == _stepSuccess),
      ],
    );
  }

  Widget _buildIntroCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ربط هذا الجهاز بالمحاسب الأساسي',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'أدخل إيميل المحاسب الأساسي، وسيتم:\n'
              '• تحميل بياناتك (الاسم، الرمز، الصلاحيات)\n'
              '• استيراد إعدادات رموز العمليات\n'
              '• مزامنة كل البيانات المشتركة',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordInfoCard(ThemeData theme) {
    return Card(
      color: Colors.amber.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lock, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'الملف مشفر',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'حماية لبياناتك، ملف المزامنة مشفّر بكلمة مرور الأساسي.\n\n'
              'اطلب من الأساسي إرسال:\n'
              '1. كلمة مرور التشفير\n'
              '2. رمز الربط (من الإعدادات ← 🔐 تشفير المزامنة)',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrerequisiteWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'قبل الربط، تأكد أن الأساسي:\n'
              '1. أضاف إيميلك كـ "محاسب جديد"\n'
              '2. ضغط "مزامنة" بعد الإضافة',
              style: TextStyle(fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: 'إيميل المحاسب الأساسي',
        hintText: 'example@gmail.com',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.email),
        errorText: _error,
      ),
      onSubmitted: (_) => _submitEmail(),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordCtrl,
      obscureText: _obscurePassword,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: 'كلمة مرور التشفير',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildLinkCodeField() {
    return TextField(
      controller: _linkCodeCtrl,
      enabled: !_busy,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        letterSpacing: 1,
      ),
      decoration: const InputDecoration(
        labelText: 'رمز الربط',
        hintText: 'LK1-xxxxxxxxxxxxxxxxxxxxxx-xxxxxxxx',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.vpn_key),
        helperText: 'من الأساسي: الإعدادات ← 🔐 تشفير المزامنة',
      ),
    );
  }

  Widget _buildSubmitButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(_busy ? 'جاري المعالجة...' : label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
      ),
    );
  }

  Widget _buildErrorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 12),
          const Text(
            'تم الربط بنجاح!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'مرحباً ${_successName ?? ""}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if ((_successCode ?? '').isNotEmpty)
            Text(
              'رمزك: ${_successCode}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          const SizedBox(height: 16),
          const Text(
            'سيتم الآن مزامنة بياناتك تلقائياً',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
