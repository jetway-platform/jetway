import 'dart:convert';
import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;

import '../models/config.dart';

class AppStoreConnectService {
  static const _baseUrl = 'https://api.appstoreconnect.apple.com/v1';

  final Logger _logger;
  final IosConfig _iosConfig;
  late final String _jwt;

  AppStoreConnectService(this._logger, this._iosConfig) {
    _jwt = _generateJwt();
  }

  String _generateJwt() {
    final privateKeyPem = File(_iosConfig.resolvedApiKeyPath).readAsStringSync();

    final jwt = JWT(
      {
        'iss': _iosConfig.resolvedApiIssuerId,
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'exp': (DateTime.now().add(const Duration(minutes: 19)).millisecondsSinceEpoch ~/ 1000),
        'aud': 'appstoreconnect-v1',
      },
      header: {'kid': _iosConfig.resolvedApiKeyId, 'typ': 'JWT'},
    );

    return jwt.sign(
      ECPrivateKey(privateKeyPem),
      algorithm: JWTAlgorithm.ES256,
    );
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_jwt',
    'Content-Type': 'application/json',
  };

  Future<void> uploadIpa({
    required String ipaPath,
    required String bundleId,
    bool verbose = false,
  }) async {
    _logger.info('  Uploading IPA to App Store Connect...');

    final result = await _runAltool([
      '--upload-app',
      '--type', 'ios',
      '--file', ipaPath,
      '--apiKey', _iosConfig.resolvedApiKeyId,
      '--apiIssuer', _iosConfig.resolvedApiIssuerId,
      if (verbose) '--verbose',
    ]);

    if (result.exitCode != 0) {
      throw AppStoreConnectException(
        'IPA upload failed:\n${result.stderr}\n${result.stdout}',
      );
    }

    _logger.success('  IPA uploaded to App Store Connect.');
  }

  Future<void> validateIpa({required String ipaPath}) async {
    _logger.info('  Validating IPA...');

    final result = await _runAltool([
      '--validate-app',
      '--type', 'ios',
      '--file', ipaPath,
      '--apiKey', _iosConfig.resolvedApiKeyId,
      '--apiIssuer', _iosConfig.resolvedApiIssuerId,
    ]);

    if (result.exitCode != 0) {
      throw AppStoreConnectException(
        'IPA validation failed:\n${result.stderr}\n${result.stdout}\n\n'
        'Check your provisioning profiles, signing certificates, and entitlements.',
      );
    }

    _logger.success('  IPA validation passed.');
  }

  Future<String?> getAppId(String bundleId) async {
    final uri = Uri.parse('$_baseUrl/apps?filter[bundleId]=$bundleId');
    final response = await http.get(uri, headers: _headers);

    _assertSuccess(response, 'fetching app info');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final apps = data['data'] as List<dynamic>;
    if (apps.isEmpty) return null;

    return apps.first['id'] as String;
  }

