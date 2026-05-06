import 'dart:io';
import 'package:path/path.dart' as path;

/// Reads iOS and Android project configuration from local project files.
/// All methods return null if the value cannot be detected.
class ProjectDetector {
  final String projectRoot;

  ProjectDetector([String? root]) : projectRoot = root ?? Directory.current.path;

  // ── iOS ──────────────────────────────────────────────────────────────────

  /// Reads PRODUCT_BUNDLE_IDENTIFIER from the Xcode project file.
  /// Returns the first unique value found (skips test targets).
  String? detectIosBundleId() {
    final pbxproj = _findPbxproj();
    if (pbxproj == null) return null;

    final content = pbxproj.readAsStringSync();

    // Match lines like: PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
    final matches = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);')
        .allMatches(content)
        .map((m) => m.group(1)!.trim())
        // Skip test bundle IDs (they typically end in .RunnerTests or .Tests)
        .where((id) => !id.toLowerCase().contains('test'))
        .toSet()
        .toList();

    return matches.isNotEmpty ? matches.first : null;
  }

  /// Reads DEVELOPMENT_TEAM from the Xcode project file.
  String? detectIosTeamId() {
    final pbxproj = _findPbxproj();
    if (pbxproj == null) return null;

    final content = pbxproj.readAsStringSync();

    // Match lines like: DEVELOPMENT_TEAM = ABCD1234EF;
    final match = RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10});')
        .firstMatch(content);

    return match?.group(1)?.trim();
  }

  /// Reads the Xcode scheme name (defaults to Runner, but may differ).
  String? detectIosScheme() {
    final schemesDir = Directory(
      path.join(projectRoot, 'ios', 'Runner.xcodeproj', 'xcshareddata', 'xcschemes'),
    );
    if (!schemesDir.existsSync()) return null;

    final schemes = schemesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.xcscheme'))
        .map((f) => path.basenameWithoutExtension(f.path))
        .where((n) => !n.toLowerCase().contains('test'))
        .toList();

    return schemes.isNotEmpty ? schemes.first : null;
  }

  // ── Android ──────────────────────────────────────────────────────────────

  /// Reads applicationId from android/app/build.gradle (Groovy or Kotlin DSL).
  /// Falls back to package= in AndroidManifest.xml.
  String? detectAndroidPackageName() {
    return _detectFromBuildGradle() ?? _detectFromManifest();
  }

  String? _detectFromBuildGradle() {
    // Try Kotlin DSL first (build.gradle.kts), then Groovy (build.gradle)
    final candidates = [
      path.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
      path.join(projectRoot, 'android', 'app', 'build.gradle'),
    ];

    for (final filePath in candidates) {
      final file = File(filePath);
      if (!file.existsSync()) continue;

      final content = file.readAsStringSync();

      // Groovy DSL: applicationId "com.example.app"
      // Kotlin DSL: applicationId = "com.example.app"
      final match = RegExp(r'''applicationId\s*[=]?\s*["']([^"']+)["']''')
          .firstMatch(content);

      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  String? _detectFromManifest() {
    final manifest = File(
      path.join(projectRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!manifest.existsSync()) return null;

    final content = manifest.readAsStringSync();
    // <manifest xmlns:android="..." package="com.example.app">
    final match = RegExp(r'package\s*=\s*"([^"]+)"').firstMatch(content);
    return match?.group(1)?.trim();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  File? _findPbxproj() {
    // Standard Flutter iOS path: ios/Runner.xcodeproj/project.pbxproj
    final standard = File(
      path.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (standard.existsSync()) return standard;

    // Fallback: search ios/ for any .xcodeproj/project.pbxproj
    final iosDir = Directory(path.join(projectRoot, 'ios'));
    if (!iosDir.existsSync()) return null;

    for (final entry in iosDir.listSync()) {
      if (entry is Directory && entry.path.endsWith('.xcodeproj')) {
        final pbx = File(path.join(entry.path, 'project.pbxproj'));
        if (pbx.existsSync()) return pbx;
      }
    }
    return null;
  }
}
