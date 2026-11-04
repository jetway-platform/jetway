import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import '../models/config.dart';
import '../services/app_store_connect_service.dart';
import '../services/google_play_service.dart';
import '../utils/project_detector.dart';
import '../utils/prompt_utils.dart';

class SetupCommand extends Command<int> {
  @override
  final String name = 'setup';

  @override
  final String description =
      'Re-run guided credential setup for iOS and/or Android on an existing project.';

  final Logger _logger;
  late final CliPrompt _prompt;

  SetupCommand(this._logger) {
    _prompt = CliPrompt(_logger);
    argParser.addOption(
      'platform',
      abbr: 'p',
      allowed: ['ios', 'android', 'all'],
      defaultsTo: 'all',
      help: 'Target platform to configure.',
    );
  }

  @override
  Future<int> run() async {
    final platform = argResults!['platform'] as String;

    final pubspec = File(path.join(Directory.current.path, 'pubspec.yaml'));
    if (!pubspec.existsSync() || !pubspec.readAsStringSync().contains('flutter:')) {
      _logger.err('No Flutter pubspec.yaml found. Run from the root of your Flutter project.');
      return 1;
    }

    final jetwayConfig = File(path.join(Directory.current.path, 'jetway.yaml'));
    final fallbackFlightdeck = File(path.join(Directory.current.path, 'flightdeck.yaml'));
    final configFile = jetwayConfig.existsSync()
        ? jetwayConfig
        : (fallbackFlightdeck.existsSync() ? fallbackFlightdeck : jetwayConfig);

    Map<String, dynamic> existing = {};
    if (configFile.existsSync()) {
      try {
        final yaml = loadYaml(configFile.readAsStringSync()) as YamlMap;
        existing = _yamlMapToDart(yaml);
      } catch (e) {
        _logger.warn('Could not parse existing ${path.basename(configFile.path)}: $e');
      }
    } else {
      _logger.warn('No jetway.yaml found. Run `jetway init` first.');
      return 1;
    }

    _logger.info('\nJetway Setup — Refreshing Credentials\n');

    String? iosBlock;
    String? androidBlock;
    final detector = ProjectDetector();

    if (platform == 'ios' || platform == 'all') {
      _logger.info('--- iOS / App Store Connect ---');
      iosBlock = await _runIosSetup(detector);
      if (iosBlock == null) return 1;
    }

    if (platform == 'android' || platform == 'all') {
      _logger.info('--- Android / Google Play ---');
      final packageName = (existing['app'] as Map?)?.entries
          .firstWhere((e) => e.key == 'package_name', orElse: () => const MapEntry('', ''))
          .value as String? ?? '';
      androidBlock = await _runAndroidSetup(packageName);
      if (androidBlock == null) return 1;
    }

    final appSection = _rebuildAppSection(existing);
    final iosSection = iosBlock ?? _rebuildSection(existing, 'ios');
    final androidSection = androidBlock ?? _rebuildSection(existing, 'android');

    configFile.writeAsStringSync(
      '# jetway.yaml — Flutter deployment config\n\n'
      '$appSection$iosSection$androidSection',
    );

    _logger.info('');
    _logger.success('${path.basename(configFile.path)} updated successfully.\n');
    return 0;
  }

  Future<String?> _runIosSetup(ProjectDetector detector) async {
    final shouldOpen = _logger.confirm('Open App Store Connect in browser?', defaultValue: true);
    if (shouldOpen) {
      await _prompt.openUrl('https://appstoreconnect.apple.com/access/integrations/api');
      _prompt.prompt('  Press Enter when ready', '');
    }

    late IosConfig tempConfig;
    while (true) {
      _logger.info('');
      final keyId = _prompt.promptRequired('API Key ID (e.g. ABC123DEF4)');
      final issuerId = _prompt.promptRequired('Issuer ID (UUID)');
      final keyPath = _prompt.promptPath('Path to .p8 file', './keys/AuthKey.p8');

      _logger.info('\n  Verifying credentials...');
      try {
        final config = IosConfig(
          teamId: '',
          profile: 'distribution',
          apiKeyId: keyId,
          apiIssuerId: issuerId,
          apiKeyPath: keyPath,
        );
        tempConfig = config;
        final service = AppStoreConnectService(_logger, config);
        await service.verifyCredentials();
        _logger.success('  Connected to App Store Connect.\n');
        break;
      } on AppStoreConnectException catch (e) {
        _logger.err('  Verification failed: ${e.message}');
        if (!_logger.confirm('  Try again?', defaultValue: true)) return null;
      } catch (e) {
        _logger.err('  Unexpected error: $e');
        if (!_logger.confirm('  Try again?', defaultValue: true)) return null;
      }
    }

    final teamId = _prompt.promptRequired(
      'Apple Team ID',
      detector.detectIosTeamId(),
    );
    final profile = _prompt.selectFromList(
      'Distribution profile',
      ['distribution', 'adhoc', 'development'],
      display: (p) => p,
    );
    final scheme = _prompt.prompt('Xcode scheme', detector.detectIosScheme() ?? 'Runner');

    return '''
ios:
  team_id: "$teamId"
  profile: $profile
  scheme: "$scheme"
  api_key_id: "${tempConfig.resolvedApiKeyId}"
  api_issuer_id: "${tempConfig.resolvedApiIssuerId}"
  api_key_path: "${tempConfig.resolvedApiKeyPath}"
''';
  }

