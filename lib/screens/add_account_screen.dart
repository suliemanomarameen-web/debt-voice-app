import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';
import '../models/log_event.dart';
import '../services/accountant_service.dart';
import '../services/logger_service.dart';
import '../config/app_settings.dart';
import '../services/settings_service.dart';

class AddAccountScreen extends StatefulWidget {
  final Customer? existing;
  const AddAccountScreen({super.key, this.existing});
  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _note;
  late TextEditingController _maxBalance;
  late String _type;
  late String _category;
  String? _photoPath;
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _note = TextEditingController(text: c?.note ?? '');
    _maxBalance = TextEditingController(
      text: c?.maxBalance != null ? c!.maxBalance!.toStringAsFixed(0) : '',
    );
    _type = c?.accountType ?? AccountType.customer;
    _category = c?.category ?? CustomerCategory.normal;
    _photoPath = c?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    _maxBalance.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/customer_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final fileName =
          'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${photosDir.path}/$fileName';

      final file = File(picked.path);
      await file.copy(savedPath);

      if (!mounted) return;
      setState(() => _photoPath = savedPath);
    } catch (e) {
      debugPrint('Pick image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل اختيار الصورة: $e')),
        );
      }
    }
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('التقاط صورة'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('اختيار من المعرض'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_photoPath != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('حذف الصورة',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _photoPath = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final db = DatabaseHelper.instance;
    final accountant = await AccountantService.getAccountantName();
    final now = DateTime.now().toIso8601String();

    double? maxBalance;
    final maxText = _maxBalance.text.trim();
    if (maxText.isNotEmpty) {
      maxBalance = double.tryParse(maxText);
    }

    if (isEdit) {
      final oldCustomer = widget.existing!;
      final newName = _name.text.trim();
      final newPhone =
          _phone.text.trim().isEmpty ? null : _phone.text.trim();
      final newNote =
          _note.text.trim().isEmpty ? null : _note.text.trim();

      final changedFields = <String>[];
      if (newName != oldCustomer.name) changedFields.add('name');
      if (newPhone != oldCustomer.phone) changedFields.add('phone');
      if (_type != oldCustomer.accountType) {
        changedFields.add('account_type');
      }
      if (newNote != oldCustomer.note) changedFields.add('note');
      if (_photoPath != oldCustomer.photoPath) changedFields.add('photo');
      if (_category != oldCustomer.category) {
        changedFields.add('category');
      }
      if (maxBalance != oldCustomer.maxBalance) {
        changedFields.add('max_balance');
      }

      final updated = Customer(
        id: oldCustomer.id,
        cloudId: oldCustomer.cloudId,
        name: newName,
        phone: newPhone,
        accountType: _type,
        note: newNote,
        photoPath: _photoPath,
        category: _category,
        maxBalance: maxBalance,
        isActive: oldCustomer.isActive,
        createdBy: oldCustomer.createdBy,
        createdAt: oldCustomer.createdAt,
      );

      await db.updateCustomer(updated, by: accountant);

      if (changedFields.isNotEmpty &&
          SettingsService.getBool(
            AppSettings.trackEdits,
            defaultValue: true,
          )) {
        final fieldNames = changedFields.map(_fieldNameAr).join('، ');
        await LoggerService.log(
          action: '✏️ تعديل حساب',
          description: 'تم تعديل $fieldNames '
              'للحساب "${oldCustomer.name}"\n'
              'بواسطة: ${accountant ?? "غير معروف"}',
          level: LogLevel.info,
          category: LogCategory.customer,
          accountant: accountant,
          relatedId: oldCustomer.id?.toString(),
          metadata: {
            'fields': changedFields,
            'customer_name': oldCustomer.name,
          },
        );
      }
    } else {
      final newCustomer = Customer(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        accountType: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoPath: _photoPath,
        category: _category,
        maxBalance: maxBalance,
        createdBy: accountant,
        updatedBy: accountant,
        updatedAt: now,
        createdAt: now,
      );

      final id = await db.insertCustomer(newCustomer);

      await LoggerService.logCustomerAdded(
        newCustomer.name,
        accountant: accountant,
      );

      debugPrint('✅ Customer created: id=$id, name=${newCustomer.name}');
    }

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (!isEdit) return;

    final db = DatabaseHelper.instance;
    final balance = await db.customerBalance(widget.existing!.id!);

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
                  'الحساب "${widget.existing!.name}" رصيده غير صفري.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الرصيد الحالي',
                        style: TextStyle(fontSize: 13)),
                    Text(
                      '${balance.toStringAsFixed(0)} ريال',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: balance > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '💡 يجب تصفية الرصيد أولاً قبل الحذف.',
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

    final txCount =
        await db.countCustomerTransactions(widget.existing!.id!);

    if (SettingsService.getBool(
          AppSettings.blockDeleteWithTransactions,
          defaultValue: true,
        ) &&
        txCount > 0) {
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
            content: Text(
              'الحساب "${widget.existing!.name}" عليه $txCount عملية.\n\n'
              '💡 يجب حذف كل معاملاته أولاً.',
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text(
            useSoft
                ? 'سيتم نقل "${widget.existing!.name}" وكل معاملاته إلى سلة المحذوفات.'
                : '⚠️ سيتم حذف "${widget.existing!.name}" **نهائيًا**!\nلا يمكن التراجع.',
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
    if (ok != true) return;

    final accountant = await AccountantService.getAccountantName();

    if (useSoft) {
      await db.softDeleteCustomer(widget.existing!.id!, by: accountant);
    } else {
      await db.hardDeleteCustomer(widget.existing!.id!);
    }

    // 🆕 تمرير التفاصيل الكاملة
    await LoggerService.logCustomerDeleted(
      widget.existing!.name,
      phone: widget.existing!.phone,
      accountType: widget.existing!.accountType,
      isHard: !useSoft,
      accountant: accountant,
    );

    if (mounted) Navigator.pop(context, true);
  }

  String _fieldNameAr(String field) {
    const map = {
      'name': 'الاسم',
      'phone': 'الهاتف',
      'account_type': 'النوع',
      'note': 'الملاحظة',
      'photo': 'الصورة',
      'category': 'التصنيف',
      'max_balance': 'الحد الأقصى',
    };
    return map[field] ?? field;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? 'تعديل حساب' : 'حساب جديد'),
          actions: [
            if (isEdit)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'حذف الحساب',
                onPressed: _busy ? null : _delete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _showPhotoOptions,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                          image: _photoPath != null
                              ? DecorationImage(
                                  image: FileImage(File(_photoPath!)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _photoPath == null
                            ? Icon(
                                Icons.add_a_photo,
                                size: 40,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              )
                            : null,
                      ),
                    ),
                    if (_photoPath != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: theme.colorScheme.primary,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.edit,
                                color: Colors.white, size: 18),
                            onPressed: _showPhotoOptions,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _photoPath == null
                      ? 'اضغط لإضافة صورة'
                      : 'اضغط لتغيير الصورة',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'الاسم مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'النوع',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
                items: AccountType.all
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(AccountType.labelsAr[t]!)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star),
                ),
                items: CustomerCategory.all.map((c) {
                  final color = Color(CustomerCategory.color(c));
                  return DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(CustomerCategory.label(c)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'الهاتف (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxBalance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الحد الأقصى للرصيد (اختياري)',
                  hintText: 'مثال: 5000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.warning_amber,
                      color: Colors.orange),
                  suffixText: 'ريال',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v.trim());
                  if (n == null) return 'أدخل رقماً صحيحاً';
                  if (n <= 0) return 'يجب أن يكون أكبر من صفر';
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'عند تجاوز رصيد العميل هذا الحد، سيظهر تحذير بالأحمر.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.orange.shade200
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(isEdit ? 'حفظ التعديلات' : 'إضافة الحساب'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
