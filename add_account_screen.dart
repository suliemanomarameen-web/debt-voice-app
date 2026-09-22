import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _note = TextEditingController(text: c?.note ?? '');
    _type = c?.accountType ?? AccountType.customer;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = DatabaseHelper.instance;
    if (widget.existing != null) {
      await db.updateCustomer(Customer(
        id: widget.existing!.id,
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        accountType: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAt: widget.existing!.createdAt,
      ));
    } else {
      await db.insertCustomer(Customer(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        accountType: _type,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حساب جديد')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'الاسم *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'النوع', border: OutlineInputBorder()),
                items: AccountType.all
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(AccountType.labelsAr[t]!)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'الهاتف', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'ملاحظة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}