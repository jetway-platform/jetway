import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/auth_state.dart';

class AuthStorage {
  final File _credentialsFile;

  AuthStorage({File? credentialsFile})
      : _credentialsFile = credentialsFile ?? _defaultCredentialsFile();

  static File _defaultCredentialsFile() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;

    return File(path.join(home, '.jetway', 'credentials.json'));
  }

  File get file => _credentialsFile;

  Future<bool> isAuthenticated() async {
    final state = await read();
    return state != null && state.accessToken.isNotEmpty;
  }

  Future<String?> getAccessToken() async {
    final state = await read();
    return state?.accessToken;
  }

  Future<AuthState?> read() async {
    try {
      if (!await _credentialsFile.exists()) {
        return null;
      }

      final content = await _credentialsFile.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      return AuthState.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AuthState state) async {
    final parentDir = _credentialsFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final jsonString = const JsonEncoder.withIndent('  ').convert(state.toJson());
    await _credentialsFile.writeAsString(jsonString, flush: true);

    await _enforceFilePermissions(_credentialsFile.path);
  }

  Future<void> clear() async {
    if (await _credentialsFile.exists()) {
      await _credentialsFile.delete();
    }
  }

  Future<void> _enforceFilePermissions(String filePath) async {
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        await Process.run('chmod', ['600', filePath]);
      } catch (_) {
        // Best effort permission enforcement on POSIX
      }
    }
  }
}
