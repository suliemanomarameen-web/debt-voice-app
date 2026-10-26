import 'package:flutter/material.dart';
import '../services/primary_link_service.dart';

class LinkToPrimaryScreen extends StatefulWidget {
  const LinkToPrimaryScreen({super.key});
  @override
  State<LinkToPrimaryScreen> createState() => _LinkToPrimaryScreenState();
}

class _LinkToPrimaryScreenState extends State<LinkToPrimaryScreen> {
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  LinkResult? _successResult;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'أدخل إيميلاً صحيحاً');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _successResult = null;
    });

    final result = await PrimaryLinkService.linkToPrimary(email);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _successResult = result;
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('🔗 ربط بالجهاز الأساسي')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== شرح =====
            Card(
              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, color: theme.colorScheme.primary,
                            size: 28),
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
            ),

            const SizedBox(height: 16),

            // ===== التحذير =====
            Container(
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
            ),

            const SizedBox(height: 20),

            // ===== حقل الإيميل =====
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              enabled: !_busy && _successResult == null,
              decoration: InputDecoration(
                labelText: 'إيميل المحاسب الأساسي',
                hintText: 'example@gmail.com',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.email),
                errorText: _error,
              ),
              onSubmitted: (_) => _link(),
            ),

            const SizedBox(height: 16),

            // ===== الزر =====
            if (_successResult == null)
              FilledButton.icon(
                onPressed: _busy ? null : _link,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link),
                label: Text(_busy ? 'جاري الربط...' : 'ربط'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),

            // ===== رسالة الخطأ =====
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ===== رسالة النجاح =====
            if (_successResult != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 64),
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
                      'مرحباً ${_successResult!.accountantName ?? ""}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if ((_successResult!.accountantCode ?? '').isNotEmpty)
                      Text(
                        'رمزك: ${_successResult!.accountantCode}',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.grey),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'سيتم الآن مزامنة بياناتك تلقائياً',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
}
