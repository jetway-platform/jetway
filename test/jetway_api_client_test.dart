import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jetway/src/models/auth_state.dart';
import 'package:jetway/src/services/auth_storage.dart';
import 'package:jetway/src/services/jetway_api_client.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late AuthStorage authStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jetway_api_test_');
    testFile = File(path.join(tempDir.path, 'credentials.json'));
    authStorage = AuthStorage(credentialsFile: testFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JetwayApiClient', () {
    test('requestDeviceCode succeeds and parses DeviceCodeResponse', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/v1/auth/device/code'));
        expect(request.method, equals('POST'));

        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'device_code': 'dev_code_12345',
              'user_code': 'WDXZ-9482',
              'verification_uri': 'http://localhost:3000/activate',
              'verification_uri_complete': 'http://localhost:3000/activate?code=WDXZ-9482',
              'expires_in': 900,
              'interval': 3,
            },
          }),
          200,
        );
      });

      final client = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final result = await client.requestDeviceCode();
      expect(result.deviceCode, equals('dev_code_12345'));
      expect(result.userCode, equals('WDXZ-9482'));
      expect(result.verificationUriComplete, contains('WDXZ-9482'));
      expect(result.interval, equals(3));
    });

    test('pollDeviceToken returns authorized with tokens on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/v1/auth/device/token'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_code'], equals('dev_code_12345'));

        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'status': 'authorized',
              'access_token': 'access_token_abc',
              'refresh_token': 'refresh_token_xyz',
              'token_type': 'bearer',
            },
          }),
          200,
        );
      });

      final client = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final result = await client.pollDeviceToken('dev_code_12345');
      expect(result.status, equals(DeviceTokenStatus.authorized));
      expect(result.accessToken, equals('access_token_abc'));
      expect(result.refreshToken, equals('refresh_token_xyz'));
    });

    test('pollDeviceToken handles pending, slowDown, denied, and expired on 400', () async {
      final responses = <String, DeviceTokenStatus>{
        'authorization_pending': DeviceTokenStatus.pending,
        'slow_down': DeviceTokenStatus.slowDown,
        'access_denied': DeviceTokenStatus.denied,
        'expired_token': DeviceTokenStatus.expired,
      };

      for (final entry in responses.entries) {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'error': {
                'error': entry.key,
                'message': 'Error status: ${entry.key}',
              },
            }),
            400,
          );
        });

        final client = JetwayApiClient(
          baseUrl: 'https://api.jetway.dev',
          authStorage: authStorage,
          httpClient: mockClient,
        );

        final result = await client.pollDeviceToken('dev_code_test');
        expect(result.status, equals(entry.value), reason: 'Failed for ${entry.key}');
      }
    });

    test('getProfile retrieves user profile with Bearer authorization', () async {
      await authStorage.write(AuthState(
        accessToken: 'saved_access_token',
        savedAt: DateTime.now(),
      ));

      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/v1/auth/profile'));
        expect(request.headers['Authorization'], equals('Bearer saved_access_token'));

        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'authenticated': true,
              'has_workspace': true,
              'user': {
                'id': 7,
                'email': 'developer@jetway.run',
                'full_name': 'Grace Hopper',
                'display_name': 'admiral_grace',
              },
            },
          }),
          200,
        );
      });

      final client = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final profile = await client.getProfile();
      expect(profile.id, equals(7));
      expect(profile.email, equals('developer@jetway.run'));
      expect(profile.displayName, equals('admiral_grace'));
      expect(profile.hasWorkspace, isTrue);
    });

    test('getProfile throws JetwayAuthException on 401', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Could not validate credentials'}),
          401,
        );
      });

      final client = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      expect(
        () => client.getProfile(token: 'expired_token'),
        throwsA(isA<JetwayAuthException>()),
      );
    });

    test('logout revokes refresh token on API and clears authStorage', () async {
      await authStorage.write(AuthState(
        accessToken: 'valid_access_token',
        refreshToken: 'valid_refresh_token',
        savedAt: DateTime.now(),
      ));

      var logoutCalled = false;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/auth/logout') {
          logoutCalled = true;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refresh_token'], equals('valid_refresh_token'));
          return http.Response(jsonEncode({'status': 'success'}), 200);
        }
        return http.Response('Not found', 404);
      });

      final client = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      await client.logout();
      expect(logoutCalled, isTrue);
      expect(await authStorage.isAuthenticated(), isFalse);
    });
  });
}
