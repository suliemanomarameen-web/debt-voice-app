import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'backup_service.dart';
import 'crypto_service.dart';

class GDriveService {
  static const String _serverClientId =
      '889184576541-406c2kom3ka5491m9utf74rfjt7plovf.apps.googleusercontent.com';

  // 🆕 صلاحية كاملة — ضرورية للعمل مع حسابات Google متعددة
  // ⚠️ عند تسجيل الدخول القادم، سيطلب Google موافقة جديدة
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive',
  ];

  static const String _syncFileName = 'debt_sync_data.json';
  // 🆕 بادئة تُشير إلى أن محتوى الملف مشفر
  static const String _encryptedPrefix = 'ENC:1:';

  static GoogleSignIn? _googleSignIn;
  static GoogleSignInAccount? _currentUser;
  static drive.DriveApi? _driveApi;

  // ========== التهيئة ==========
  static GoogleSignIn get _signIn {
    if (_googleSignIn == null) {
      _googleSignIn = GoogleSignIn(
        scopes: _scopes,
        serverClientId: _serverClientId,
      );
    }
    return _googleSignIn!;
  }

  // ========== تسجيل الدخول ==========
  static Future<String?> signInWithError() async {
    try {
      debugPrint('🔵 [GDrive] Starting sign in...');

      final account = await _signIn.signIn();
      if (account == null) {
        debugPrint('🟡 [GDrive] User cancelled');
        return 'تم إلغاء تسجيل الدخول';
      }

      _currentUser = account;
      debugPrint('🟢 [GDrive] Got account: ${account.email}');

      final authClient = await _signIn.authenticatedClient();
      if (authClient == null) {
        debugPrint('🔴 [GDrive] authClient is null');
        return 'فشل الحصول على Auth Client\n\n'
            'تأكد من:\n'
            '1. SHA-1 مُسجَّل في Console\n'
            '2. Package name = ye.sulieman.debtbook\n'
            '3. انتظر 10 دقائق بعد الإضافة';
      }

      _driveApi = drive.DriveApi(authClient);
      debugPrint('✅ [GDrive] Signed in: ${account.email}');
      return null;
    } catch (e) {
      debugPrint('❌ [GDrive] Sign in error: $e');
      return 'خطأ:\n${e.toString()}';
    }
  }

  static Future<bool> signIn() async {
    final err = await signInWithError();
    return err == null;
  }

  static Future<void> signOut() async {
    try {
      await _signIn.signOut();
      _currentUser = null;
      _driveApi = null;
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  static bool get isSignedIn => _currentUser != null;
  static String? get userEmail => _currentUser?.email;
  static String? get userName => _currentUser?.displayName;

  static Future<bool> trySilentSignIn() async {
    try {
      final account = await _signIn.signInSilently();
      if (account == null) return false;
      _currentUser = account;

      final authClient = await _signIn.authenticatedClient();
      if (authClient == null) return false;

      _driveApi = drive.DriveApi(authClient);
      debugPrint('✅ [GDrive] Restored: ${account.email}');
      return true;
    } catch (e) {
      debugPrint('Silent sign-in error: $e');
      return false;
    }
  }

  static Future<bool> ensureSignedIn() async {
    if (_driveApi != null) return true;
    if (await trySilentSignIn()) return true;
    final err = await signInWithError();
    return err == null;
  }

  // ========== النسخ الاحتياطي القديم ==========
  static Future<Map<String, dynamic>> uploadBackup() async {
    try {
      if (_driveApi == null) {
        final err = await signInWithError();
        if (err != null) return {'success': false, 'message': err};
      }

      final backup = await BackupService.createBackup();
      if (!backup.success || backup.filePath == null) {
        return {'success': false, 'message': 'فشل إنشاء النسخة المحلية'};
      }

      final file = File(backup.filePath!);
      final fileName = backup.filePath!.split('/').last;
      final folderId = await _getOrCreateFolder('DebtBookBackups');

      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(file.openRead(), await file.length());
      final uploaded = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      debugPrint('✅ Uploaded: ${uploaded.name}');
      await _cleanOldBackups(folderId, keep: 5);

      return {
        'success': true,
        'file_id': uploaded.id,
        'file_name': uploaded.name,
        'message': 'تم الرفع بنجاح',
        'customers': backup.customersCount,
        'transactions': backup.transactionsCount,
      };
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      return {'success': false, 'message': 'فشل الرفع: $e'};
    }
  }

  static Future<List<Map<String, dynamic>>> listBackups() async {
    try {
      if (_driveApi == null) {
        if (!await trySilentSignIn()) {
          final err = await signInWithError();
          if (err != null) return [];
        }
      }

      final folderId = await _getOrCreateFolder('DebtBookBackups');

      final result = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed = false",
        orderBy: 'createdTime desc',
        $fields: 'files(id,name,createdTime,size)',
      );

      return (result.files ?? [])
          .map((f) => {
                'id': f.id ?? '',
                'name': f.name ?? '',
                'created': f.createdTime?.toIso8601String() ?? '',
                'size': f.size ?? '0',
              })
          .toList();
    } catch (e) {
      debugPrint('❌ List error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    try {
      if (_driveApi == null) {
        if (!await trySilentSignIn()) {
          final err = await signInWithError();
          if (err != null) return {'success': false, 'message': err};
        }
      }

      final fileInfo = await _driveApi!.files.get(fileId, $fields: 'name')
          as drive.File;
      final fileName = fileInfo.name ?? 'backup_drive.json';

      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/debt_book_backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final localFile = File('${backupDir.path}/$fileName');
      final sink = localFile.openWrite();
      await media.stream.pipe(sink);
      await sink.close();

      debugPrint('✅ Downloaded: $fileName');

      return {
        'success': true,
        'file_path': localFile.path,
        'file_name': fileName,
        'message': 'تم التحميل',
      };
    } catch (e) {
      debugPrint('❌ Download error: $e');
      return {'success': false, 'message': 'فشل التحميل: $e'};
    }
  }

  static Future<bool> deleteBackup(String fileId) async {
    try {
      if (_driveApi == null) {
        if (!await trySilentSignIn()) {
          final err = await signInWithError();
          if (err != null) return false;
        }
      }
      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 دوال المشاركة (لنظام المحاسبين المتعددين)
  // ═══════════════════════════════════════════════════════════

  /// مشاركة ملف مع إيميل محاسب آخر
  static Future<Map<String, dynamic>> shareFileWithEmail({
    required String fileId,
    required String email,
    String role = 'writer', // 'reader' | 'writer' | 'commenter'
    bool sendNotification = true,
  }) async {
    try {
      if (!await ensureSignedIn()) {
        return {'success': false, 'message': 'غير متصل'};
      }

      final cleanEmail = email.trim().toLowerCase();
      if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
        return {'success': false, 'message': 'بريد إلكتروني غير صالح'};
      }

      final permission = drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = cleanEmail;

      final created = await _driveApi!.permissions.create(
        permission,
        fileId,
        sendNotificationEmail: sendNotification,
      );

      debugPrint('✅ Shared $fileId with $cleanEmail as $role');

      return {
        'success': true,
        'permission_id': created.id,
        'message': 'تمت المشاركة بنجاح',
      };
    } catch (e) {
      debugPrint('❌ Share error: $e');
      return {'success': false, 'message': 'فشل المشاركة: $e'};
    }
  }

  /// قائمة من لديهم صلاحية على الملف
  static Future<List<Map<String, dynamic>>> listPermissions(
      String fileId) async {
    try {
      if (!await ensureSignedIn()) return [];

      final result = await _driveApi!.permissions.list(
        fileId,
        $fields: 'permissions(id,emailAddress,role,type,displayName,photoLink)',
      );

      return (result.permissions ?? [])
          .map((p) => {
                'id': p.id ?? '',
                'email': p.emailAddress ?? '',
                'role': p.role ?? '',
                'type': p.type ?? '',
                'displayName': p.displayName ?? '',
                'photoLink': p.photoLink ?? '',
              })
          .toList();
    } catch (e) {
      debugPrint('❌ List permissions error: $e');
      return [];
    }
  }

  /// إلغاء وصول إيميل من الملف
  static Future<bool> revokeAccess({
    required String fileId,
    required String email,
  }) async {
    try {
      if (!await ensureSignedIn()) return false;

      final permissions = await _driveApi!.permissions.list(
        fileId,
        $fields: 'permissions(id,emailAddress)',
      );

      final list = permissions.permissions ?? [];
      drive.Permission? target;
      for (final p in list) {
        if (p.emailAddress?.toLowerCase() == email.trim().toLowerCase()) {
          target = p;
          break;
        }
      }

      if (target?.id == null) {
        debugPrint('⚠️ Permission not found for $email');
        return false;
      }

      await _driveApi!.permissions.delete(fileId, target!.id!);
      debugPrint('✅ Revoked access for $email');
      return true;
    } catch (e) {
      debugPrint('❌ Revoke error: $e');
      return false;
    }
  }

  /// مشاركة ملف المزامنة الرئيسي مع إيميل
  static Future<Map<String, dynamic>> shareSyncFileWithEmail({
    required String email,
    String role = 'writer',
  }) async {
    final fileId = await getSyncFileId();
    if (fileId == null) {
      return {'success': false, 'message': 'ملف المزامنة غير موجود'};
    }
    return shareFileWithEmail(fileId: fileId, email: email, role: role);
  }

  /// عرض صلاحيات ملف المزامنة
  static Future<List<Map<String, dynamic>>> listSyncFilePermissions() async {
    final fileId = await getSyncFileId();
    if (fileId == null) return [];
    return listPermissions(fileId);
  }

  /// إلغاء وصول إيميل من ملف المزامنة
  static Future<bool> revokeSyncFileAccess(String email) async {
    final fileId = await getSyncFileId();
    if (fileId == null) return false;
    return revokeAccess(fileId: fileId, email: email);
  }

  // ═══════════════════════════════════════════════════════════
  // ملف المزامنة — مع دعم التشفير التلقائي
  // ═══════════════════════════════════════════════════════════

  static Future<String?> getSyncFileId() async {
    try {
      if (!await ensureSignedIn()) return null;

      final result = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false",
        $fields: 'files(id,name,modifiedTime)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }
      return null;
    } catch (e) {
      debugPrint('❌ getSyncFileId error: $e');
      return null;
    }
  }

  static Future<DateTime?> getSyncFileModifiedTime() async {
    try {
      if (!await ensureSignedIn()) return null;

      final result = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false",
        $fields: 'files(id,modifiedTime)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.modifiedTime;
      }
      return null;
    } catch (e) {
      debugPrint('❌ getSyncFileModifiedTime error: $e');
      return null;
    }
  }

  /// تحميل ملف المزامنة (يدعم المشفر وغير المشفر)
  static Future<Map<String, dynamic>?> downloadSyncFile() async {
    try {
      if (!await ensureSignedIn()) return null;

      final fileId = await getSyncFileId();
      if (fileId == null) return null;

      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }

      final content = utf8.decode(chunks);

      // 🆕 ملف مشفر؟
      if (content.startsWith(_encryptedPrefix)) {
        debugPrint('🔐 Detected encrypted sync file — decrypting...');
        final base64Payload = content.substring(_encryptedPrefix.length);
        try {
          return await CryptoService.decryptData(base64Payload);
        } catch (e) {
          debugPrint('❌ Decrypt failed (wrong password?): $e');
          return null;
        }
      }

      // ملف عادي (JSON)
      debugPrint('📄 Detected plain sync file');
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ downloadSyncFile error: $e');
      return null;
    }
  }

  /// رفع ملف المزامنة (يشفر تلقائياً إذا كانت ميزة التشفير مفعلة)
  static Future<bool> uploadSyncFile(Map<String, dynamic> data) async {
    try {
      if (!await ensureSignedIn()) return false;

      // 🆕 هل التشفير مفعل على هذا الجهاز؟
      final encryptEnabled = await CryptoService.isEncryptionEnabled();

      String content;
      if (encryptEnabled) {
        final encrypted = await CryptoService.encryptData(data);
        content = '$_encryptedPrefix$encrypted';
        debugPrint('🔐 Uploading ENCRYPTED sync file');
      } else {
        content = jsonEncode(data);
        debugPrint('📄 Uploading PLAIN sync file');
      }

      final bytes = utf8.encode(content);
      final existingId = await getSyncFileId();

      if (existingId != null) {
        final driveFile = drive.File();
        final media = drive.Media(Stream.value(bytes), bytes.length);
        await _driveApi!.files.update(
          driveFile,
          existingId,
          uploadMedia: media,
        );
        debugPrint('✅ Sync file updated');
      } else {
        final driveFile = drive.File()
          ..name = _syncFileName
          ..mimeType = 'application/json';
        final media = drive.Media(Stream.value(bytes), bytes.length);
        await _driveApi!.files.create(driveFile, uploadMedia: media);
        debugPrint('✅ Sync file created');
      }
      return true;
    } catch (e) {
      debugPrint('❌ uploadSyncFile error: $e');
      return false;
    }
  }

  // ========== إدارة المجلدات ==========
  static Future<String> _getOrCreateFolder(String name) async {
    try {
      final result = await _driveApi!.files.list(
        q: "name = '$name' "
            "and mimeType = 'application/vnd.google-apps.folder' "
            "and trashed = false",
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id!;
      }

      final folder = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await _driveApi!.files.create(folder);
      return created.id!;
    } catch (e) {
      debugPrint('Folder error: $e');
      rethrow;
    }
  }

  static Future<void> _cleanOldBackups(String folderId,
      {int keep = 5}) async {
    try {
      final result = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed = false",
        orderBy: 'createdTime desc',
      );

      final files = result.files ?? [];
      if (files.length <= keep) return;

      for (final file in files.skip(keep)) {
        try {
          if (file.id != null) {
            await _driveApi!.files.delete(file.id!);
          }
        } catch (e) {
          debugPrint('Delete old error: $e');
        }
      }
    } catch (e) {
      debugPrint('Clean error: $e');
    }
  }
}
