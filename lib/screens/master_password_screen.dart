import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/crypto_service.dart';
import '../services/logger_service.dart';
import '../models/log_event.dart';

/// شاشة إعداد / تغيير كلمة مرور تشفير المزامنة
class MasterPasswordScreen extends StatefulWidget {
  /// true = تغيير كلمة المرور الحالية
  /// false = إنشاء كلمة مرور لأول مرة
  final bool isChange;

  const MasterPasswordScreen({super.key, this.isChange = false});

  @override
  State<MasterPasswordScreen> createState() => _MasterPasswordScreenState();
}

class _MasterPasswordScreenState extends State<MasterPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _oldCtrl = TextEditingController();

  bool _usePin = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _obscureOld = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _oldCtrl.dispose();
    super.dispose();
  }

  // ========== قوة كلمة المرور ==========
  double _passwordStrength(String pwd) {
    if (pwd.isEmpty) return 0;
    double score = 0;

    if (pwd.length >= 4) score += 0.15;
    if (pwd.length >= 6) score += 0.15;
    if (pwd.length >= 8) score += 0.15;
    if (pwd.length >= 12) score += 0.15;
    if (pwd.length >= 16) score += 0.1;

    if (RegExp(r'[a-z]').hasMatch(pwd)) score += 0.05;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score += 0.05;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score += 0.05;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pwd)) score += 0.05;

    return score.clamp(0.0, 1.0);
  }

  String _strengthLabel(double s) {
    if (s == 0) return '';
    if (s < 0.3) return 'ضعيفة جداً';
    if (s < 0.5) return 'ضعيفة';
    if (s < 0.7) return 'متوسطة';
    if (s < 0.9) return 'قوية';
    return 'قوية جداً';
  }

  Color _strengthColor(double s) {
    if (s < 0.3) return Colors.red;
    if (s < 0.5) return Colors.orange;
    if (s < 0.7) return Colors.amber;
    if (s < 0.9) return Colors.lightGreen;
    return Colors.green;
  }

  // ========== الحفظ ==========
  Future<void> _save() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    try {
      final pwd = _passwordCtrl.text;
      final confirm = _confirmCtrl.text;

      if (pwd.isEmpty) {
        _setError('أدخل كلمة المرور');
        return;
      }

      if (_usePin) {
        if (!RegExp(r'^\d{4,6}$').hasMatch(pwd)) {
          _setError('PIN يجب أن يكون 4-6 أرقام');
          return;
        }
      } else {
        if (pwd.length < 6) {
          _setError('كلمة المرور قصيرة (6 أحرف على الأقل)');
          return;
        }
        if (_passwordStrength(pwd) < 0.3) {
          _setError('كلمة المرور ضعيفة جداً');
          return;
        }
      }

      if (pwd != confirm) {
        _setError('كلمتا المرور غير متطابقتين');
        return;
      }

      if (widget.isChange) {
        final old = await CryptoService.getMasterPassword();
        if (old != _oldCtrl.text) {
          _setError('كلمة المرور الحالية خاطئة');
          return;
        }
      }

      await CryptoService.setMasterPassword(pwd);

      await LoggerService.info(
        widget.isChange
            ? 'تغيير كلمة مرور المزامنة'
            : 'تفعيل تشفير المزامنة',
        widget.isChange
            ? 'تم تغيير كلمة مرور التشفير'
            : 'تم تفعيل تشفير المزامنة لأول مرة',
        category: LogCategory.security,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _setError('خطأ: $e');
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = _passwordStrength(_passwordCtrl.text);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isChange ? 'تغيير كلمة المرور' : 'تفعيل التشفير',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== توضيح =====
            Card(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.isChange
                                ? 'تغيير كلمة المرور'
                                : 'حماية ملف المزامنة',
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
                      widget.isChange
                          ? 'سيتم استبدال كلمة المرور الحالية. '
                              'تذكّر أن كل الأجهزة المرتبطة يجب أن تستخدم الكلمة الجديدة.'
                          : 'كلمة المرور هذه تُشفّر ملف المزامنة على Google Drive. '
                              'بدونها، لا يمكن لأحد (حتى لو فتح Drive) قراءة بياناتك.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ===== تحذير =====
            if (!widget.isChange)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ احفظ كلمة المرور في مكان آمن!\n'
                        'إذا نسيتها، لن تستطيع استعادة البيانات من Drive.',
                        style: TextStyle(fontSize: 11, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

            // ===== اختيار النوع =====
            if (!widget.isChange) ...[
              const Text(
                'اختر نوع الحماية:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('كلمة مرور'),
                    icon: Icon(Icons.password, size: 16),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('PIN'),
                    icon: Icon(Icons.pin, size: 16),
                  ),
                ],
                selected: {_usePin},
                onSelectionChanged: (v) {
                  setState(() {
                    _usePin = v.first;
                    _passwordCtrl.clear();
                    _confirmCtrl.clear();
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // ===== كلمة المرور القديمة =====
            if (widget.isChange) ...[
              TextField(
                controller: _oldCtrl,
                obscureText: _obscureOld,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureOld ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscureOld = !_obscureOld),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ===== كلمة المرور الجديدة =====
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              keyboardType:
                  _usePin ? TextInputType.number : TextInputType.text,
              maxLength: _usePin ? 6 : null,
              onChanged: (_) => setState(() {}),
              inputFormatters: _usePin
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(
                labelText: _usePin ? 'PIN (4-6 أرقام)' : 'كلمة المرور الجديدة',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(_usePin ? Icons.pin : Icons.password),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                counterText: _usePin ? '' : null,
              ),
            ),

            // ===== مؤشر القوة =====
            if (!_usePin && _passwordCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: strength,
                      minHeight: 6,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_strengthColor(strength)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _strengthLabel(strength),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _strengthColor(strength),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // ===== التأكيد =====
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              keyboardType:
                  _usePin ? TextInputType.number : TextInputType.text,
              maxLength: _usePin ? 6 : null,
              inputFormatters: _usePin
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.check),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                counterText: '',
              ),
            ),

            // ===== الخطأ =====
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ===== زر الحفظ =====
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_busy ? 'جاري الحفظ...' : 'حفظ'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _usePin
                  ? 'PIN أسهل في الإدخال لكن أقل أماناً. مناسب للاستخدام السريع.'
                  : 'استخدم مزيجاً من الأحرف والأرقام والرموز لكلمة مرور قوية.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
