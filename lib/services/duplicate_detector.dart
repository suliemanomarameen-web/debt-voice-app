import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/app_settings.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import 'settings_service.dart';

/// كاشف التكرارات — يطابق السجلات السحابية بالمحلية
class DuplicateDetector {
  static Future<int> detect(Map<String, dynamic> cloudData) async {
    if (!SettingsService.getBool(
      AppSettings.duplicateDetectionEnabled,
      defaultValue: true,
    )) {
      debugPrint('🔀 [Detector] Disabled — skipping');
      return 0;
    }

    final db = DatabaseHelper.instance;
    final now = DateTime.now().toIso8601String();
    int found = 0;

    // 🆕 الحد الأقصى للتكرارات في جلسة واحدة
    final maxDuplicates = SettingsService.getInt(
      AppSettings.maxDuplicatesPerSync,
      defaultValue: 50,
    );
    bool reachedMax() => maxDuplicates > 0 && found >= maxDuplicates;

    // ═══════════════════════════════════════════════════
    // 1) العملاء
    // ═══════════════════════════════════════════════════
    final cloudCustomers = (cloudData['customers'] as List?) ?? [];
    final localCustomers = await db.allCustomersWithDeleted();

    for (final cloudC in cloudCustomers) {
      if (reachedMax()) break;

      final cloudId = cloudC['cloud_id'] as String?;
      final cloudName = cloudC['name'] as String? ?? '';

      if (cloudId == null || cloudId.isEmpty) continue;
      if (await db.hasTombstone(cloudId)) continue;

      bool isSameRecord = false;
      for (final localC in localCustomers) {
        if (localC.cloudId == cloudId) {
          isSameRecord = true;
          break;
        }
      }
      if (isSameRecord) continue;

      for (final localC in localCustomers) {
        if (reachedMax()) break;
        if (localC.cloudId == cloudId) continue;
        if (localC.cloudId == null || localC.cloudId!.isEmpty) continue;
        if (localC.isPermanentlyDeleted) continue;

        final cmp = _compareNames(cloudName, localC.name);
        if (cmp.level == 'different') continue;
        if (!_isLevelEnabled(cmp.level)) continue;

        final existing = await db.database.then((d) => d.query(
              'pending_duplicates',
              where:
                  'local_cloud_id = ? AND cloud_cloud_id = ? AND type = ? AND status IN (?, ?)',
              whereArgs: [
                localC.cloudId,
                cloudId,
                'customer',
                'pending',
                'skipped',
              ],
              limit: 1,
            ));
        if (existing.isNotEmpty) continue;

        await db.insertPendingDuplicate({
          'type': 'customer',
          'local_cloud_id': localC.cloudId,
          'cloud_cloud_id': cloudId,
          'similarity_score': cmp.score,
          'similarity_level': cmp.level,
          'detected_at': now,
          'status': 'pending',
          'metadata': jsonEncode({
            'local_name': localC.name,
            'cloud_name': cloudName,
            'local_phone': localC.phone,
            'cloud_phone': cloudC['phone'],
          }),
        });
        found++;
        debugPrint(
            '🔀 [Detector] Customer: "${localC.name}" ↔ "$cloudName" (${cmp.level})');
      }
    }

    // ═══════════════════════════════════════════════════
    // 2) العمليات
    // ═══════════════════════════════════════════════════

    // 🆕 خريطة معرّف العميل السحابي → معرّفه المحلي
    final cloudCustomerIdToLocal = <int, int>{};
    for (final cloudC in cloudCustomers) {
      final cloudId = cloudC['id'] as int?;
      final cloudCloudId = cloudC['cloud_id'] as String?;
      if (cloudId == null ||
          cloudCloudId == null ||
          cloudCloudId.isEmpty) {
        continue;
      }
      for (final localC in localCustomers) {
        if (localC.cloudId == cloudCloudId && localC.id != null) {
          cloudCustomerIdToLocal[cloudId] = localC.id!;
          break;
        }
      }
    }

    final cloudTransactions = (cloudData['transactions'] as List?) ?? [];
    final localTransactions = await db.allTransactionsWithDeleted();

    for (final cloudT in cloudTransactions) {
      if (reachedMax()) break;

      final cloudId = cloudT['cloud_id'] as String?;
      if (cloudId == null || cloudId.isEmpty) continue;
      if (await db.hasTombstone(cloudId)) continue;

      bool isSameRecord = false;
      for (final localT in localTransactions) {
        if (localT.cloudId == cloudId) {
          isSameRecord = true;
          break;
        }
      }
      if (isSameRecord) continue;

      for (final localT in localTransactions) {
        if (reachedMax()) break;
        if (localT.cloudId == cloudId) continue;
        if (localT.cloudId == null || localT.cloudId!.isEmpty) continue;
        if (localT.isDeleted) continue;

        // 🆕 فحص التكرار حسب الوضع
        final isDup = _isTransactionDuplicate(
          localT: localT,
          cloudT: cloudT,
          cloudCustomerIdToLocal: cloudCustomerIdToLocal,
        );
        if (!isDup) continue;

        final existing = await db.database.then((d) => d.query(
              'pending_duplicates',
              where:
                  'local_cloud_id = ? AND cloud_cloud_id = ? AND type = ? AND status IN (?, ?)',
              whereArgs: [
                localT.cloudId,
                cloudId,
                'transaction',
                'pending',
                'skipped',
              ],
              limit: 1,
            ));
        if (existing.isNotEmpty) continue;

        final mode = SettingsService.getString(
          AppSettings.transactionDuplicateMode,
          defaultValue: 'code',
        );

        await db.insertPendingDuplicate({
          'type': 'transaction',
          'local_cloud_id': localT.cloudId,
          'cloud_cloud_id': cloudId,
          'similarity_score': 1.0,
          'similarity_level': 'confirmed',
          'detected_at': now,
          'status': 'pending',
          'metadata': jsonEncode({
            'code': cloudT['code'],
            'amount': cloudT['amount'],
            'type': cloudT['type'],
            'mode': mode,
          }),
        });
        found++;
        debugPrint(
            '🔀 [Detector] Transaction: ${cloudT['code'] ?? cloudT['amount']} (mode=$mode)');
      }
    }

    debugPrint(
        '🔀 [Detector] Detected $found new duplicates${reachedMax() ? " (max reached)" : ""}');
    return found;
  }

