import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jetway/src/commands/login_command.dart';
import 'package:jetway/src/commands/logout_command.dart';
import 'package:jetway/src/commands/whoami_command.dart';
import 'package:jetway/src/models/auth_state.dart';
import 'package:jetway/src/services/auth_storage.dart';
import 'package:jetway/src/services/jetway_api_client.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late AuthStorage authStorage;
  late Logger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jetway_cmd_test_');
    testFile = File(path.join(tempDir.path, 'credentials.json'));
    authStorage = AuthStorage(credentialsFile: testFile);
    logger = Logger(level: Level.quiet);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WhoamiCommand', () {
    test('returns 0 and reports standalone local mode when unauthenticated', () async {
      final command = WhoamiCommand(
        logger,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(0));
    });

    test('returns 0 and displays profile when authenticated', () async {
      await authStorage.write(AuthState(
        accessToken: 'active_token',
        savedAt: DateTime.now(),
      ));

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'authenticated': true,
              'has_workspace': true,
              'user': {
                'id': 1,
                'email': 'pilot@jetway.run',
                'full_name': 'Test Pilot',
                'display_name': 'pilot_one',
              },
              'workspaces': [
                {
                  'id': 101,
                  'name': 'Test Workspace',
                  'slug': 'test-workspace',
                  'role': 'owner',
                  'plan_tier': 'community',
                }
              ],
            },
          }),
          200,
        );
      });

      final apiClient = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final command = WhoamiCommand(
        logger,
        apiClient: apiClient,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(0));
    });

    test('returns 1 when session has expired', () async {
      await authStorage.write(AuthState(
        accessToken: 'expired_token',
        savedAt: DateTime.now(),
      ));

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid credentials'}),
          401,
        );
      });

      final apiClient = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final command = WhoamiCommand(
        logger,
        apiClient: apiClient,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(1));
    });
  });

  group('LogoutCommand', () {
    test('returns 0 when not logged in', () async {
      final command = LogoutCommand(
        logger,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(0));
    });

    test('revokes credentials and returns 0 when logged in', () async {
      await authStorage.write(AuthState(
        accessToken: 'logged_in_token',
        refreshToken: 'refresh_to_revoke',
        savedAt: DateTime.now(),
      ));

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'success'}), 200);
      });

      final apiClient = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final command = LogoutCommand(
        logger,
        apiClient: apiClient,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(0));
      expect(await authStorage.isAuthenticated(), isFalse);
    });
  });

  group('LoginCommand', () {
    test('completes device flow and saves credentials upon authorization', () async {
      var pollAttempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/auth/device/code') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'device_code': 'dev_code_test',
                'user_code': 'ABCD-1234',
                'verification_uri': 'http://localhost:3000/activate',
                'verification_uri_complete': 'http://localhost:3000/activate?code=ABCD-1234',
                'expires_in': 10,
                'interval': 0, // 0 for instant test execution
              },
            }),
            200,
          );
        }

        if (request.url.path == '/v1/auth/device/token') {
          pollAttempts++;
          if (pollAttempts == 1) {
            return http.Response(
              jsonEncode({
                'status': 'error',
                'error': {'error': 'authorization_pending'},
              }),
              400,
            );
          }

          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'access_token': 'newly_authorized_token',
                'refresh_token': 'new_refresh_token',
                'token_type': 'bearer',
              },
            }),
            200,
          );
        }

        if (request.url.path == '/v1/auth/profile') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'authenticated': true,
                'has_workspace': true,
                'user': {
                  'id': 10,
                  'email': 'developer@jetway.run',
                  'full_name': 'Test Developer',
                },
              },
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final command = LoginCommand(
        logger,
        apiClient: apiClient,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(0));
      expect(await authStorage.isAuthenticated(), isTrue);

      final saved = await authStorage.read();
      expect(saved?.accessToken, equals('newly_authorized_token'));
      expect(saved?.refreshToken, equals('new_refresh_token'));
      expect(saved?.userEmail, equals('developer@jetway.run'));
    });

    test('stops and returns 1 when authorization is denied', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/auth/device/code') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'data': {
                'device_code': 'dev_code_denied',
                'user_code': 'DENY-1234',
                'verification_uri': 'http://localhost:3000/activate',
                'verification_uri_complete': 'http://localhost:3000/activate?code=DENY-1234',
                'expires_in': 5,
                'interval': 0,
              },
            }),
            200,
          );
        }

        if (request.url.path == '/v1/auth/device/token') {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'error': {'error': 'access_denied'},
            }),
            400,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = JetwayApiClient(
        baseUrl: 'https://api.jetway.dev',
        authStorage: authStorage,
        httpClient: mockClient,
      );

      final command = LoginCommand(
        logger,
        apiClient: apiClient,
        authStorage: authStorage,
      );

      final exitCode = await command.run();
      expect(exitCode, equals(1));
      expect(await authStorage.isAuthenticated(), isFalse);
    });
  });
}
