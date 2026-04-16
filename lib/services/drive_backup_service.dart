import 'dart:async';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class DriveBackupService {
  static final DriveBackupService instance = DriveBackupService._();
  
  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;

  static const _scopes = [drive.DriveApi.driveFileScope];

  DriveBackupService._() {
    _googleSignIn = GoogleSignIn.instance;
    _subscription = _googleSignIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _currentUser = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _currentUser = null;
      }
    });
  }

  static const _backupFileName = 'expense_manager_backup.db';

  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.authenticate();
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  bool get isSignedIn => _currentUser != null;

  Future<GoogleSignInAccount?> get currentUser async {
    if (_currentUser != null) return _currentUser;
    // attemptLightweightAuthentication might trigger a sign-in event
    return await _googleSignIn.attemptLightweightAuthentication();
  }

  Future<bool> backup() async {
    final account = await _ensureSignedIn();
    if (account == null) return false;

    final headers = await account.authorizationClient.authorizationHeaders(_scopes);
    if (headers == null) return false;
    
    final client = _AuthenticatedClient(headers);

    try {
      final driveApi = drive.DriveApi(client);

      // Get local DB path
      final dbPath = await getDatabasesPath();
      final localFile = File(join(dbPath, 'expenses.db'));
      if (!localFile.existsSync()) throw Exception('Local database not found');

      // Check if backup already exists
      final existing = await driveApi.files.list(
        q: "name='$_backupFileName' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      final media = drive.Media(
        localFile.openRead(),
        localFile.lengthSync(),
      );

      if (existing.files != null && existing.files!.isNotEmpty) {
        // Update existing file
        await driveApi.files.update(
          drive.File(),
          existing.files!.first.id!,
          uploadMedia: media,
        );
      } else {
        // Create new file
        await driveApi.files.create(
          drive.File()..name = _backupFileName,
          uploadMedia: media,
        );
      }
      return true;
    } catch (e) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> restore() async {
    final account = await _ensureSignedIn();
    if (account == null) return false;

    final headers = await account.authorizationClient.authorizationHeaders(_scopes);
    if (headers == null) return false;

    final client = _AuthenticatedClient(headers);

    try {
      final driveApi = drive.DriveApi(client);

      final existing = await driveApi.files.list(
        q: "name='$_backupFileName' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      if (existing.files == null || existing.files!.isEmpty) {
        throw Exception('No backup found on Google Drive');
      }

      final fileId = existing.files!.first.id!;
      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Close current DB connection before overwriting
      await DatabaseHelper.instance.close();

      final dbPath = await getDatabasesPath();
      final localFile = File(join(dbPath, 'expenses.db'));
      
      final sink = localFile.openWrite();
      await response.stream.pipe(sink);
      await sink.flush();
      await sink.close();
      
      return true;
    } catch (e) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<GoogleSignInAccount?> _ensureSignedIn() async {
    final current = _currentUser;
    if (current != null) return current;
    return await _googleSignIn.attemptLightweightAuthentication() ?? await _googleSignIn.authenticate();
  }

  void dispose() {
    _subscription?.cancel();
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthenticatedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