  /// 🆕 هل العملية مكررة بناءً على الوضع المختار؟
  static bool _isTransactionDuplicate({
    required Transaction localT,
    required Map<String, dynamic> cloudT,
    required Map<int, int> cloudCustomerIdToLocal,
  }) {
    final mode = SettingsService.getString(
      AppSettings.transactionDuplicateMode,
      defaultValue: 'code',
    );

    switch (mode) {
      case 'code':
        // نفس رمز العملية
        final cloudCode = cloudT['code'] as String?;
        return cloudCode != null &&
            cloudCode.isNotEmpty &&
            localT.code == cloudCode;

      case 'basic':
        // نفس العميل + المبلغ + النوع
        final cloudCustomerId = cloudT['customer_id'] as int?;
        final localCustomerId = cloudCustomerIdToLocal[cloudCustomerId];
        if (localCustomerId == null) return false;
        if (localT.customerId != localCustomerId) return false;

        final cloudAmount = (cloudT['amount'] as num?)?.toDouble();
        if (cloudAmount == null) return false;
        if ((localT.amount - cloudAmount).abs() >= 0.01) return false;

        final cloudType = cloudT['type'] as String?;
        return localT.type == cloudType;

      case 'window':
        // نفس العميل + المبلغ + النوع + ضمن نافذة زمنية
        final cloudCustomerId = cloudT['customer_id'] as int?;
        final localCustomerId = cloudCustomerIdToLocal[cloudCustomerId];
        if (localCustomerId == null) return false;
        if (localT.customerId != localCustomerId) return false;

        final cloudAmount = (cloudT['amount'] as num?)?.toDouble();
        if (cloudAmount == null) return false;
        if ((localT.amount - cloudAmount).abs() >= 0.01) return false;

        final cloudType = cloudT['type'] as String?;
        if (localT.type != cloudType) return false;

        final windowMin = SettingsService.getInt(
          AppSettings.transactionWindowMinutes,
          defaultValue: 30,
        );
        try {
          final t1 = DateTime.parse(localT.createdAt);
          final t2 = DateTime.parse(cloudT['created_at'] as String? ?? '');
          return t1.difference(t2).inMinutes.abs() <= windowMin;
        } catch (_) {
          return false;
        }

      default:
        return false;
    }
  }

  static Future<bool> shouldBlockSync() async {
    final count = await getBlockingCount();
    return count > 0;
  }

  static Future<int> getBlockingCount() async {
    final db = DatabaseHelper.instance;
    final duplicates = await db.getUnresolvedDuplicatesRaw();

    int blocking = 0;
    for (final row in duplicates) {
      final level = row['similarity_level'] as String? ?? 'confirmed';
      if (_isBlockingLevel(level)) blocking++;
    }
    return blocking;
  }

