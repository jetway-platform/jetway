import 'dart:io';
import 'package:flightdeck/src/utils/project_detector.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectDetector', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('detector_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('detects iOS bundle ID and team ID from project.pbxproj', () {
      final pbxDir = Directory('${tempDir.path}/ios/Runner.xcodeproj');
      pbxDir.createSync(recursive: true);

      final pbxFile = File('${pbxDir.path}/project.pbxproj');
      pbxFile.writeAsStringSync('''
PRODUCT_BUNDLE_IDENTIFIER = com.example.runnerTests;
PRODUCT_BUNDLE_IDENTIFIER = com.example.flutterApp;
DEVELOPMENT_TEAM = ABCD1234EF;
''');

      final detector = ProjectDetector(tempDir.path);
      expect(detector.detectIosBundleId(), equals('com.example.flutterApp'));
      expect(detector.detectIosTeamId(), equals('ABCD1234EF'));
    });

    test('detects Android package name from build.gradle', () {
      final appDir = Directory('${tempDir.path}/android/app');
      appDir.createSync(recursive: true);

      final gradleFile = File('${appDir.path}/build.gradle');
      gradleFile.writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.example.androidapp"
    }
}
''');

      final detector = ProjectDetector(tempDir.path);
      expect(detector.detectAndroidPackageName(), equals('com.example.androidapp'));
    });

    test('returns null when project files are missing', () {
      final detector = ProjectDetector(tempDir.path);
      expect(detector.detectIosBundleId(), isNull);
      expect(detector.detectIosTeamId(), isNull);
      expect(detector.detectIosScheme(), isNull);
      expect(detector.detectAndroidPackageName(), isNull);
    });
  });
}
