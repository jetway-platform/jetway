import 'dart:io';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import '../models/config.dart';

/// Handles running Flutter build commands and locating output artifacts.
class FlutterBuildService {
  final Logger _logger;
  final bool verbose;

  FlutterBuildService(this._logger, {this.verbose = false});

  /// Runs `flutter build ipa` and returns the path to the built .ipa or .xcarchive.
  Future<String> buildIos({
    required FlightDeckConfig config,
    String? buildNumber,
  }) async {
    _logger.info('  Building Flutter iOS release...');

    final args = [
      'build',
      'ipa',
      '--release',
      if (buildNumber != null) '--build-number=$buildNumber',
      '--export-method=${_exportMethod(config.ios!.profile)}',
    ];

    await _runFlutter(args, 'iOS build');

    // Locate the IPA
    final ipaDir = path.join(Directory.current.path, 'build', 'ios', 'ipa');
    final ipaFiles = Directory(ipaDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ipa'))
        .toList();

    if (ipaFiles.isEmpty) {
      throw FlightDeckBuildException(
        'iOS build succeeded but no .ipa file found in $ipaDir',
      );
    }

    final ipaPath = ipaFiles.first.path;
    _logger.success('  ✓ IPA built: ${path.basename(ipaPath)}');
    return ipaPath;
  }

  /// Runs `flutter build appbundle` or `flutter build apk` and returns the artifact path.
  Future<String> buildAndroid({
    required FlightDeckConfig config,
    String? buildNumber,
  }) async {
    final isAab = config.android!.artifact == 'aab';
    _logger.info('  Building Flutter Android ${isAab ? 'App Bundle (AAB)' : 'APK'}...');

    final args = [
      'build',
      if (isAab) 'appbundle' else 'apk',
      '--release',
      if (buildNumber != null) '--build-number=$buildNumber',
    ];

    await _runFlutter(args, 'Android build');

    // Locate the artifact
    String artifactPath;
    if (isAab) {
      artifactPath = path.join(
        Directory.current.path,
        'build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab',
      );
    } else {
      artifactPath = path.join(
        Directory.current.path,
        'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk',
      );
    }

    if (!File(artifactPath).existsSync()) {
      throw FlightDeckBuildException(
        'Android build succeeded but artifact not found at: $artifactPath',
      );
    }

    _logger.success('  ✓ ${isAab ? 'AAB' : 'APK'} built: ${path.basename(artifactPath)}');
    return artifactPath;
  }

  /// Runs `flutter pub get` to ensure dependencies are up to date.
  Future<void> pubGet() async {
    _logger.info('  Running flutter pub get...');
    await _runFlutter(['pub', 'get'], 'pub get');
    _logger.success('  ✓ Dependencies resolved');
  }

  /// Verifies flutter is installed and the project is valid.
  Future<void> validate() async {
    final result = await Process.run('flutter', ['--version']);
    if (result.exitCode != 0) {
      throw FlightDeckBuildException(
        'Flutter not found. Install Flutter: https://flutter.dev/docs/get-started/install',
      );
    }

    if (!File(path.join(Directory.current.path, 'pubspec.yaml')).existsSync()) {
      throw FlightDeckBuildException(
        'Not a Flutter project directory (no pubspec.yaml found).',
      );
    }
  }

  Future<void> _runFlutter(List<String> args, String step) async {
    if (verbose) {
      _logger.detail('  flutter ${args.join(' ')}');
    }

    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: Directory.current.path,
    );

    if (verbose) {
      // Stream output in verbose mode
      process.stdout.listen((data) => _logger.detail(String.fromCharCodes(data)));
      process.stderr.listen((data) => _logger.detail(String.fromCharCodes(data)));
    } else {
      // Suppress in normal mode but capture stderr for error reporting
      final errors = StringBuffer();
      process.stderr.listen((data) => errors.write(String.fromCharCodes(data)));
      await process.exitCode; // Wait for completion in non-verbose mode
      final code = await process.exitCode;
      if (code != 0) {
        throw FlightDeckBuildException(
          'Flutter $step failed (exit $code):\n${errors.toString().trim()}\n\n'
          'Run with --verbose for full output.',
        );
      }
      return;
    }

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw FlightDeckBuildException(
        'Flutter $step failed (exit $exitCode). Run with --verbose for details.',
      );
    }
  }

  String _exportMethod(String profile) {
    switch (profile) {
      case 'distribution':
        return 'app-store';
      case 'adhoc':
        return 'ad-hoc';
      case 'development':
        return 'development';
      default:
        return 'app-store';
    }
  }
}

class FlightDeckBuildException implements Exception {
  final String message;
  FlightDeckBuildException(this.message);

  @override
  String toString() => message;
}
