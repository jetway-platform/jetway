import 'dart:io';

import 'package:jetway/src/models/auth_state.dart';
import 'package:jetway/src/services/auth_storage.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('AuthState', () {
    test('serializes to and from JSON correctly', () {
      final now = DateTime.utc(2026, 11, 4, 12, 0, 0);
      final state = AuthState(
        accessToken: 'jwt_access_token_123',
        refreshToken: 'jwt_refresh_token_456',
        tokenType: 'bearer',
        userEmail: 'pilot@jetway.run',
        userName: 'Ada Lovelace',
        savedAt: now,
      );

      final json = state.toJson();
      expect(json['access_token'], equals('jwt_access_token_123'));
      expect(json['refresh_token'], equals('jwt_refresh_token_456'));
      expect(json['token_type'], equals('bearer'));
      expect(json['user_email'], equals('pilot@jetway.run'));
      expect(json['user_name'], equals('Ada Lovelace'));
      expect(json['saved_at'], equals(now.toIso8601String()));

      final restored = AuthState.fromJson(json);
      expect(restored.accessToken, equals(state.accessToken));
      expect(restored.refreshToken, equals(state.refreshToken));
      expect(restored.tokenType, equals(state.tokenType));
      expect(restored.userEmail, equals(state.userEmail));
      expect(restored.userName, equals(state.userName));
      expect(restored.savedAt, equals(state.savedAt));
    });

    test('copyWith updates properties properly', () {
      final state = AuthState(
        accessToken: 'initial_token',
        savedAt: DateTime.now(),
      );

      final updated = state.copyWith(
        userEmail: 'updated@jetway.run',
        userName: 'Captain Jet',
      );

      expect(updated.accessToken, equals('initial_token'));
      expect(updated.userEmail, equals('updated@jetway.run'));
      expect(updated.userName, equals('Captain Jet'));
    });
  });

  group('AuthStorage', () {
    late Directory tempDir;
    late File testFile;
    late AuthStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('jetway_auth_test_');
      testFile = File(path.join(tempDir.path, '.jetway', 'credentials.json'));
      storage = AuthStorage(credentialsFile: testFile);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('read returns null when file does not exist', () async {
      expect(await storage.read(), isNull);
      expect(await storage.isAuthenticated(), isFalse);
      expect(await storage.getAccessToken(), isNull);
    });

    test('writes and reads credentials correctly with parent directory creation', () async {
      final state = AuthState(
        accessToken: 'token_abc_xyz',
        refreshToken: 'refresh_123',
        userEmail: 'test@jetway.run',
        savedAt: DateTime.now(),
      );

      await storage.write(state);

      expect(await testFile.exists(), isTrue);
      expect(await storage.isAuthenticated(), isTrue);
      expect(await storage.getAccessToken(), equals('token_abc_xyz'));

      final readState = await storage.read();
      expect(readState, isNotNull);
      expect(readState!.accessToken, equals('token_abc_xyz'));
      expect(readState.refreshToken, equals('refresh_123'));
      expect(readState.userEmail, equals('test@jetway.run'));
    });

    test('clear removes credentials file', () async {
      final state = AuthState(
        accessToken: 'to_be_deleted',
        savedAt: DateTime.now(),
      );

      await storage.write(state);
      expect(await testFile.exists(), isTrue);

      await storage.clear();
      expect(await testFile.exists(), isFalse);
      expect(await storage.read(), isNull);
    });
  });
}

