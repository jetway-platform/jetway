import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import '../models/config.dart';

/// Interacts with the App Store Connect API to upload builds and manage TestFlight.
/// API docs: https://developer.apple.com/documentation/appstoreconnectapi
class AppStoreConnectService {
  static const _baseUrl = 'https://api.appstoreconnect.apple.com/v1';

  final Logger _logger;
  final IosConfig _iosConfig;
  late final String _jwt;

  AppStoreConnectService(this._logger, this._iosConfig) {
    _jwt = _generateJwt();
  }

  /// Generates a JWT for App Store Connect API authentication.
  /// Apple requires ES256-signed JWTs that expire within 20 minutes.
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

  /// Uploads an IPA to App Store Connect via the altool-compatible upload approach.
  /// Uses Apple's Transporter tool under the hood (installed with Xcode CLI tools).
  Future<void> uploadIpa({
    required String ipaPath,
    required String bundleId,
    bool verbose = false,
  }) async {
    _logger.info('  Uploading IPA to App Store Connect...');

    // Apple's recommended approach: use xcrun altool or Transporter
    // xcrun altool --upload-app is deprecated; use xcrun altool --validate-app then upload
    // Or use Apple Transporter CLI. We use altool with API key auth.
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

    _logger.success('  ✓ IPA uploaded to App Store Connect');
  }

  /// Validates an IPA before uploading (catches signing/provisioning issues early).
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
        'Common causes:\n'
        '  - Invalid provisioning profile\n'
        '  - Certificate mismatch\n'
        '  - Missing entitlements\n'
        'Run: flightdeck certs sync  to refresh your certificates.',
      );
    }

    _logger.success('  ✓ IPA validation passed');
  }

  /// Looks up the App ID for a given bundle identifier.
  Future<String?> getAppId(String bundleId) async {
    final uri = Uri.parse('$_baseUrl/apps?filter[bundleId]=$bundleId');
    final response = await http.get(uri, headers: _headers);

    _assertSuccess(response, 'fetching app info');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final apps = data['data'] as List<dynamic>;
    if (apps.isEmpty) return null;

    return apps.first['id'] as String;
  }

  /// Helper to run Apple's stubborn altool which requires a specific directory and filename.
  Future<ProcessResult> _runAltool(List<String> args) async {
    // altool natively expects the key to be named AuthKey_<ApiKeyId>.p8
    // It automatically looks in the ./private_keys directory relative to where it's run.
    final privateKeysDir = Directory(path.join(Directory.current.path, 'private_keys'));
    final dirExisted = privateKeysDir.existsSync();
    
    if (!dirExisted) {
      privateKeysDir.createSync(recursive: true);
    }

    final targetPath = path.join(privateKeysDir.path, 'AuthKey_${_iosConfig.resolvedApiKeyId}.p8');
    final targetFile = File(targetPath);
    bool fileCopied = false;

    try {
      final sourceFile = File(_iosConfig.resolvedApiKeyPath);
      if (sourceFile.existsSync() && sourceFile.path != targetPath) {
        sourceFile.copySync(targetPath);
        fileCopied = true;
      }

      return await Process.run(
        'xcrun',
        ['altool', ...args],
      );
    } finally {
      // Clean up the copied key
      if (fileCopied && targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      // Clean up the directory if we created it and it's now empty
      if (!dirExisted && privateKeysDir.existsSync()) {
        if (privateKeysDir.listSync().isEmpty) {
          privateKeysDir.deleteSync();
        }
      }
    }
  }

  /// Adds the latest build to a TestFlight group.
  Future<void> addBuildToTestFlightGroup({
    required String appId,
    required String buildId,
    required String groupName,
  }) async {
    // 1. Find the beta group
    final groupId = await _findBetaGroup(appId: appId, groupName: groupName);
    if (groupId == null) {
      _logger.warn('  TestFlight group "$groupName" not found. Skipping group assignment.');
      return;
    }

    // 2. Add build to group (with polling for processing state)
    final uri = Uri.parse('$_baseUrl/betaGroups/$groupId/relationships/builds');
    
    _logger.info('  Assigning build to group "$groupName"...');

    var attempt = 1;
    while (true) {
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'data': [{'type': 'builds', 'id': buildId}],
        }),
      );

      // If success, we're done
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logger.success('  ✓ Build added to TestFlight group: $groupName');
        break;
      }

      // If it's a 422 Processing error, Apple is still chewing on the IPA
      if (response.statusCode == 422 && response.body.contains('ENTITY_UNPROCESSABLE')) {
        if (attempt == 1) {
          _logger.info('  ⏳ Apple is still processing the build. Waiting to assign...');
          _logger.info('  (You can safely press Ctrl+C to cancel and assign it manually later in ASC)');
        }
        
        await Future.delayed(const Duration(seconds: 30));
        attempt++;
        continue;
      }

      // Any other error
      _assertSuccess(response, 'adding build to TestFlight group');
    }
  }

  /// Gets the latest build for an app.
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
        'App Store Connect API error while $action '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Verifies credentials are valid by making a lightweight API call.
  /// Throws [AppStoreConnectException] if auth fails.
  Future<void> verifyCredentials() async {
    final uri = Uri.parse('$_baseUrl/apps?limit=1');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AppStoreConnectException(
        'Invalid App Store Connect credentials (HTTP ${response.statusCode}).\n'
        'Check your Key ID, Issuer ID, and that the .p8 file matches the Key ID.',
      );
    }
    _assertSuccess(response, 'verifying credentials');
  }

  /// Returns all apps accessible to this API key.
  /// Each map has: id, bundleId, name.
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

  /// Returns beta group names for the given app ID.
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
