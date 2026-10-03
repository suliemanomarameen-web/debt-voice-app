import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/account_type.dart';
import '../models/customer.dart';

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
    _type = c?.accountType ?? AccountType.customer;
    _category = c?.category ?? CustomerCategory.normal;
    _photoPath = c?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  // ============== اختيار صورة ==============
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

      // احفظ الصورة في مجلد التطبيق
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/customer_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final fileName =
          'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${photosDir.path}/$fileName';

      // انسخ الملف
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

  // ============== حفظ ==============
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    final db = DatabaseHelper.instance;

    if (isEdit) {
      await db.updateCustomer(Customer(
        id: widget.existing!.id,
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        accountType: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoPath: _photoPath,
        category: _category,
        createdAt: widget.existing!.createdAt,
      ));
    } else {
      await db.insertCustomer(Customer(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        accountType: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        photoPath: _photoPath,
        category: _category,
        createdAt: DateTime.now().toIso8601String(),
      ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  // ============== حذف ==============
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('سيتم حذف "${widget.existing!.name}" وكل معاملاته.'),
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
    if (ok != true) return;
    await DatabaseHelper.instance.deleteCustomer(widget.existing!.id!);
    if (mounted) Navigator.pop(context, true);
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
                onPressed: _delete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ============== صورة العميل ==============
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
                  _photoPath == null ? 'اضغط لإضافة صورة' : 'اضغط لتغيير الصورة',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ============== الاسم ==============
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

              // ============== النوع (عميل/مورد) ==============
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

              // ============== التصنيف ==============
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

              // ============== الهاتف ==============
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

              // ============== ملاحظة ==============
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

              // ============== حفظ ==============
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
