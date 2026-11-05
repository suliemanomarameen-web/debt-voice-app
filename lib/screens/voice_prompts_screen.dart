import 'package:flutter/material.dart';
import '../services/voice_prompts_service.dart';

/// شاشة تعديل أسئلة الحوار الصوتي والردود الصوتية
///
/// جدولان:
/// - 📋 الأسئلة (Prompts): ما يقوله التطبيق ليسأل
/// - 🔊 الردود (TTS): ما يُقرأ بصوت للمستخدم
class VoicePromptsScreen extends StatefulWidget {
  const VoicePromptsScreen({super.key});

  @override
  State<VoicePromptsScreen> createState() => _VoicePromptsScreenState();
}

class _VoicePromptsScreenState extends State<VoicePromptsScreen> {
  @override
  void initState() {
    super.initState();
    VoicePromptsService.reload().then((_) {
      if (mounted) setState(() {});
    });
  }

  // ═══════════════════════════════════════════════════════════
  // نافذة التعديل
  // ═══════════════════════════════════════════════════════════
  Future<void> _showEditDialog({
    required String key,
    required String title,
    required String currentValue,
    required String defaultValue,
    required bool isPrompt,
    required String hint,
  }) async {
    final ctrl = TextEditingController(text: currentValue);
    final theme = Theme.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                isPrompt ? Icons.help_outline : Icons.volume_up,
                color: isPrompt ? Colors.blue : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الحالي
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'الافتراضي: $defaultValue',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // مربع التعديل
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  minLines: 2,
                  autofocus: true,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: 'النص المخصص',
                    hintText: hint,
                    border: const OutlineInputBorder(),
                    helperText: isPrompt
                        ? 'المتغيرات المتاحة: {name}'
                        : 'المتغيرات: {type} {amount} {currency} {customer} {name} {summary} {max}',
                    helperMaxLines: 3,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, defaultValue),
              child: const Text('استعادة الافتراضي'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    if (isPrompt) {
      await VoicePromptsService.setPrompt(key, result);
    } else {
      await VoicePromptsService.setResponse(key, result);
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم الحفظ'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // تأكيد استعادة الكل
  // ═══════════════════════════════════════════════════════════
  Future<void> _confirmResetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red),
              SizedBox(width: 8),
              Text('استعادة كل النصوص'),
            ],
          ),
          content: const Text(
            '⚠️ سيتم حذف كل التعديلات والعودة للقيم الافتراضية.\n\n'
            'لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة الكل'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    await VoicePromptsService.resetAll();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تمت استعادة كل النصوص'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // بناء صف واحد
  // ═══════════════════════════════════════════════════════════
  Widget _buildRow({
    required String key,
    required String label,
    required String currentValue,
    required String defaultValue,
    required bool isPrompt,
    required String hint,
    required ThemeData theme,
  }) {
    final isModified = isPrompt
        ? VoicePromptsService.isPromptModified(key)
        : VoicePromptsService.isResponseModified(key);

    final accentColor = isPrompt ? Colors.blue : Colors.green;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => _showEditDialog(
          key: key,
          title: label,
          currentValue: currentValue,
          defaultValue: defaultValue,
          isPrompt: isPrompt,
          hint: hint,
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isPrompt ? Icons.help_outline : Icons.volume_up,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  if (isModified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        'مُعدّل',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  currentValue.isEmpty ? '(فارغ)' : currentValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // البناء
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompts = VoicePromptsService.getAllPrompts();
    final responses = VoicePromptsService.getAllResponses();
    final hasMod = VoicePromptsService.hasAnyModification;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أسئلة الحوار الصوتي'),
          actions: [
            if (hasMod)
              IconButton(
                icon: const Icon(Icons.restore_page),
                tooltip: 'استعادة الكل',
                onPressed: _confirmResetAll,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ===== معلومات =====
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'هذه النصوص يستخدمها التطبيق في الحوار الصوتي التفاعلي. '
                      'عدّلها حسب لهجتك — تُطبَّق فورًا بدون إعادة بناء.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ═══════════════════════════════════════════════
            // القسم 1: الأسئلة
            // ═══════════════════════════════════════════════
            _buildSectionHeader(
              '📋 الأسئلة',
              'ما يقوله التطبيق ليسألك',
              Colors.blue,
              theme,
            ),

            _buildRow(
              key: VoicePromptsService.pAskIntent,
              label: 'سؤال النوع',
              currentValue: prompts[VoicePromptsService.pAskIntent] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskIntent),
              isPrompt: true,
              hint: 'مثال: دين أم سداد؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskCustomerDebt,
              label: 'اسم الحساب (دين)',
              currentValue:
                  prompts[VoicePromptsService.pAskCustomerDebt] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskCustomerDebt),
              isPrompt: true,
              hint: 'مثال: على من أسجل؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskCustomerPayment,
              label: 'اسم الحساب (سداد)',
              currentValue:
                  prompts[VoicePromptsService.pAskCustomerPayment] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskCustomerPayment),
              isPrompt: true,
              hint: 'مثال: لمن أوصل؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskCustomerReturn,
              label: 'اسم الحساب (مرتجع)',
              currentValue:
                  prompts[VoicePromptsService.pAskCustomerReturn] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskCustomerReturn),
              isPrompt: true,
              hint: 'مثال: مرتجع على من؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskCustomerUnknown,
              label: 'اسم الحساب (نوع غير معروف)',
              currentValue:
                  prompts[VoicePromptsService.pAskCustomerUnknown] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskCustomerUnknown),
              isPrompt: true,
              hint: 'مثال: على من أسجل؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskAmount,
              label: 'سؤال المبلغ',
              currentValue: prompts[VoicePromptsService.pAskAmount] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskAmount),
              isPrompt: true,
              hint: 'مثال: كم المبلغ؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskItems,
              label: 'سؤال البيان',
              currentValue: prompts[VoicePromptsService.pAskItems] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskItems),
              isPrompt: true,
              hint: 'مثال: ما البيان؟ قل "بدون بيان" لتخطي السؤال',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAskCustomerAmbiguous,
              label: 'سؤال الحساب الغامض',
              currentValue:
                  prompts[VoicePromptsService.pAskCustomerAmbiguous] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAskCustomerAmbiguous),
              isPrompt: true,
              hint: 'مثال: لا يوجد حساب باسم "{name}" — هل تقصد أحد هؤلاء؟',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pConfirmChoice,
              label: 'تأكيد الاختيار',
              currentValue:
                  prompts[VoicePromptsService.pConfirmChoice] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pConfirmChoice),
              isPrompt: true,
              hint: 'مثال: قل الرقم أو الاسم، أو "أضف جديد"',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pCancelWord,
              label: 'كلمة الإلغاء',
              currentValue:
                  prompts[VoicePromptsService.pCancelWord] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pCancelWord),
              isPrompt: true,
              hint: 'مثال: إلغاء',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pSkipItemsWord,
              label: 'كلمة تخطي البيان',
              currentValue:
                  prompts[VoicePromptsService.pSkipItemsWord] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pSkipItemsWord),
              isPrompt: true,
              hint: 'مثال: بدون بيان',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.pAddNewCustomerWord,
              label: 'كلمة إضافة حساب جديد',
              currentValue:
                  prompts[VoicePromptsService.pAddNewCustomerWord] ?? '',
              defaultValue: VoicePromptsService.getDefaultPrompt(
                  VoicePromptsService.pAddNewCustomerWord),
              isPrompt: true,
              hint: 'مثال: أضف جديد',
              theme: theme,
            ),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════
            // القسم 2: الردود الصوتية
            // ═══════════════════════════════════════════════
            _buildSectionHeader(
              '🔊 الردود الصوتية',
              'ما يُقرأ لك بصوت أثناء الحوار',
              Colors.green,
              theme,
            ),

            _buildRow(
              key: VoicePromptsService.rStartListening,
              label: 'بدء الاستماع',
              currentValue:
                  responses[VoicePromptsService.rStartListening] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rStartListening),
              isPrompt: false,
              hint: 'مثال: جاري الاستماع...',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rStopListening,
              label: 'توقف الاستماع',
              currentValue:
                  responses[VoicePromptsService.rStopListening] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rStopListening),
              isPrompt: false,
              hint: 'مثال: تم',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rUnderstoodPartial,
              label: 'تأكيد الفهم الجزئي',
              currentValue:
                  responses[VoicePromptsService.rUnderstoodPartial] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rUnderstoodPartial),
              isPrompt: false,
              hint: 'مثال: فهمت: {summary}',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rConfirmSave,
              label: 'تأكيد قبل الحفظ',
              currentValue:
                  responses[VoicePromptsService.rConfirmSave] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rConfirmSave),
              isPrompt: false,
              hint:
                  'مثال: تم تسجيل {type} {amount} {currency} على {customer}',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rSavedSuccess,
              label: 'تأكيد بعد الحفظ',
              currentValue:
                  responses[VoicePromptsService.rSavedSuccess] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rSavedSuccess),
              isPrompt: false,
              hint: 'مثال: تم الحفظ بنجاح',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rUnknownMax,
              label: 'الاستسلام بعد محاولات',
              currentValue:
                  responses[VoicePromptsService.rUnknownMax] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rUnknownMax),
              isPrompt: false,
              hint:
                  'مثال: لم أفهمك بعد {max} محاولات. تم حفظ التسجيل في السجل.',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rNoAccount,
              label: 'عدم وجود حساب',
              currentValue:
                  responses[VoicePromptsService.rNoAccount] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rNoAccount),
              isPrompt: false,
              hint: 'مثال: لا يوجد حساب باسم {name}',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rCancelled,
              label: 'إلغاء العملية',
              currentValue:
                  responses[VoicePromptsService.rCancelled] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rCancelled),
              isPrompt: false,
              hint: 'مثال: تم الإلغاء',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rChooseFromList,
              label: 'بعد عرض المرشحين',
              currentValue:
                  responses[VoicePromptsService.rChooseFromList] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rChooseFromList),
              isPrompt: false,
              hint: 'مثال: قل الرقم أو الاسم',
              theme: theme,
            ),
            _buildRow(
              key: VoicePromptsService.rAddingNew,
              label: 'عند إضافة حساب جديد',
              currentValue:
                  responses[VoicePromptsService.rAddingNew] ?? '',
              defaultValue: VoicePromptsService.getDefaultResponse(
                  VoicePromptsService.rAddingNew),
              isPrompt: false,
              hint: 'مثال: سيتم إضافة حساب جديد باسم {name}',
              theme: theme,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle,
    Color color,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// شاشة أسئلة الحوار الصوتي v1: واجهة تعديل الأسئلة (12) والردود (10)
// - عرض النصوص الحالية مع تمييز "مُعدّل"
// - تعديل فوري لكل صف
// - استعادة الافتراضي لكل صف + استعادة الكل
// - تُطبَّق التعديلات فورًا بدون إعادة بناء
