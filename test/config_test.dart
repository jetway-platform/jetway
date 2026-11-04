import 'dart:io';
import 'package:jetway/src/models/config.dart';
import 'package:test/test.dart';

void main() {
  group('JetwayConfig', () {
    test('throws JetwayConfigException when file does not exist', () {
      expect(
        () => JetwayConfig.fromFile('non_existent_jetway.yaml'),
        throwsA(isA<JetwayConfigException>()),
      );
    });

    test('parses minimal valid config', () {
      final tempDir = Directory.systemTemp.createTempSync('jetway_test_');
      final configFile = File('${tempDir.path}/jetway.yaml');

      configFile.writeAsStringSync('''
app:
  name: "Sample App"
  bundle_id: "com.example.sample"
  package_name: "com.example.sample"

ios:
  team_id: "ABCD1234EF"
  api_key_id: "KEY123"
  api_issuer_id: "ISSUER123"
  api_key_path: "./keys/AuthKey.p8"

android:
  keystore: "./keys/release.keystore"
  service_account: "./keys/service.json"
''');

      final config = JetwayConfig.fromFile(configFile.path);

      expect(config.app.name, equals('Sample App'));
      expect(config.app.bundleId, equals('com.example.sample'));
      expect(config.app.packageName, equals('com.example.sample'));
      expect(config.ios?.teamId, equals('ABCD1234EF'));
      expect(config.ios?.profile, equals('distribution'));
      expect(config.android?.track, equals('internal'));
      expect(config.android?.artifact, equals('aab'));

      tempDir.deleteSync(recursive: true);
    });

    test('validates platform requirements', () {
      final tempDir = Directory.systemTemp.createTempSync('jetway_test_');
      final configFile = File('${tempDir.path}/jetway.yaml');

      configFile.writeAsStringSync('''
app:
  name: "Sample App"
  bundle_id: "com.example.sample"
  package_name: "com.example.sample"
''');

      final config = JetwayConfig.fromFile(configFile.path);

      expect(
        () => config.validateForPlatform(DeployPlatform.ios),
        throwsA(isA<JetwayConfigException>()),
      );

      expect(
        () => config.validateForPlatform(DeployPlatform.android),
        throwsA(isA<JetwayConfigException>()),
      );

      tempDir.deleteSync(recursive: true);
    });
  });

  group('DeployPlatformParsing', () {
    test('parses valid strings', () {
      expect(DeployPlatformParsing.fromString('ios'), equals(DeployPlatform.ios));
      expect(DeployPlatformParsing.fromString('android'), equals(DeployPlatform.android));
      expect(DeployPlatformParsing.fromString('all'), equals(DeployPlatform.all));
    });

    test('throws on unknown platform', () {
      expect(
        () => DeployPlatformParsing.fromString('web'),
        throwsA(isA<JetwayConfigException>()),
      );
    });
  });
}