  static bool _isBlockingLevel(String level) {
    switch (level) {
      case 'confirmed':
        return SettingsService.getBool(
            AppSettings.blockSyncOnConfirmed,
            defaultValue: true);
      case 'likely':
        return SettingsService.getBool(
            AppSettings.blockSyncOnLikely,
            defaultValue: false);
      case 'weak':
        return SettingsService.getBool(
            AppSettings.blockSyncOnWeak,
            defaultValue: false);
      case 'similar':
        return SettingsService.getBool(
            AppSettings.blockSyncOnSimilar,
            defaultValue: false);
      default:
        return false;
    }
  }

  static bool _isLevelEnabled(String level) {
    final mode = SettingsService.getString(
      AppSettings.duplicateDetectionLevel,
      defaultValue: 'balanced',
    );

    switch (mode) {
      case 'strict':
        return level == 'confirmed';
      case 'balanced':
        return level == 'confirmed' || level == 'likely';
      case 'flexible':
        return level != 'different';
      case 'custom':
        return _isBlockingLevel(level) || level == 'confirmed';
      default:
        return level == 'confirmed' || level == 'likely';
    }
  }

  static NameComparison _compareNames(String a, String b) {
    final normA = _normalize(a);
    final normB = _normalize(b);

    if (normA.isEmpty || normB.isEmpty) {
      return NameComparison(level: 'different', score: 0.0);
    }

    if (normA == normB) {
      return NameComparison(level: 'confirmed', score: 1.0);
    }

    final wordsA = normA.split(' ').where((w) => w.isNotEmpty).toList();
    final wordsB = normB.split(' ').where((w) => w.isNotEmpty).toList();

    final shorter = wordsA.length <= wordsB.length ? wordsA : wordsB;
    final longer = wordsA.length > wordsB.length ? wordsA : wordsB;

    bool isPrefix = shorter.isNotEmpty;
    for (int i = 0; i < shorter.length; i++) {
      if (shorter[i] != longer[i]) {
        isPrefix = false;
        break;
      }
    }

    if (isPrefix) {
      if (shorter.length >= 2) {
        return NameComparison(level: 'likely', score: 0.9);
      } else {
        if (SettingsService.getBool(
          AppSettings.detectHighSimilarity,
          defaultValue: true,
        )) {
          return NameComparison(level: 'weak', score: 0.5);
        }
        return NameComparison(level: 'different', score: 0.0);
      }
    }

    if (wordsA.length == wordsB.length &&
        SettingsService.getBool(
          AppSettings.detectHighSimilarity,
          defaultValue: true,
        )) {
      final dist = _levenshtein(normA, normB);
      if (dist == 1) {
        return NameComparison(level: 'similar', score: 0.85);
      }
    }

    return NameComparison(level: 'different', score: 0.0);
  }

  static String _normalize(String input) {
    String n = input.trim();
    if (n.isEmpty) return '';

    n = n.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    n = n.replaceAll('\u0640', '');

    if (SettingsService.getBool(
      AppSettings.normalizeHamza,
      defaultValue: true,
    )) {
      n = n.replaceAll(RegExp(r'[أإآ]'), 'ا');
    }

    if (SettingsService.getBool(
      AppSettings.normalizeTaaMarbuta,
      defaultValue: true,
    )) {
      n = n.replaceAll('ة', 'ه');
    }

    n = n.replaceAll('ى', 'ي');
    n = n.replaceAll('ئ', 'ي');
    n = n.replaceAll('ؤ', 'و');

    final compoundMode = SettingsService.getString(
      AppSettings.compoundNameHandling,
      defaultValue: 'auto',
    );
    if (compoundMode == 'auto') {
      n = n.replaceAll(RegExp(r'\b(عبد|ابو|ابن|ام|بنت)\s+'), r'$1');
    }

    n = n.replaceAll(RegExp(r'\s+'), ' ');

    return n.toLowerCase().trim();
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );

    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }

    return matrix[a.length][b.length];
  }
}

class NameComparison {
  final String level;
  final double score;
  NameComparison({required this.level, required this.score});
}

// Duplicate Detector v1: نظام الكشف عن التكرارات (تطبيع عربي + مقارنة + حظر) — المرحلة 2
// Duplicate Detector v2: ربط transactionDuplicateMode وtransactionWindowMinutes وmaxDuplicatesPerSync
