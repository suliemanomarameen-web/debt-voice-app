import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/accountant_service.dart';
import '../services/code_service.dart';
import '../services/logger_service.dart';
import '../services/notification_dispatcher.dart';

/// نافذة "عملية جديدة" — مشتركة بين customers_tab و debts_tab
class QuickTransactionDialog {
  /// عرض النافذة
  ///
  /// يعيد `true` إذا تم حفظ العملية، `null` أو `false` إذا أُلغيت
  static Future<bool?> show(BuildContext context) async {
    final db = DatabaseHelper.instance;

    // 1. جلب العملاء النشطين
    final all = await db.activeCustomers();

    if (all.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد عملاء نشطون. أضف حساباً أولاً'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    // 2. جلب اسم المحاسب
    final accountant = await AccountantService.getAccountantName();

    // 3. متغيرات النافذة
    String type = 'debt';
    Customer? selectedCustomer;
    final amountCtrl = TextEditingController();
    final itemsCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    List<Customer> filtered = List.from(all);
    bool isSaving = false;

    if (!context.mounted) return false;

    // 4. عرض النافذة
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.add_card, color: Colors.teal),
                const SizedBox(width: 8),
                const Expanded(child: Text('عملية جديدة')),
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
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ============ نوع العملية ============
                    const Text(
                      'نوع العملية:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'debt',
                          label: _SegmentLabel('دين', Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: 'payment',
                          label: _SegmentLabel('سداد', Icons.payments),
                        ),
                        ButtonSegment(
                          value: 'return',
                          label: _SegmentLabel(
                              'مرتجع', Icons.keyboard_return),
                        ),
                      ],
                      selected: {type},
                      onSelectionChanged: (v) {
                        setStateDialog(() => type = v.first);
                      },
                    ),

                    const Divider(height: 24),

                    // ============ العميل ============
                    const Text(
                      'العميل:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (selectedCustomer != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.teal, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                selectedCustomer!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setStateDialog(() {
                                  selectedCustomer = null;
                                  searchCtrl.clear();
                                  filtered = List.from(all);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (selectedCustomer == null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        onChanged: (v) {
                          setStateDialog(() {
                            filtered = all
                                .where((c) => c.name.contains(v.trim()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: Text(
                                    'لا توجد نتائج',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          Theme.of(ctx).colorScheme.primary,
                                      child: Text(
                                        c.name.characters.first,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    title: Text(c.name),
                                    subtitle: c.phone != null &&
                                            c.phone!.isNotEmpty
                                        ? Text(
                                            c.phone!,
                                            style: const TextStyle(
                                                fontSize: 11),
                                          )
                                        : null,
                                    onTap: () {
                                      setStateDialog(() {
                                        selectedCustomer = c;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],

                    const Divider(height: 24),

                    // ============ المبلغ ============
                    const Text(
                      'المبلغ:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'أدخل المبلغ',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ============ البيان / الأصناف ============
                    if (type == 'payment') ...[
                      const Text(
                        'البيان:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: noteCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: دفعة شهر أكتوبر...',
                          prefixIcon:
                              const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                    if (type != 'payment') ...[
                      const Text(
                        'الأصناف:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: itemsCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: رز، شاي، زبادي',
                          prefixIcon:
                              const Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        // ============ التحقق ============
                        if (selectedCustomer == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('الرجاء اختيار عميل'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }

                        final amt = double.tryParse(amountCtrl.text);
                        if (amt == null || amt <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('الرجاء إدخال مبلغ صحيح'),
                              backgroundColor: Colors.orange,
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);

                        try {
                          // ============ منع التكرار ============
                          final storedType =
                              (type == 'return') ? 'payment' : type;

                          final isDuplicate =
                              await db.transactionExistsRecent(
                            customerId: selectedCustomer!.id!,
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

                          // ============ توليد الرمز ============
                          String? code;
                          try {
                            code = await CodeService.generateCode(type);
                          } catch (_) {}

                          // ============ نص إضافي ============
                          String extraText;
                          if (type == 'payment') {
                            extraText = noteCtrl.text.trim();
                          } else if (type == 'return') {
                            extraText = itemsCtrl.text.trim().isEmpty
                                ? 'مرتجع'
                                : 'مرتجع: ${itemsCtrl.text.trim()}';
                          } else {
                            extraText = itemsCtrl.text.trim();
                          }

                          // ============ حفظ العملية ============
                          await db.insertTransaction(Transaction(
                            customerId: selectedCustomer!.id!,
                            code: code,
                            accountant: accountant,
                            source: 'manual',
                            amount: amt,
                            type: storedType,
                            items: extraText,
                            createdAt: DateTime.now().toIso8601String(),
                          ));

                          // ============ تسجيل الحدث ============
                          final typeLabelForLog = {
                            'debt': 'دين',
                            'payment': 'سداد',
                            'return': 'مرتجع',
                          }[type]!;

                          await LoggerService.logTransactionAdded(
                            typeLabel: typeLabelForLog,
                            customerName: selectedCustomer!.name,
                            amount: amt,
                            currency: 'YER',
                            code: code,
                            accountant: accountant,
                            source: 'manual',
                          );

                          // ============ الإشعارات (واتساب) ============
                          final newBalance =
                              await db.customerBalance(selectedCustomer!.id!);

                          final normalizedType =
                              CodeService.normalizeType(type);

                          await NotificationDispatcher.afterTransactionAdded(
                            customerId: selectedCustomer!.id!,
                            customerName: selectedCustomer!.name,
                            phone: selectedCustomer!.phone,
                            type: normalizedType,
                            amount: amt,
                            newBalance: newBalance,
                            source: 'manual',
                          );

                          // ============ إغلاق + SnackBar ============
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, true);

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'تم تسجيل $typeLabelForLog بقيمة ${amt.toStringAsFixed(0)} ريال'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        } finally {
                          if (ctx.mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }
}

/// Widget مساعد للـ SegmentedButton
class _SegmentLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SegmentLabel(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Icon(icon, size: 16),
        ],
      ),
    );
  }
}
