import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/log_event.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/date_filter.dart';
import '../services/export_service.dart';
import '../services/logger_service.dart';
import '../services/pdf_service.dart';
import '../services/whatsapp_service.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';
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
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _load();
  }

  Future<void> _load() async {
    try {
      final bal = await db.customerBalance(_customer.id!);
      final allTx = await db.customerTransactions(_customer.id!);

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

      if (!_alertShown &&
          _customer.isOverLimit(bal) &&
          _customer.maxBalance != null) {
        _alertShown = true;

        await LoggerService.logCustomerLimitExceeded(
          name: _customer.name,
          balance: bal,
          maxBalance: _customer.maxBalance!,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showLimitWarning();
        });
      }
    } catch (e) {
      debugPrint('❌ _load error: $e');
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

  // ═══════════════════════════════════════════════════════════
  // إضافة عملية — مع إصلاح البيان للسداد
  // ═══════════════════════════════════════════════════════════
  Future<void> _addTransaction(String type) async {
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

    final accountant = await AccountantService.getAccountantName();

    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    bool isSaving = false;

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
                if (accountant != null && accountant.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.teal.withOpacity(0.4)),
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
                const SizedBox(height: 8),
                // 🆕 يظهر دائمًا — "البيان" للسداد، "الأصناف" للدين/المرتجع
                TextField(
                  controller: itemsCtrl,
                  enabled: !isSaving,
                  decoration: InputDecoration(
                    labelText: type == 'payment' ? 'البيان' : 'الأصناف',
                    hintText: type == 'payment'
                        ? 'مثال: دفعة شهر أكتوبر...'
                        : 'مثال: رز، شاي، سكر...',
                  ),
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
                            accountant: accountant,
                            source: 'customer_screen',
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          final typeLabel = {
                            'debt': 'دين',
                            'payment': 'سداد',
                            'return': 'مرتجع',
                          }[type]!;
                          await LoggerService.logTransactionAdded(
                            typeLabel: typeLabel,
                            customerName: _customer.name,
                            amount: amt,
                            currency: 'YER',
                            code: code,
                            accountant: accountant,
                            source: 'customer_screen',
                          );

                          if (accountant != null && accountant.isNotEmpty) {
                            await db.updateCustomerFields(
                              _customer.id!,
                              {},
                              by: accountant,
                            );
                          }

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

  Future<void> _editTransaction(Transaction t) async {
    if (!SettingsService.getBool(
      AppSettings.allowEditTransactions,
      defaultValue: true,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التعديل على العمليات معطّل من الإعدادات'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isDebt = t.type == 'debt';
    final isReturn = t.items.startsWith('مرتجع');
    final amountCtrl = TextEditingController(text: t.amount.toStringAsFixed(0));
    final itemsCtrl = TextEditingController(
        text: isReturn
            ? t.items.replaceFirst(RegExp(r'^مرتجع:?\s*'), '')
            : t.items);

    bool didSave = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
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
              const SizedBox(height: 8),
              // 🆕 يظهر دائمًا
              TextField(
                controller: itemsCtrl,
                decoration: InputDecoration(
                  labelText: isDebt || isReturn ? 'الأصناف' : 'البيان',
                  hintText: isDebt || isReturn
                      ? 'مثال: رز، شاي...'
                      : 'مثال: دفعة...',
                ),
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
                if (amt == null || amt <= 0) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('أدخل مبلغًا صحيحًا'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                final newItems = isReturn
                    ? 'مرتجع: ${itemsCtrl.text.trim()}'
                    : itemsCtrl.text.trim();

                final changedFields = <String>[];
                if (amt != t.amount) changedFields.add('amount');
                if (newItems != t.items) changedFields.add('items');

                if (changedFields.isEmpty) {
                  if (!mounted) return;
                  Navigator.pop(context);
                  return;
                }

                final accountant =
                    await AccountantService.getAccountantName();

                final updated = t.copyWith(
                  amount: amt,
                  items: newItems,
                  updatedBy: accountant,
                  updatedAt: DateTime.now().toIso8601String(),
                  lastModifiedBy: accountant,
                  lastModifiedFrom: 'customer_screen',
                );

                try {
                  final r = await db.updateTransaction(updated, by: accountant);
                  debugPrint('✅ Updated transaction: $r rows');

                  if (SettingsService.getBool(
                    AppSettings.logTransactionEdits,
                    defaultValue: true,
                  )) {
                    final fieldNames = changedFields.map((f) {
                      if (f == 'amount') return 'المبلغ';
                      if (f == 'items') return 'الأصناف';
                      return f;
                    }).join('، ');

                    await LoggerService.log(
                      action: '✏️ تعديل عملية',
                      description: 'تم تعديل $fieldNames\n'
                          'للعملية ${t.code ?? ""}\n'
                          'بواسطة: ${accountant ?? "غير معروف"}',
                      level: LogLevel.warning,
                      category: LogCategory.transaction,
                      accountant: accountant,
                      relatedId: t.id?.toString(),
                      needsAck: false,
                      metadata: {
                        'fields': changedFields,
                        'old_amount': t.amount,
                        'new_amount': amt,
                        'old_items': t.items,
                        'new_items': newItems,
                      },
                    );
                  }

                  didSave = true;

                  if (!mounted) return;
                  Navigator.pop(context);

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ تم التعديل'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );
                } catch (e) {
                  debugPrint('❌ update error: $e');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('فشل: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (didSave && mounted) {
      await _load();
    }
  }

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
            'سيتم نقل هذه العملية إلى سلة المحذوفات:\n\n'
            '${t.code != null ? 'الرمز: ${t.code}\n' : ''}'
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
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final accountant = await AccountantService.getAccountantName();

      final useSoft = SettingsService.getBool(
        AppSettings.softDeleteEnabled,
        defaultValue: true,
      );

      if (useSoft) {
        await db.softDeleteTransaction(t.id!, by: accountant);
      } else {
        await db.hardDeleteTransaction(t.id!);
      }

      await LoggerService.logTransactionDeleted(
        customerName: _customer.name,
        amount: t.amount,
        code: t.code,
        accountant: accountant,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(useSoft
              ? '✅ تم نقل العملية إلى سلة المحذوفات'
              : '✅ تم الحذف النهائي'),
          backgroundColor: Colors.red,
        ),
      );

      await _load();
    } catch (e) {
      debugPrint('❌ delete error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الحذف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showTransactionMenu(Transaction t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
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
                      if (t.wasModified &&
                          SettingsService.getBool(
                            AppSettings.showTrackingInfo,
                            defaultValue: true,
                          ))
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(
                                'عُدّلت بواسطة: ${t.lastModifiedBy ?? t.updatedBy ?? "غير معروف"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        '${t.amount.toStringAsFixed(0)} ${t.currency}',
                        style: const TextStyle(
                          fontSize: 22,
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

                // ✏️ تعديل
                ListTile(
                  leading: const Icon(Icons.edit,
                      color: Colors.blue, size: 28),
                  title: const Text(
                    'تعديل العملية',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  subtitle: const Text(
                    'تعديل المبلغ أو الأصناف',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await Future.delayed(
                        const Duration(milliseconds: 300));
                    if (mounted) {
                      await _editTransaction(t);
                    }
                  },
                ),

                // 🗑️ حذف
                ListTile(
                  leading: const Icon(Icons.delete,
                      color: Colors.red, size: 28),
                  title: const Text(
                    'حذف العملية',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  subtitle: const Text(
                    'نقلها إلى سلة المحذوفات',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await Future.delayed(
                        const Duration(milliseconds: 300));
                    if (mounted) {
                      await _deleteTransaction(t);
                    }
                  },
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.message, color: Colors.green),
                  title: const Text('إرسال عبر واتساب'),
                  onTap: () async {
                    Navigator.pop(context);
                    if (_customer.phone == null ||
                        _customer.phone!.isEmpty) {
                      if (!mounted) return;
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

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportStatement() async {
    final f = await ExportService.exportCustomerStatement(_customer.id!);
    await ExportService.shareFile(f, text: 'كشف حساب ${_customer.name}');
  }

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

  Color _getBalanceColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_customer.maxBalance == null || _customer.maxBalance! <= 0) {
      if (_balance > 0) {
        return isDark ? Colors.red.shade300 : Colors.red.shade700;
      } else {
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      }
    }

    final ratio = _customer.balanceRatio(_balance);

    if (ratio < 0.5) {
      return isDark ? Colors.green.shade300 : Colors.green.shade700;
    }
    if (ratio < 0.8) {
      return isDark ? Colors.amber.shade300 : Colors.amber.shade800;
    }
    return isDark ? Colors.red.shade300 : Colors.red.shade700;
  }

  Color _getHeaderBgColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_customer.maxBalance == null || _customer.maxBalance! <= 0) {
      if (_balance > 0) {
        return isDark
            ? Colors.red.shade900.withOpacity(0.3)
            : Colors.red.shade50;
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
              color: balanceColor,
            ),
          ),
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

  Future<void> _toggleCustomerActive() async {
    if (!SettingsService.getBool(
      AppSettings.allowEditCustomers,
      defaultValue: true,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعديل الحسابات معطّل من الإعدادات'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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

    final accountant = await AccountantService.getAccountantName();

    await db.setCustomerActive(_customer.id!, !_customer.isActive,
        by: accountant);

    await LoggerService.logCustomerStatusChanged(
      name: _customer.name,
      isActive: !_customer.isActive,
      accountant: accountant,
    );

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

  Widget _buildTransactionCard(
      Transaction t, ThemeData theme, bool isDark) {
    final isDebt = t.type == 'debt';
    final isReturn = t.items.startsWith('مرتجع');

    Color typeColor;
    IconData typeIcon;
    if (isReturn) {
      typeColor = Colors.orange;
      typeIcon = Icons.keyboard_return;
    } else if (isDebt) {
      typeColor = theme.colorScheme.error;
      typeIcon = Icons.arrow_upward;
    } else {
      typeColor = theme.colorScheme.primary;
      typeIcon = Icons.arrow_downward;
    }

    final sourceInfo = Transaction.sourceInfo(t.source);
    final sourceColor = Color(sourceInfo.color);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _showTransactionMenu(t),
        onLongPress: () => _showTransactionMenu(t),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _formatDateTime(t.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (t.source != null && t.source!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: sourceColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: sourceColor.withOpacity(0.4),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        sourceInfo.emoji,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  if (t.accountant != null && t.accountant!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.teal.withOpacity(0.4),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person,
                              size: 10, color: Colors.teal),
                          const SizedBox(width: 3),
                          Text(
                            t.accountant!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (t.wasModified &&
                      SettingsService.getBool(
                        AppSettings.showTrackingInfo,
                        defaultValue: true,
                      ))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.4),
                          width: 0.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit,
                              size: 9, color: Colors.orange),
                          SizedBox(width: 2),
                          Text(
                            'مُعدّلة',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
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
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.4),
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
                              color: Colors.blue.withOpacity(0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isReturn
                          ? 'مرتجع'
                          : (isDebt ? 'دين' : 'سداد'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '${t.amount.toStringAsFixed(0)} ${t.currency}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: typeColor,
                    ),
                  ),
                ],
              ),
              if (t.items.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          t.items.replaceFirst(
                              RegExp(r'^مرتجع:?\s*'), ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
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
                      itemBuilder: (_, i) =>
                          _buildTransactionCard(_tx[i], theme, isDark),
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
    final balance = await db.customerBalance(_customer.id!);

    if (SettingsService.getBool(
          AppSettings.blockDeleteNonzeroBalance,
          defaultValue: true,
        ) &&
        balance != 0) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Text('لا يمكن الحذف'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الحساب "${_customer.name}" رصيده غير صفري.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _warningRow(
                  'الرصيد الحالي',
                  '${balance.toStringAsFixed(0)} ريال',
                  balance > 0 ? Colors.red : Colors.green,
                ),
                const SizedBox(height: 12),
                const Text(
                  '💡 يجب تصفية الرصيد أولاً (سداد كامل أو تعديل) قبل الحذف.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (SettingsService.getBool(
          AppSettings.blockDeleteWithTransactions,
          defaultValue: true,
        ) &&
        _allTx.isNotEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.red),
                SizedBox(width: 8),
                Text('لا يمكن الحذف'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الحساب "${_customer.name}" عليه ${_allTx.length} عملية.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  '💡 يجب حذف كل معاملاته أولاً قبل حذف الحساب.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final useSoft = SettingsService.getBool(
      AppSettings.softDeleteEnabled,
      defaultValue: true,
    );

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
            useSoft
                ? 'سيتم حذف الحساب "${_customer.name}" وكل معاملاته (${_allTx.length} عملية).\n\n'
                    '💰 الرصيد: ${balance.toStringAsFixed(0)} ريال\n'
                    '🗑️ سيُحفظ في سلة المحذوفات لمدة 30 يومًا.'
                : '⚠️ سيتم حذف الحساب "${_customer.name}" **نهائيًا**!\n\n'
                    'لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(useSoft ? 'حذف' : 'حذف نهائي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final accountant = await AccountantService.getAccountantName();

    if (useSoft) {
      await db.softDeleteCustomer(_customer.id!, by: accountant);
    } else {
      await db.hardDeleteCustomer(_customer.id!);
    }

    await LoggerService.logCustomerDeleted(
      _customer.name,
      accountant: accountant,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(useSoft
            ? 'تم الحذف — يمكن استعادته من السلة'
            : 'تم الحذف النهائي'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
