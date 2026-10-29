import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_service.dart';
import 'crypto_service.dart';

/// نتيجة تنزيل الملف الخام (قبل فك التشفير)
class RawSyncFile {
  final bool isEncrypted;
  final String? encryptedPayload;
  final Map<String, dynamic>? plainData;

  RawSyncFile({
    required this.isEncrypted,
    this.encryptedPayload,
    this.plainData,
  });
}

class GDriveService {
  static const String _serverClientId =
      '889184576541-406c2kom3ka5491m9utf74rfjt7plovf.apps.googleusercontent.com';

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive',
  ];

  static const String _syncFileName = 'debt_sync_data.json';
  static const String _encryptedPrefix = 'ENC:1:';

  // مفتاح تخزين معرف الملف المشترك
  static const String _keyLinkedFileId = 'linked_sync_file_id';

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
  // دوال المشاركة
  // ═══════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> shareFileWithEmail({
    required String fileId,
    required String email,
    String role = 'writer',
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

  static Future<List<Map<String, dynamic>>> listSyncFilePermissions() async {
    final fileId = await getSyncFileId();
    if (fileId == null) return [];
    return listPermissions(fileId);
  }

  static Future<bool> revokeSyncFileAccess(String email) async {
    final fileId = await getSyncFileId();
    if (fileId == null) return false;
    return revokeAccess(fileId: fileId, email: email);
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 إدارة معرف الملف المشترك
  // ═══════════════════════════════════════════════════════════

  static Future<void> setLinkedFileId(String? fileId) async {
    final prefs = await SharedPreferences.getInstance();
    if (fileId == null || fileId.isEmpty) {
      await prefs.remove(_keyLinkedFileId);
      debugPrint('🔗 [GDrive] Cleared linked file ID');
    } else {
      await prefs.setString(_keyLinkedFileId, fileId);
      debugPrint('🔗 [GDrive] Linked to file: $fileId');
    }
  }

  static Future<String?> getLinkedFileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLinkedFileId);
  }

  // ═══════════════════════════════════════════════════════════
  // ملف المزامنة
  // ═══════════════════════════════════════════════════════════

  /// البحث عن ملف المزامنة الذي **أنشأه هذا الحساب**
  static Future<String?> getSyncFileId() async {
    try {
      if (!await ensureSignedIn()) return null;

      final result = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false and 'me' in owners",
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

  /// البحث عن ملف المزامنة المشترك معي
  static Future<String?> findSharedSyncFileId() async {
    try {
      if (!await ensureSignedIn()) return null;

      final result = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false and sharedWithMe = true",
        $fields: 'files(id,name,modifiedTime,owners(emailAddress))',
        orderBy: 'modifiedTime desc',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        final file = result.files!.first;
        debugPrint('🔗 [GDrive] Found shared sync file: ${file.id}');
        return file.id;
      }

      debugPrint('⚠️ [GDrive] Trying fallback search...');
      final fallback = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false",
        $fields: 'files(id,name,modifiedTime,owners(emailAddress))',
        orderBy: 'modifiedTime desc',
      );

      if (fallback.files != null && fallback.files!.isNotEmpty) {
        final myEmail = userEmail?.toLowerCase();
        for (final f in fallback.files!) {
          final ownerEmail = f.owners?.first.emailAddress?.toLowerCase();
          if (ownerEmail != myEmail) {
            debugPrint('🔗 [GDrive] Fallback found: ${f.id} (owner: $ownerEmail)');
            return f.id;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ findSharedSyncFileId error: $e');
      return null;
    }
  }

  /// تنزيل الملف الخام (للتحقق من التشفير)
  static Future<RawSyncFile?> downloadRawSyncFileById(String fileId) async {
    try {
      if (!await ensureSignedIn()) return null;

      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }

      final content = utf8.decode(chunks);

      if (content.startsWith(_encryptedPrefix)) {
        debugPrint('🔐 [GDrive] Raw: encrypted file detected');
        return RawSyncFile(
          isEncrypted: true,
          encryptedPayload: content.substring(_encryptedPrefix.length),
        );
      }

      debugPrint('📄 [GDrive] Raw: plain file detected');
      return RawSyncFile(
        isEncrypted: false,
        plainData: jsonDecode(content) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('❌ downloadRawSyncFileById error: $e');
      return null;
    }
  }

  /// تنزيل ملف المزامنة (مع فك التشفير تلقائياً)
  static Future<Map<String, dynamic>?> downloadSyncFileById(
      String fileId) async {
    try {
      if (!await ensureSignedIn()) return null;

      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
      }

      final content = utf8.decode(chunks);

      if (content.startsWith(_encryptedPrefix)) {
        debugPrint('🔐 Detected encrypted sync file — decrypting...');
        final base64Payload = content.substring(_encryptedPrefix.length);
        try {
          return await CryptoService.decryptData(base64Payload);
        } catch (e) {
          debugPrint('❌ Decrypt failed: $e');
          return null;
        }
      }

      debugPrint('📄 Detected plain sync file');
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ downloadSyncFileById error: $e');
      return null;
    }
  }

  /// حذف ملف المزامنة الخاص بي
  static Future<void> deleteOwnSyncFileIfExists() async {
    try {
      if (!await ensureSignedIn()) return;

      final myFileId = await getSyncFileId();
      if (myFileId != null) {
        await _driveApi!.files.delete(myFileId);
        debugPrint('🗑️ [GDrive] Deleted own sync file (now secondary)');
      }
    } catch (e) {
      debugPrint('⚠️ deleteOwnSyncFileIfExists error: $e');
    }
  }

  static Future<DateTime?> getSyncFileModifiedTime() async {
    try {
      if (!await ensureSignedIn()) return null;

      final result = await _driveApi!.files.list(
        q: "name = '$_syncFileName' and trashed = false",
        $fields: 'files(id,modifiedTime)',
        orderBy: 'modifiedTime desc',
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

  /// تنزيل ملف المزامنة (مع الأخذ بالاعتبار الملف المشترك)
  static Future<Map<String, dynamic>?> downloadSyncFile() async {
    try {
      if (!await ensureSignedIn()) return null;

      var fileId = await getLinkedFileId();
      if (fileId != null && fileId.isNotEmpty) {
        debugPrint('🔗 [GDrive] Downloading from linked file: $fileId');
      } else {
        fileId = await getSyncFileId();
        if (fileId != null) {
          debugPrint('📄 [GDrive] Downloading from own file: $fileId');
        } else {
          fileId = await findSharedSyncFileId();
          if (fileId != null) {
            debugPrint('🔗 [GDrive] Downloading from shared file: $fileId');
          }
        }
      }

      if (fileId == null) return null;

      return await downloadSyncFileById(fileId);
    } catch (e) {
      debugPrint('❌ downloadSyncFile error: $e');
      return null;
    }
  }

  /// رفع ملف المزامنة (مع الأخذ بالاعتبار الملف المشترك)
  static Future<bool> uploadSyncFile(Map<String, dynamic> data) async {
    try {
      if (!await ensureSignedIn()) return false;

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

      final linkedId = await getLinkedFileId();
      final ownId = await getSyncFileId();
      final targetId = (linkedId != null && linkedId.isNotEmpty)
          ? linkedId
          : ownId;

      if (targetId != null) {
        final driveFile = drive.File();
        final media = drive.Media(Stream.value(bytes), bytes.length);
        await _driveApi!.files.update(
          driveFile,
          targetId,
          uploadMedia: media,
        );
        debugPrint('✅ Sync file updated: $targetId');
      } else {
        final driveFile = drive.File()
          ..name = _syncFileName
          ..mimeType = 'application/json';
        final media = drive.Media(Stream.value(bytes), bytes.length);
        await _driveApi!.files.create(driveFile, uploadMedia: media);
        debugPrint('✅ Sync file created (own)');
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