  Future<String?> _runAndroidSetup(String packageName) async {
    final shouldOpen = _logger.confirm('Open Google Play Console in browser?', defaultValue: true);
    if (shouldOpen) {
      await _prompt.openUrl('https://play.google.com/console/developers/api-access');
      _prompt.prompt('  Press Enter when ready', '');
    }

    final keystorePath = _prompt.promptPath('Path to keystore file', './keys/release.keystore');
    final keyAlias = _prompt.prompt('Key alias', 'release');

    _logger.info('');
    String serviceAccountPath = '';
    while (true) {
      serviceAccountPath = _prompt.promptPath(
        'Path to service account JSON',
        './keys/play-service-account.json',
      );
      if (File(serviceAccountPath).existsSync()) {
        try {
          final config = AndroidConfig(
            keystorePath: keystorePath,
            track: 'internal',
            artifact: 'aab',
            serviceAccountPath: serviceAccountPath,
          );
          final playService = GooglePlayService(_logger, config, packageName);
          await playService.verifyCredentials();
          _logger.success('  Connected to Google Play.\n');
          break;
        } on GooglePlayException catch (e) {
          _logger.err('  Verification failed: ${e.message}');
          if (!_logger.confirm('  Try a different file or path?', defaultValue: true)) break;
        } catch (e) {
          _logger.err('  Unexpected error: $e');
          if (!_logger.confirm('  Try again?', defaultValue: true)) break;
        }
      } else {
        _logger.err('  File not found: $serviceAccountPath');
        if (!_logger.confirm('  Try again?', defaultValue: true)) break;
      }
    }

    final track = _prompt.selectFromList(
      'Play Store track',
      ['internal', 'alpha', 'beta', 'production'],
      display: (t) => t,
    );
    final artifactRaw = _prompt.selectFromList(
      'Build artifact',
      ['aab (recommended)', 'apk'],
      display: (a) => a,
    );
    final artifact = artifactRaw.startsWith('aab') ? 'aab' : 'apk';

    return '''
android:
  keystore: "$keystorePath"
  key_alias: "$keyAlias"
  track: $track
  artifact: $artifact
  service_account: "$serviceAccountPath"
''';
  }

  String _rebuildAppSection(Map<String, dynamic> existing) {
    final app = existing['app'] as Map? ?? {};
    final name = app['name'] ?? 'MyApp';
    final bundleId = app['bundle_id'] ?? 'com.example.myapp';
    final packageName = app['package_name'] ?? bundleId;
    return 'app:\n  name: "$name"\n  bundle_id: "$bundleId"\n  package_name: "$packageName"\n';
  }

  String _rebuildSection(Map<String, dynamic> existing, String section) {
    if (!existing.containsKey(section)) return '';
    final data = existing[section] as Map? ?? {};
    final buf = StringBuffer('\n$section:\n');
    for (final entry in data.entries) {
      if (entry.value != null && entry.value.toString().isNotEmpty) {
        buf.writeln('  ${entry.key}: "${entry.value}"');
      }
    }
    return buf.toString();
  }

  Map<String, dynamic> _yamlMapToDart(YamlMap yaml) {
    final result = <String, dynamic>{};
    for (final key in yaml.keys) {
      final value = yaml[key];
      if (value is YamlMap) {
        result[key as String] = _yamlMapToDart(value);
      } else {
        result[key as String] = value;
      }
    }
    return result;
  }
}
