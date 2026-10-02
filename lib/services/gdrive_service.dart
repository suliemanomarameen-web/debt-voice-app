import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'backup_service.dart';

class GDriveService {
  // ⚠️ Client ID من Google Cloud Console
  static const String _serverClientId =
      '889184576541-qvobtlhujbftskconckpkqfijbvb9rld.apps.googleusercontent.com';

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];

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
  static Future<bool> signIn() async {
    try {
      final account = await _signIn.signIn();
      if (account == null) return false;
      _currentUser = account;

      final authClient = await _signIn.authenticatedClient();
      if (authClient == null) return false;

      _driveApi = drive.DriveApi(authClient);
      debugPrint('✅ Signed in: ${account.email}');
      return true;
    } catch (e) {
      debugPrint('❌ Sign in error: $e');
      return false;
    }
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

  /// محاولة استرجاع الجلسة السابقة
  static Future<bool> trySilentSignIn() async {
    try {
      final account = await _signIn.signInSilently();
      if (account == null) return false;
      _currentUser = account;

      final authClient = await _signIn.authenticatedClient();
      if (authClient == null) return false;

      _driveApi = drive.DriveApi(authClient);
      debugPrint('✅ Restored session: ${account.email}');
      return true;
    } catch (e) {
      debugPrint('Silent sign-in error: $e');
      return false;
    }
  }

  // ========== رفع نسخة احتياطية ==========
  static Future<Map<String, dynamic>> uploadBackup() async {
    try {
      if (_driveApi == null) {
        final ok = await signIn();
        if (!ok) {
          return {
            'success': false,
            'message': 'يجب تسجيل الدخول أولاً',
          };
        }
      }

      final backup = await BackupService.createBackup();
      if (!backup.success || backup.filePath == null) {
        return {
          'success': false,
          'message': 'فشل إنشاء النسخة المحلية',
        };
      }

      final file = File(backup.filePath!);
      final fileName = backup.filePath!.split('/').last;

      final folderId = await _getOrCreateFolder('DebtBookBackups');

      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(
        file.openRead(),
        await file.length(),
      );

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
      return {
        'success': false,
        'message': 'فشل الرفع: $e',
      };
    }
  }

  // ========== قائمة النسخ على Drive ==========
  static Future<List<Map<String, dynamic>>> listBackups() async {
    try {
      if (_driveApi == null) {
        final ok = await trySilentSignIn() || await signIn();
        if (!ok) return [];
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

  // ========== تحميل نسخة من Drive ==========
  static Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    try {
      if (_driveApi == null) {
        final ok = await trySilentSignIn() || await signIn();
        if (!ok) {
          return {
            'success': false,
            'message': 'يجب تسجيل الدخول',
          };
        }
      }

      // ✅ التعديل: نوع صريح
      final fileInfo = await _driveApi!.files.get(
        fileId,
        $fields: 'name',
      ) as drive.File;
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
      return {
        'success': false,
        'message': 'فشل التحميل: $e',
      };
    }
  }

  // ========== حذف نسخة من Drive ==========
  static Future<bool> deleteBackup(String fileId) async {
    try {
      if (_driveApi == null) {
        final ok = await trySilentSignIn() || await signIn();
        if (!ok) return false;
      }
      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      debugPrint('❌ Delete error: $e');
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