  Future<ProcessResult> _runAltool(List<String> args) async {
    final privateKeysDir = Directory(path.join(Directory.current.path, 'private_keys'));
    final dirExisted = privateKeysDir.existsSync();

    if (!dirExisted) {
      privateKeysDir.createSync(recursive: true);
    }

    final targetPath = path.join(privateKeysDir.path, 'AuthKey_${_iosConfig.resolvedApiKeyId}.p8');
    final targetFile = File(targetPath);
    var fileCopied = false;

    try {
      final sourceFile = File(_iosConfig.resolvedApiKeyPath);
      if (sourceFile.existsSync() && sourceFile.path != targetPath) {
        sourceFile.copySync(targetPath);
        fileCopied = true;
      }

      return await Process.run('xcrun', ['altool', ...args]);
    } finally {
      if (fileCopied && targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      if (!dirExisted && privateKeysDir.existsSync()) {
        if (privateKeysDir.listSync().isEmpty) {
          privateKeysDir.deleteSync();
        }
      }
    }
  }

  Future<void> addBuildToTestFlightGroup({
    required String appId,
    required String buildId,
    required String groupName,
  }) async {
    final groupId = await _findBetaGroup(appId: appId, groupName: groupName);
    if (groupId == null) {
      _logger.warn('  TestFlight group "$groupName" not found. Skipping assignment.');
      return;
    }

    final uri = Uri.parse('$_baseUrl/betaGroups/$groupId/relationships/builds');
    _logger.info('  Assigning build to group "$groupName"...');

    var attempt = 1;
    const maxAttempts = 10;

    while (attempt <= maxAttempts) {
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'data': [{'type': 'builds', 'id': buildId}],
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logger.success('  Build added to TestFlight group: $groupName');
        return;
      }

      if (response.statusCode == 422 && response.body.contains('ENTITY_UNPROCESSABLE')) {
        if (attempt == 1) {
          _logger.info('  Build is still processing in App Store Connect. Waiting to assign group...');
        }
        if (attempt == maxAttempts) {
          _logger.warn('  Processing took too long. You can assign the group manually in App Store Connect.');
          return;
        }

        await Future.delayed(const Duration(seconds: 30));
        attempt++;
        continue;
      }

      _assertSuccess(response, 'adding build to TestFlight group');
    }
  }

  Future<Map<String, dynamic>?> getLatestBuild(String appId) async {
    final uri = Uri.parse('$_baseUrl/builds?filter[app]=$appId&sort=-uploadedDate&limit=1');
    final response = await http.get(uri, headers: _headers);
    _assertSuccess(response, 'fetching latest build');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final builds = data['data'] as List<dynamic>;
    if (builds.isEmpty) return null;

    return builds.first as Map<String, dynamic>;
  }

  Future<String?> _findBetaGroup({required String appId, required String groupName}) async {
    final uri = Uri.parse('$_baseUrl/betaGroups?filter[app]=$appId');
    final response = await http.get(uri, headers: _headers);
    _assertSuccess(response, 'fetching TestFlight groups');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final groups = data['data'] as List<dynamic>;

    for (final group in groups) {
      final attrs = group['attributes'] as Map<String, dynamic>;
      if (attrs['name'] == groupName) {
        return group['id'] as String;
      }
    }
    return null;
  }

  void _assertSuccess(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppStoreConnectException(
        'App Store Connect API error while $action (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> verifyCredentials() async {
    final uri = Uri.parse('$_baseUrl/apps?limit=1');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AppStoreConnectException(
        'Invalid App Store Connect credentials (HTTP ${response.statusCode}).\n'
        'Check Key ID, Issuer ID, and .p8 key file.',
      );
    }
    _assertSuccess(response, 'verifying credentials');
  }

  Future<List<Map<String, dynamic>>> fetchApps() async {
    final uri = Uri.parse('$_baseUrl/apps?limit=200&fields[apps]=name,bundleId');
    final response = await http.get(uri, headers: _headers);
    _assertSuccess(response, 'fetching apps');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final apps = data['data'] as List<dynamic>;
    return apps.map((app) {
      final attrs = app['attributes'] as Map<String, dynamic>;
      return {
        'id': app['id'] as String,
        'bundleId': attrs['bundleId'] as String,
        'name': attrs['name'] as String,
      };
    }).toList();
  }

  Future<List<String>> fetchBetaGroupNames(String appId) async {
    final uri = Uri.parse('$_baseUrl/betaGroups?filter[app]=$appId&fields[betaGroups]=name&limit=100');
    final response = await http.get(uri, headers: _headers);
    _assertSuccess(response, 'fetching TestFlight groups');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final groups = data['data'] as List<dynamic>;
    return groups
        .map((g) => (g['attributes'] as Map<String, dynamic>)['name'] as String)
        .toList();
  }
}

class AppStoreConnectException implements Exception {
  final String message;
  AppStoreConnectException(this.message);

  @override
  String toString() => message;
}
