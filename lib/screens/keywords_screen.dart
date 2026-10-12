import 'package:flutter/material.dart';
import '../services/keywords_service.dart';

class KeywordsScreen extends StatefulWidget {
  const KeywordsScreen({super.key});

  @override
  State<KeywordsScreen> createState() => _KeywordsScreenState();
}

class _KeywordsScreenState extends State<KeywordsScreen> {
  @override
  void initState() {
    super.initState();
    // نضمن أن الكلمات محمّلة
    KeywordsService.reload().then((_) {
      if (mounted) setState(() {});
    });
  }

  // ============================================================
  // نافذة إضافة كلمة جديدة
  // ============================================================
  Future<void> _showAddDialog(String category) async {
    final ctrl = TextEditingController();
    final theme = Theme.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Text(
                KeywordsService.categoryEmojis[category] ?? '➕',
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              const Text('إضافة كلمة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'الكلمة أو العبارة',
                  hintText: 'مثال: سجل على',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.text_fields),
                ),
                onSubmitted: (v) {
                  final v2 = v.trim();
                  if (v2.isNotEmpty) Navigator.pop(ctx, v2);
                },
              ),
              const SizedBox(height: 12),
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
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'يمكن أن تكون الكلمة عبارة كاملة. '
                        'الفهم يقبل أن يقول المستخدم إحدى هذه العبارات.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isNotEmpty) Navigator.pop(ctx, v);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    await KeywordsService.add(category, result);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تمت إضافة "$result"'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // تأكيد استعادة الافتراضي لفئة
  // ============================================================
  Future<void> _confirmReset(String category) async {
    final label =
        KeywordsService.categoryLabelsAr[category] ?? category;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore, color: Colors.orange),
              SizedBox(width: 8),
              Text('استعادة الافتراضي'),
            ],
          ),
          content: Text(
            'سيتم استعادة كلمات "$label" إلى القيم الافتراضية.\n\n'
            'هل أنت متأكد؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    await KeywordsService.reset(category);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تمت استعادة "$label"'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // تأكيد استعادة الكل
  // ============================================================
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
              Text('استعادة كل الكلمات'),
            ],
          ),
          content: const Text(
            '⚠️ سيتم حذف كل التعديلات في كل الفئات، والعودة للقيم الافتراضية.\n\n'
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
    await KeywordsService.resetAll();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تمت استعادة كل الكلمات'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============================================================
  // بناء البطاقة لكل فئة
  // ============================================================
  Widget _buildCategoryCard(String category, ThemeData theme) {
    final keywords = KeywordsService.get(category);
    final isModified = KeywordsService.isModified(category);
    final emoji = KeywordsService.categoryEmojis[category] ?? '📌';
    final label = KeywordsService.categoryLabelsAr[category] ?? category;
    final description =
        KeywordsService.categoryDescriptions[category] ?? '';

    final accentColor = isModified ? Colors.orange : theme.colorScheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== الرأس =====
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (isModified) ...[
                            const SizedBox(width: 6),
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
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${keywords.length} كلمة',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.restore, size: 20),
                  tooltip: 'استعادة الافتراضي',
                  onPressed:
                      isModified ? () => _confirmReset(category) : null,
                ),
              ],
            ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ===== Chip-list للكلمات =====
            if (keywords.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'لا توجد كلمات. اضغط + لإضافة.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: keywords.map((kw) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accentColor.withOpacity(0.4),
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          kw,
                          style: TextStyle(
                            fontSize: 12,
                            color: accentColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () async {
                            await KeywordsService.remove(category, kw);
                            if (!mounted) return;
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 10),

            // ===== زر إضافة كلمة =====
            OutlinedButton.icon(
              onPressed: () => _showAddDialog(category),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة كلمة'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // البناء الرئيسي
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMod = KeywordsService.hasAnyModification();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('كلمات الفهم الصوتي'),
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
                      'هذه الكلمات يستخدمها التطبيق لفهم ما تقوله. '
                      'كلما أضفت كلمات أكثر (حسب لهجتك)، كان الفهم أفضل. '
                      'التعديلات تُطبّق فوراً — بدون إعادة بناء.',
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

            // ===== الفئات =====
            ...KeywordsService.allCategories.map((cat) {
              return _buildCategoryCard(cat, theme);
            }),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
