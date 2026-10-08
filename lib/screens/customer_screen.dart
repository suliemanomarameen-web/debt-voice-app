import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/date_filter.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';
import 'add_account_screen.dart';
import 'share_receipt_screen.dart';

class CustomerScreen extends StatefulWidget {
  final Customer customer;
  const CustomerScreen({super.key, required this.customer});
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final db = DatabaseHelper.instance;
  double _balance = 0;
  List<Transaction> _allTx = [];
  List<Transaction> _tx = [];
  DateFilter _dateFilter = DateFilter();
  bool _alertShown = false;
  late Customer _customer; // 🆕 نسخة قابلة للتحديث

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _load();
  }

  Future<void> _load() async {
    final bal = await db.customerBalance(_customer.id!);
    final allTx = await db.customerTransactions(_customer.id!);

    // 🆕 إعادة جلب بيانات العميل (للتأكد من isActive و maxBalance)
    final all = await db.allCustomers();
    final updated = all.where((c) => c.id == _customer.id).toList();
    if (updated.isNotEmpty) {
      _customer = updated.first;
    }

    if (!mounted) return;
    setState(() {
      _balance = bal;
      _allTx = allTx;
      _applyFilter();
    });

    // تنبيه تجاوز الحد
    if (!_alertShown && _customer.isOverLimit(bal) && _customer.maxBalance != null) {
      _alertShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showLimitWarning();
      });
    }
  }

  void _applyFilter() {
    _tx = _allTx.where((t) => _dateFilter.matches(t.createdAt)).toList();
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final y = dt.year;
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y/$m/$d - $h:$min';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(0, 16) : iso;
    }
  }

  // ============ نسخ الرمز ============
  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('تم نسخ الرمز: $code'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============ تنبيه تجاوز الحد ============
  void _showLimitWarning() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('تنبيه', style: TextStyle(color: Colors.red)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'رصيد "${_customer.name}" تجاوز الحد الأقصى.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _warningRow('الرصيد الحالي',
                  '${_balance.toStringAsFixed(0)} ريال', Colors.red),
              const SizedBox(height: 4),
              _warningRow(
                'الحد الأقصى',
                '${_customer.maxBalance!.toStringAsFixed(0)} ريال',
                Colors.grey,
              ),
              const SizedBox(height: 4),
              _warningRow(
                'التجاوز',
                '+${(_balance - _customer.maxBalance!).toStringAsFixed(0)} ريال',
                Colors.orange,
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warningRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ============ إرسال تذكير واتساب ============
  Future<void> _sendWhatsAppReminder() async {
    if (_customer.phone == null || _customer.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف لهذا العميل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await WhatsAppService.sendReminder(
        phone: _customer.phone,
        customerName: _customer.name,
        balance: _balance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============ فلتر التاريخ ============
  Future<void> _showDateFilter() async {
    final result = await showModalBottomSheet<DateFilter>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('فلترة بالتاريخ',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.all_inclusive),
                title: const Text('الكل'),
                trailing: _dateFilter.type == DateFilterType.all
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, DateFilter()),
              ),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('اليوم'),
                trailing: _dateFilter.type == DateFilterType.today
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.today)),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('آخر 7 أيام'),
                trailing: _dateFilter.type == DateFilterType.week
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.week)),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('آخر 30 يوماً'),
                trailing: _dateFilter.type == DateFilterType.month
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(
                    context, DateFilter(type: DateFilterType.month)),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _dateFilter = result;
        _applyFilter();
      });
    }
  }

  // ============ إضافة معاملة ============
  Future<void> _addTransaction(String type) async {
    // 🆕 تحقق من حالة الحساب
    if (!_customer.isActive) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Text('الحساب موقوف'),
              ],
            ),
            content: Text(
              'الحساب "${_customer.name}" موقوف حالياً.\n\n'
              'هل تريد المتابعة وإضافة العملية؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        ),
      );
      if (proceed != true) return;
    }

    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    bool isSaving = false;

    // 🆕 جلب اسم المحاسب مسبقاً
    final accountant = await AccountantService.getAccountantName();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(type == 'debt'
                      ? 'دين جديد'
                      : type == 'return'
                          ? 'مرتجع جديد'
                          : 'دفعة سداد'),
                ),
                // 🆕 عرض اسم المحاسب
                if (accountant != null && accountant.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.teal.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person,
                            size: 12, color: Colors.teal),
                        const SizedBox(width: 4),
                        Text(
                          accountant,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !isSaving,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
                if (type != 'payment')
                  TextField(
                    controller: itemsCtrl,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: 'الأصناف'),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final amt = double.tryParse(amountCtrl.text);
                        if (amt == null || amt <= 0) return;

                        setStateDialog(() => isSaving = true);

                        try {
                          final storedType =
                              (type == 'return') ? 'payment' : type;

                          // منع التكرار
                          final isDuplicate =
                              await db.transactionExistsRecent(
                            customerId: _customer.id!,
                            amount: amt,
                            type: storedType,
                            window: const Duration(seconds: 30),
                          );

                          if (isDuplicate) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '⚠️ هذه العملية مسجلة بالفعل (خلال آخر 30 ثانية)'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            setStateDialog(() => isSaving = false);
                            return;
                          }

                          String? code;
                          try {
                            code = await CodeService.generateCode(type);
                          } catch (_) {
                            code = null;
                          }

                          String extraText;
                          if (type == 'return') {
                            extraText = itemsCtrl.text.trim().isEmpty
                                ? 'مرتجع'
                                : 'مرتجع: ${itemsCtrl.text.trim()}';
                          } else {
                            extraText = itemsCtrl.text.trim();
                          }

                          await db.insertTransaction(Transaction(
                            customerId: _customer.id!,
                            code: code,
                            accountant: accountant, // 🆕
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          final newBalance =
                              await db.customerBalance(_customer.id!);

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await _load();

                          final sp =
                              await SharedPreferences.getInstance();
                          final autoWhatsApp =
                              sp.getBool('auto_whatsapp') ?? false;

                          if (autoWhatsApp &&
                              _customer.phone != null &&
                              _customer.phone!.isNotEmpty) {
                            await Future.delayed(
                                const Duration(milliseconds: 500));
                            try {
                              await WhatsAppService
                                  .sendTransactionNotification(
                                phone: _customer.phone,
                                customerName: _customer.name,
                                type: type,
                                amount: amt,
                                newBalance: newBalance,
                              );
                            } catch (e) {
                              debugPrint('WhatsApp error: $e');
                            }
                          }
                        } finally {
                          if (mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    _load();
  }

  // ============ تعديل معاملة ============
  Future<void> _editTransaction(Transaction t) async {
    final isDebt = t.type == 'debt';
    final isReturn = t.items.startsWith('مرتجع');
    final amountCtrl = TextEditingController(text: t.amount.toStringAsFixed(0));
    final itemsCtrl = TextEditingController(
        text: isReturn
            ? t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '')
            : t.items);

    await showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(isDebt
              ? 'تعديل الدين'
              : isReturn
                  ? 'تعديل المرتجع'
                  : 'تعديل السداد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (t.code != null && t.code!.isNotEmpty) ...[
                InkWell(
                  onTap: () => _copyCode(t.code!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code,
                            size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          'الرمز: ${t.code}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.copy, size: 14, color: Colors.blue),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              if (isDebt || isReturn)
                TextField(
                  controller: itemsCtrl,
                  decoration: const InputDecoration(labelText: 'الأصناف'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text);
                if (amt == null || amt <= 0) return;
                await db.updateTransaction(Transaction(
                  id: t.id,
                  customerId: t.customerId,
                  code: t.code,
                  accountant: t.accountant,
                  amount: amt,
                  currency: t.currency,
                  type: t.type,
                  items: isReturn
                      ? 'مرتجع: ${itemsCtrl.text.trim()}'
                      : itemsCtrl.text.trim(),
                  createdAt: t.createdAt,
                ));
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    _load();
  }

  // ============ حذف معاملة ============
  Future<void> _deleteTransaction(Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Text('تأكيد الحذف'),
            ],
          ),
          content: Text(
            'سيتم حذف هذه العملية نهائياً:\n\n'
            '${t.code != null ? 'الرمز: ${t.code}\n' : ''}'
            '${t.accountant != null ? 'المحاسب: ${t.accountant}\n' : ''}'
            'النوع: ${t.type == 'debt' ? 'دين' : 'سداد'}\n'
            'المبلغ: ${t.amount.toStringAsFixed(0)} ${t.currency}\n'
            '${t.items.isNotEmpty ? 'الأصناف: ${t.items}\n' : ''}'
            'التاريخ: ${_formatDateTime(t.createdAt)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await db.deleteTransaction(t.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف العملية'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _load();
    }
  }

  // ============ قائمة العمليات ============
  void _showTransactionMenu(Transaction t) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (t.code != null && t.code!.isNotEmpty) ...[
                      InkWell(
                        onTap: () => _copyCode(t.code!),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.qr_code,
                                  size: 14, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                t.code!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.copy,
                                  size: 12, color: Colors.blue),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (t.accountant != null && t.accountant!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person,
                                size: 14, color: Colors.teal),
                            const SizedBox(width: 6),
                            Text(
                              t.accountant!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      '${t.amount.toStringAsFixed(0)} ${t.currency}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(t.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text('إرسال عبر واتساب'),
                onTap: () async {
                  Navigator.pop(context);
                  if (_customer.phone == null ||
                      _customer.phone!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('لا يوجد رقم هاتف لهذا العميل'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  try {
                    await WhatsAppService.sendTransactionNotification(
                      phone: _customer.phone,
                      customerName: _customer.name,
                      type: t.type,
                      amount: t.amount,
                      newBalance: _balance,
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e')),
                      );
                    }
                  }
                },
              ),

              ListTile(
                leading: const Icon(Icons.share, color: Colors.blue),
                title: const Text('مشاركة'),
                onTap: () async {
                  Navigator.pop(context);
                  final typeLabel = t.type == 'debt'
                      ? 'دين'
                      : t.items.startsWith('مرتجع')
                          ? 'مرتجع'
                          : 'سداد';
                  final text = '''
السلام عليكم ${_customer.name}،
تم تسجيل العملية التالية:

${t.code != null ? 'الرمز: ${t.code}\n' : ''}النوع: $typeLabel
المبلغ: ${t.amount.toStringAsFixed(0)} ${t.currency}
${t.items.isNotEmpty ? 'الأصناف: ${t.items}\n' : ''}التاريخ: ${_formatDateTime(t.createdAt)}

الرصيد المتبقي: ${_balance.toStringAsFixed(0)} ريال

شكراً لتعاملكم معنا
''';
                  await Share.share(text);
                },
              ),

              ListTile(
                leading: const Icon(Icons.print, color: Colors.orange),
                title: const Text('طباعة / حفظ PDF للعملية'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final file = await PdfService.generateStatement(
                      _customer,
                      fromDate: DateTime.parse(t.createdAt),
                      toDate: DateTime.parse(t.createdAt),
                    );
                    await PdfService.share(file, _customer.name);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('فشل: $e')),
                      );
                    }
                  }
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('تعديل'),
                onTap: () {
                  Navigator.pop(context);
                  _editTransaction(t);
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteTransaction(t);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportStatement() async {
    final f = await ExportService.exportCustomerStatement(_customer.id!);
    await ExportService.shareFile(f, text: 'كشف حساب ${_customer.name}');
  }

  // ============ PDF مع فلترة التاريخ ============
  Future<void> _exportPdf() async {
    DateTime? fromDate;
    DateTime? toDate;
    String selectedFont = 'Tajawal';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('فلترة كشف الحساب'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('اختر الفترة (اتركها فارغة للكل)',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(
                      fromDate == null
                          ? 'من تاريخ: الكل'
                          : 'من: ${fromDate!.year}/${fromDate!.month}/${fromDate!.day}',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fromDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setStateDialog(() => fromDate = picked);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.event),
                    title: Text(
                      toDate == null
                          ? 'إلى تاريخ: الكل'
                          : 'إلى: ${toDate!.year}/${toDate!.month}/${toDate!.day}',
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: toDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setStateDialog(() => toDate = picked);
                      }
                    },
                  ),
                  if (fromDate != null || toDate != null)
                    TextButton.icon(
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('مسح الفلتر'),
                      onPressed: () {
                        setStateDialog(() {
                          fromDate = null;
                          toDate = null;
                        });
                      },
                    ),
                  const Divider(height: 24),
                  const Text('نوع الخط:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Tajawal',
                        label: Text('Tajawal'),
                        icon: Icon(Icons.text_fields),
                      ),
                      ButtonSegment(
                        value: 'Cairo',
                        label: Text('Cairo'),
                        icon: Icon(Icons.text_format),
                      ),
                    ],
                    selected: {selectedFont},
                    onSelectionChanged: (v) {
                      setStateDialog(() => selectedFont = v.first);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, {
                  'from': fromDate,
                  'to': toDate,
                  'font': selectedFont,
                }),
                child: const Text('توليد PDF'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final file = await PdfService.generateStatement(
        _customer,
        fromDate: result['from'],
        toDate: result['to'],
        fontName: result['font'] ?? 'Tajawal',
      );

      if (!mounted) return;
      Navigator.pop(context);

      await PdfService.share(file, _customer.name);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إنشاء PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============ 🆕 حساب ألوان الرصيد حسب النسبة ============
  Color _getBalanceColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // إذا لا يوجد حد أقصى → السلوك القديم
    if (_customer.maxBalance == null || _customer.maxBalance! <= 0) {
      if (_balance > 0) {
        return isDark ? Colors.red.shade300 : Colors.red.shade700;
      } else {
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      }
    }

    final ratio = _customer.balanceRatio(_balance);

    // 🟢 أخضر: أقل من 50%
    if (ratio < 0.5) {
      return isDark ? Colors.green.shade300 : Colors.green.shade700;
    }
    // 🟡 أصفر: من 50% إلى 80%
    if (ratio < 0.8) {
      return isDark ? Colors.amber.shade300 : Colors.amber.shade800;
    }
    // 🔴 أحمر: 80% أو أكثر
    return isDark ? Colors.red.shade300 : Colors.red.shade700;
  }

  // ============ 🆕 لون خلفية الهيدر ============
  Color _getHeaderBgColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_customer.maxBalance == null || _customer.maxBalance! <= 0) {
      if (_balance > 0) {
        return isDark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50;
      }
      return isDark
          ? Colors.green.shade900.withOpacity(0.3)
          : Colors.green.shade50;
    }

    final ratio = _customer.balanceRatio(_balance);

    if (ratio < 0.5) {
      return isDark
          ? Colors.green.shade900.withOpacity(0.3)
          : Colors.green.shade50;
    }
    if (ratio < 0.8) {
      return isDark
          ? Colors.amber.shade900.withOpacity(0.3)
          : Colors.amber.shade50;
    }
    return isDark ? Colors.red.shade900.withOpacity(0.3) : Colors.red.shade50;
  }

  // ============ Header ============
  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final catColor = Color(CustomerCategory.color(_customer.category));
    final overLimit = _customer.isOverLimit(_balance);
    final balanceColor = _getBalanceColor(theme);
    final headerBg = _getHeaderBgColor(theme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: headerBg),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withOpacity(0.2),
                      border: Border.all(
                        color: !_customer.isActive
                            ? Colors.grey
                            : (overLimit ? Colors.red : catColor),
                        width: 3,
                      ),
                      image: _customer.photoPath != null &&
                              File(_customer.photoPath!).existsSync()
                          ? DecorationImage(
                              image:
                                  FileImage(File(_customer.photoPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _customer.photoPath == null ||
                            !File(_customer.photoPath!).existsSync()
                        ? Center(
                            child: Text(
                              _customer.name.characters.first,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  // 🆕 شارة الإيقاف
                  if (!_customer.isActive)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: theme.colorScheme.surface, width: 2),
                        ),
                        child: const Icon(
                          Icons.block,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _customer.name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: !_customer.isActive
                                  ? Colors.grey
                                  : null,
                            ),
                          ),
                        ),
                        if (overLimit && _customer.isActive)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.warning_amber,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                        // 🆕 شارة الإيقاف
                        if (!_customer.isActive)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade700,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.block,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 3),
                                Text(
                                  'موقوف',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: catColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, size: 14, color: catColor),
                              const SizedBox(width: 4),
                              Text(
                                CustomerCategory.label(_customer.category),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: catColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                theme.colorScheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _accountTypeLabel(_customer.accountType),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_customer.phone != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.phone,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            _customer.phone!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text('الرصيد المتبقي',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            '${_balance.toStringAsFixed(0)} ريال',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: balanceColor, // 🆕 حسب النسبة
            ),
          ),
          // ===== الحد الأقصى + النسبة =====
          if (_customer.maxBalance != null) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: balanceColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: balanceColor.withOpacity(0.5),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    overLimit ? Icons.warning_amber : Icons.shield_outlined,
                    size: 14,
                    color: balanceColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'الحد الأقصى: ${_customer.maxBalance!.toStringAsFixed(0)} ريال',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: balanceColor,
                    ),
                  ),
                  // 🆕 النسبة المئوية
                  if (_balance > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${(_customer.balanceRatio(_balance) * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: balanceColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 🆕 شريط التقدم
            if (_balance > 0) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _customer.balanceRatio(_balance).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(balanceColor),
                  ),
                ),
              ),
            ],
          ],
          if (_customer.note != null && _customer.note!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.note, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _customer.note!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _accountTypeLabel(String t) {
    return {
      'customer': 'عميل',
      'supplier': 'مورد',
      'other': 'أخرى',
    }[t] ?? 'عميل';
  }

  // ============ 🆕 تبديل حالة الحساب ============
  Future<void> _toggleCustomerActive() async {
    final willStop = _customer.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                willStop ? Icons.block : Icons.check_circle,
                color: willStop ? Colors.orange : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(willStop ? 'إيقاف الحساب' : 'تفعيل الحساب'),
            ],
          ),
          content: Text(
            willStop
                ? 'سيتم إيقاف الحساب "${_customer.name}".\n\n'
                    '• لن يُظهر في القوائم العادية.\n'
                    '• يمكنك إضافته في العمليات مع تنبيه.\n'
                    '• البيانات محفوظة بالكامل.'
                : 'سيتم تفعيل الحساب "${_customer.name}" مرة أخرى.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: willStop ? Colors.orange : Colors.green,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(willStop ? 'إيقاف' : 'تفعيل'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    await db.setCustomerActive(_customer.id!, !_customer.isActive);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(willStop
            ? 'تم إيقاف الحساب "${_customer.name}"'
            : 'تم تفعيل الحساب "${_customer.name}"'),
        backgroundColor: willStop ? Colors.orange : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_customer.name),
          actions: [
            IconButton(
              icon: Icon(
                _dateFilter.type == DateFilterType.all
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt,
                color: _dateFilter.type == DateFilterType.all
                    ? null
                    : theme.colorScheme.primary,
              ),
              tooltip: 'فلترة: ${_dateFilter.label}',
              onPressed: _showDateFilter,
            ),
            IconButton(
              icon: const Icon(Icons.image),
              tooltip: 'مشاركة كصورة',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ShareReceiptScreen(customer: _customer),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'كشف حساب PDF',
              onPressed: _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.message, color: Colors.green),
              tooltip: 'تذكير عبر واتساب',
              onPressed: _sendWhatsAppReminder,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'excel':
                    _exportStatement();
                    break;
                  case 'edit':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AddAccountScreen(existing: _customer),
                      ),
                    ).then((changed) {
                      if (changed == true && mounted) {
                        Navigator.pop(context, true);
                      } else {
                        _load();
                      }
                    });
                    break;
                  case 'toggle':
                    _toggleCustomerActive();
                    break;
                  case 'delete':
                    _showDeleteCustomer();
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'excel',
                  child: ListTile(
                    leading: Icon(Icons.table_chart),
                    title: Text('تصدير Excel'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('تعديل بيانات الحساب'),
                  ),
                ),
                // 🆕 إيقاف/تفعيل الحساب
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(
                      _customer.isActive ? Icons.block : Icons.check_circle,
                      color:
                          _customer.isActive ? Colors.orange : Colors.green,
                    ),
                    title: Text(
                      _customer.isActive ? 'إيقاف الحساب' : 'تفعيل الحساب',
                      style: TextStyle(
                        color: _customer.isActive
                            ? Colors.orange
                            : Colors.green,
                      ),
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('حذف الحساب',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            _buildHeader(theme),
            if (_dateFilter.type != DateFilterType.all)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: theme.colorScheme.primary.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(Icons.filter_alt,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('فلتر: ${_dateFilter.label}',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_tx.length} عملية',
                        style: const TextStyle(fontSize: 12)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _dateFilter = DateFilter();
                          _applyFilter();
                        });
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _tx.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد عمليات في هذا النطاق',
                        style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _tx.length,
                      itemBuilder: (_, i) {
                        final t = _tx[i];
                        final isDebt = t.type == 'debt';
                        final isReturn = t.items.startsWith('مرتجع');

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              isReturn
                                  ? Icons.keyboard_return
                                  : (isDebt
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward),
                              color: isReturn
                                  ? Colors.orange
                                  : (isDebt
                                      ? (isDark
                                          ? Colors.red.shade300
                                          : theme.colorScheme.error)
                                      : (isDark
                                          ? Colors.green.shade300
                                          : theme.colorScheme.primary)),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${t.amount.toStringAsFixed(0)} ${t.currency}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (t.accountant != null &&
                                    t.accountant!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color:
                                            Colors.teal.withOpacity(0.4),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person,
                                            size: 9, color: Colors.teal),
                                        const SizedBox(width: 2),
                                        Text(
                                          t.accountant!,
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (t.code != null && t.code!.isNotEmpty)
                                  InkWell(
                                    onTap: () => _copyCode(t.code!),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.blue.withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                          color:
                                              Colors.blue.withOpacity(0.4),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            t.code!,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Icon(
                                            Icons.copy,
                                            size: 9,
                                            color:
                                                Colors.blue.withOpacity(0.7),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (t.items.isNotEmpty)
                                  Text(t.items,
                                      style: const TextStyle(fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDateTime(t.createdAt),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme
                                          .colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            onLongPress: () => _showTransactionMenu(t),
                            onTap: () => _showTransactionMenu(t),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('debt'),
                  icon: const Icon(Icons.add),
                  label: const Text('دين'),
                  style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? Colors.red.shade400 : Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('payment'),
                  icon: const Icon(Icons.payments),
                  label: const Text('سداد'),
                  style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.green.shade400
                          : theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addTransaction('return'),
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('مرتجع'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteCustomer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('تأكيد حذف الحساب'),
            ],
          ),
          content: Text(
            'سيتم حذف الحساب "${_customer.name}" وكل معاملاته (${_allTx.length} عملية).\n\n'
            'لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف الحساب'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await db.deleteCustomer(_customer.id!);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الحساب'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
