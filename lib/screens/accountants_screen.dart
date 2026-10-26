import 'package:flutter/material.dart';
import '../services/accountants_service.dart';
import '../services/accountant_service.dart';
import '../services/device_service.dart';
import '../services/gdrive_service.dart';
import 'link_to_primary_screen.dart'; // 🆕

class AccountantsScreen extends StatefulWidget {
  const AccountantsScreen({super.key});

  @override
  State<AccountantsScreen> createState() => _AccountantsScreenState();
}

class _AccountantsScreenState extends State<AccountantsScreen> {
  List<Accountant> _accountants = [];
  List<PendingDevice> _pendingDevices = [];
  Accountant? _myAccountant;
  String? _myDeviceId;
  String? _myDeviceName;
  bool _isPrimary = false;
  bool _canManage = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      await AccountantsService.reload();
      _myDeviceId = await DeviceService.getDeviceId();
      _myDeviceName = await DeviceService.getDeviceName();
      _myAccountant = await AccountantsService.getCurrentAccountant();
      _isPrimary = await DeviceService.isPrimaryDevice();
      _canManage = _isPrimary ||
          (_myAccountant?.can('manage_accountants') ?? false);

      _accountants = AccountantsService.getAll();
      _pendingDevices = AccountantsService.getPendingDevices();
    } catch (e) {
      debugPrint('Load error: $e');
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 ربط بالأساسي
  // ═══════════════════════════════════════════════════════════
  Future<void> _linkToPrimary() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LinkToPrimaryScreen(),
      ),
    );

    if (result == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم ربط الجهاز بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ========== تعيين نفسي كمحاسب ==========
  Future<void> _registerSelf() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعيين نفسي كمحاسب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسمك',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'رمزك (S، AHM، ...)',
                  border: OutlineInputBorder(),
                  counterText: '',
                  helperText: 'اختياري',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result != true || nameCtrl.text.trim().isEmpty) return;

    final isPrimaryDevice = await DeviceService.isPrimaryDevice();

    final perms = <String, bool>{};
    for (final e in Accountant.defaultPermissions.entries) {
      perms[e.key] = isPrimaryDevice ? true : e.value;
    }

    final res = await AccountantsService.addAccountant(
      name: nameCtrl.text.trim(),
      code: codeCtrl.text.trim(),
      deviceId: _myDeviceId,
      isPrimary: isPrimaryDevice,
      permissions: perms,
    );

    if (res['success'] != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] as String? ?? 'فشل التسجيل'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await AccountantService.setAccountantName(nameCtrl.text.trim());

    _load();
  }

  // ========== إضافة محاسب ==========
  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String? error;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add, color: Colors.teal),
                SizedBox(width: 8),
                Text('محاسب جديد'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codeCtrl,
                    maxLength: 5,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'الرمز',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                      counterText: '',
                      helperText: 'اختياري — يُضاف لرمز العمليات',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'الإيميل (اختياري)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                      helperText: 'للمشاركة عبر Google Drive',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          setSt(() => error = 'الاسم مطلوب');
                          return;
                        }
                        setSt(() {
                          saving = true;
                          error = null;
                        });

                        final res = await AccountantsService.addAccountant(
                          name: nameCtrl.text,
                          code: codeCtrl.text,
                          email: emailCtrl.text.trim().isEmpty
                              ? null
                              : emailCtrl.text.trim(),
                        );

                        if (res['success'] != true) {
                          setSt(() {
                            saving = false;
                            error = res['message'] as String? ?? 'فشل';
                          });
                          return;
                        }

                        final email = emailCtrl.text.trim();
                        if (email.isNotEmpty && _isPrimary) {
                          final shareRes = await GDriveService
                              .shareSyncFileWithEmail(
                            email: email,
                            role: 'writer',
                          );
                          if (shareRes['success'] != true) {
                            debugPrint(
                                '⚠️ Share failed: ${shareRes['message']}');
                          }
                        }

                        if (ctx.mounted) Navigator.pop(ctx, true);
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) _load();
  }

  // ========== تعديل محاسب ==========
  Future<void> _showEditDialog(Accountant acc) async {
    final nameCtrl = TextEditingController(text: acc.name);
    final codeCtrl = TextEditingController(text: acc.code);
    final emailCtrl = TextEditingController(text: acc.email ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل محاسب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'الرمز',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'الإيميل',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await AccountantsService.updateAccountant(
                  id: acc.id,
                  name: nameCtrl.text,
                  code: codeCtrl.text,
                  email: emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                );
                if (acc.deviceId == _myDeviceId &&
                    nameCtrl.text.trim().isNotEmpty) {
                  await AccountantService.setAccountantName(
                      nameCtrl.text.trim());
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _load();
  }

  // ========== الصلاحيات ==========
  Future<void> _showPermissionsDialog(Accountant acc) async {
    final perms = Map<String, bool>.from(acc.permissions);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.security, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'صلاحيات ${acc.name}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView(
                children: Accountant.defaultPermissions.keys.map((key) {
                  final label = Accountant.permissionLabelsAr[key] ?? key;
                  final isDangerous = key.startsWith('manage_') ||
                      key == 'access_advanced_settings' ||
                      key == 'can_become_primary' ||
                      key == 'delete_customers' ||
                      key == 'delete_transactions';
                  return SwitchListTile(
                    dense: true,
                    value: perms[key] ?? false,
                    title: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDangerous ? Colors.red.shade700 : null,
                        fontWeight: isDangerous
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onChanged: (v) => setSt(() => perms[key] = v),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () async {
                  await AccountantsService.updateAccountant(
                    id: acc.id,
                    permissions: perms,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) _load();
  }

  // ========== حذف محاسب ==========
  Future<void> _deleteAccountant(Accountant acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('حذف محاسب'),
            ],
          ),
          content: Text(
            'سيتم حذف "${acc.name}" نهائياً.\n'
            'لن يستطيع الوصول إلى المزامنة بعد الآن.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await AccountantsService.removeAccountant(acc.id);
    if (acc.email != null && acc.email!.isNotEmpty) {
      await GDriveService.revokeSyncFileAccess(acc.email!);
    }
    _load();
  }

  // ========== قبول جهاز ==========
  Future<void> _approveDevice(PendingDevice dev) async {
    final nameCtrl = TextEditingController(text: dev.deviceName);
    final codeCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified_user, color: Colors.green),
              SizedBox(width: 8),
              Text('ترخيص جهاز'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الجهاز: ${dev.deviceName}\n'
                '${dev.email != null ? "الإيميل: ${dev.email}" : ""}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المحاسب',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: codeCtrl,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'الرمز',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رفض'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('موافقة'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    await AccountantsService.approveDevice(
      deviceId: dev.deviceId,
      accountantName: nameCtrl.text.trim(),
      code: codeCtrl.text.trim(),
    );

    if (dev.email != null && dev.email!.isNotEmpty) {
      await GDriveService.shareSyncFileWithEmail(
        email: dev.email!,
        role: 'writer',
      );
    }

    _load();
  }

  // ========== عرض معلومات الجهاز ==========
  Future<void> _showDeviceInfo() async {
    final status = await DeviceService.getDeviceStatus();
    final primaryId = await DeviceService.getPrimaryDeviceId();
    final isPrimary = await DeviceService.isPrimaryDevice();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.phone_android, color: Colors.blue),
              SizedBox(width: 8),
              Text('معلومات هذا الجهاز'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('المعرف', _myDeviceId?.substring(0, 8) ?? '—'),
              _infoRow('الاسم', _myDeviceName ?? 'غير محدد'),
              _infoRow('الحالة', status),
              _infoRow('الأساسي؟', isPrimary ? 'نعم 👑' : 'لا'),
              if (primaryId != null)
                _infoRow('معرف الأساسي', primaryId.substring(0, 8)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(
                '$label:',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

  // ========== الواجهة ==========
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحاسبون والأجهزة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.link, color: Colors.teal),
              tooltip: '🔗 ربط بالأساسي',
              onPressed: _linkToPrimary,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        floatingActionButton: _canManage
            ? FloatingActionButton.extended(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('محاسب جديد'),
                backgroundColor: Colors.teal,
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildMyCard(theme),
                    const SizedBox(height: 16),

                    if (_pendingDevices.isNotEmpty && _canManage) ...[
                      _sectionTitle(
                        '⏳ طلبات الانضمام (${_pendingDevices.length})',
                        color: Colors.orange,
                      ),
                      ..._pendingDevices.map(_buildPendingCard),
                      const SizedBox(height: 16),
                    ],

                    _sectionTitle(
                      '👥 المحاسبون (${_accountants.length})',
                    ),
                    if (_accountants.isEmpty)
                      _emptyCard('لا يوجد محاسبون بعد')
                    else
                      ..._accountants.map(_buildAccountantCard),

                    const SizedBox(height: 24),

                    OutlinedButton.icon(
                      onPressed: _showDeviceInfo,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('معلومات هذا الجهاز'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMyCard(ThemeData theme) {
    final name = _myAccountant?.name ?? 'غير معروف';
    final code = _myAccountant?.code ?? '';
    final isPrimary = _myAccountant?.isPrimary ?? _isPrimary;

    return Card(
      color: isPrimary
          ? Colors.amber.withOpacity(0.15)
          : theme.colorScheme.primaryContainer.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      isPrimary ? Colors.amber : theme.colorScheme.primary,
                  child: Text(
                    isPrimary ? '👑' : '👤',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isPrimary
                            ? 'الجهاز الأساسي'
                            : 'محاسب على هذا الجهاز',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPrimary
                              ? Colors.amber.shade800
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (code.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
            if (_myAccountant == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '⚠️ لم يتم تعيينك كمحاسب على هذا الجهاز بعد.\n'
                  'اختر إحدى الطريقتين أدناه:',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),

              // 🆕 زر "ربط بالأساسي" — الخيار الأول (إذا كان لديك أساسي)
              FilledButton.icon(
                onPressed: _linkToPrimary,
                icon: const Icon(Icons.link),
                label: const Text('🔗 ربط بالأساسي'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.teal,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Divider(color: Colors.grey.shade400),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'أو',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: Colors.grey.shade400),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // الخيار الثاني: تعيين نفسي (إذا كنت الأساسي)
              OutlinedButton.icon(
                onPressed: _registerSelf,
                icon: const Icon(Icons.person_add),
                label: const Text('تعيين نفسي كمحاسب أساسي'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccountantCard(Accountant acc) {
    final isMe = acc.deviceId == _myDeviceId;
    final isPrimary = acc.isPrimary;
    final isActive = acc.status == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPrimary
          ? Colors.amber.withOpacity(0.08)
          : (!isActive ? Colors.grey.withOpacity(0.1) : null),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPrimary
              ? Colors.amber
              : (isActive ? Colors.teal : Colors.grey),
          child: Text(
            isPrimary ? '👑' : acc.name.characters.first,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                acc.name + (isMe ? ' (أنت)' : ''),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isActive ? null : Colors.grey,
                ),
              ),
            ),
            if (!isActive)
              const Text(
                'موقوف',
                style: TextStyle(fontSize: 10, color: Colors.orange),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (acc.code.isNotEmpty)
              Text('الرمز: ${acc.code}',
                  style: const TextStyle(fontSize: 11)),
            if (acc.email != null && acc.email!.isNotEmpty)
              Text(acc.email!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(
              'الصلاحيات: ${acc.permissions.values.where((v) => v).length} / ${acc.permissions.length}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: isPrimary
            ? const Icon(Icons.lock, size: 16, color: Colors.amber)
            : _canManage
                ? PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          _showEditDialog(acc);
                          break;
                        case 'permissions':
                          _showPermissionsDialog(acc);
                          break;
                        case 'delete':
                          _deleteAccountant(acc);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit, size: 18),
                          title: Text('تعديل',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'permissions',
                        child: ListTile(
                          leading: Icon(Icons.security, size: 18),
                          title: Text('الصلاحيات',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      if (!isMe)
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete,
                                color: Colors.red, size: 18),
                            title: Text('حذف',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.red)),
                          ),
                        ),
                    ],
                  )
                : null,
      ),
    );
  }

  Widget _buildPendingCard(PendingDevice dev) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.orange.withOpacity(0.08),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.phone_android, color: Colors.white),
        ),
        title: Text(
          dev.deviceName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '${dev.email ?? "بدون إيميل"}\n${_formatDate(dev.requestedAt)}',
          style: const TextStyle(fontSize: 10),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              tooltip: 'موافقة',
              onPressed: () => _approveDevice(dev),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              tooltip: 'رفض',
              onPressed: () async {
                await AccountantsService.rejectDevice(dev.deviceId);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.grey.shade700,
          ),
        ),
      );

  Widget _emptyCard(String msg) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ),
      );

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
