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

class InitCommand extends Command<int> {
  @override
  final String name = 'init';

  @override
  final String description =
      'Guided setup wizard to generate jetway.yaml for your project.';

  final Logger _logger;
  late final CliPrompt _prompt;

  InitCommand(this._logger) {
    _prompt = CliPrompt(_logger);
  }

  @override
  Future<int> run() async {
    _logger.info('');
    _logger.info('Jetway Setup Wizard\n');

    if (!_isFlutterProject()) {
      _logger.err(
        'No pubspec.yaml with Flutter found. Run this command from your Flutter project root.',
      );
      return 1;
    }

    final configFile = File(path.join(Directory.current.path, 'jetway.yaml'));
    if (configFile.existsSync()) {
      final overwrite = _logger.confirm(
        'jetway.yaml already exists. Overwrite?',
        defaultValue: false,
      );
      if (!overwrite) {
        _logger.info('Aborted. Run `jetway setup` to update platform credentials.');
        return 0;
      }
    }

    _printSection('App Info');
    final detector = ProjectDetector();
    final appName = _prompt.prompt('App name', _detectAppName());

    final detectedIosBundleId = detector.detectIosBundleId();
    final bundleId = _prompt.prompt(
      'iOS Bundle ID',
      detectedIosBundleId ?? 'com.example.${appName.toLowerCase().replaceAll(' ', '')}',
    );

    final detectedPackageName = detector.detectAndroidPackageName();
    final packageName = _prompt.prompt('Android Package name', detectedPackageName ?? bundleId);

    String iosBlock = '';
    final setupIos = _logger.confirm('\nConfigure iOS / App Store Connect?', defaultValue: true);
    if (setupIos) {
      final result = await _runIosSetup(detector);
      if (result == null) return 1;
      iosBlock = result;
    }

    String androidBlock = '';
    final setupAndroid = _logger.confirm('\nConfigure Android / Google Play?', defaultValue: true);
    if (setupAndroid) {
      final result = await _runAndroidSetup(packageName);
      if (result == null) return 1;
      androidBlock = result;
    }

    final configContent = '''# jetway.yaml — Flutter deployment config
# Docs: https://github.com/AbdLim/jetway-cli

app:
  name: "$appName"
  bundle_id: "$bundleId"
  package_name: "$packageName"
$iosBlock$androidBlock
''';

    configFile.writeAsStringSync(configContent);

    _logger.info('');
    _logger.success('jetway.yaml created successfully.');
    _logger.info('Ensure keys/ and .env are added to your .gitignore to protect secrets.');
    _logger.info('Run `jetway deploy` when you are ready to release.\n');

    return 0;
  }

  Future<String?> _runIosSetup(ProjectDetector detector) async {
    _printSection('iOS / App Store Connect');

    _logger.info('App Store Connect API key required:\n');
    _logger.info('  1. Go to: App Store Connect -> Users & Access -> Integrations -> API');
    _logger.info('  2. Click "+" -> Name it "Jetway" -> Role: App Manager');
    _logger.info('  3. Download the .p8 file');
    _logger.info('  4. Copy your Key ID and Issuer ID\n');

    final shouldOpen = _logger.confirm('Open App Store Connect in browser now?', defaultValue: true);
    if (shouldOpen) {
      await _prompt.openUrl('https://appstoreconnect.apple.com/access/integrations/api');
      _logger.info('\n  Waiting for key generation...\n');
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
        final retry = _logger.confirm('  Try again?', defaultValue: true);
        if (!retry) return null;
      } catch (e) {
        _logger.err('  Unexpected error: $e');
        final retry = _logger.confirm('  Try again?', defaultValue: true);
        if (!retry) return null;
      }
    }

    _logger.info('  Fetching apps from App Store Connect...');
    final service = AppStoreConnectService(_logger, tempConfig);
    late Map<String, dynamic> selectedApp;
    try {
      final apps = await service.fetchApps();
      if (apps.isEmpty) {
        _logger.warn('  No apps found. Ensure the API key has the App Manager role.');
        selectedApp = {'id': '', 'name': '', 'bundleId': ''};
      } else {
        _logger.info('');
        selectedApp = _prompt.selectFromList(
          'Select iOS app',
          apps,
          display: (a) => '${a['name']} (${a['bundleId']})',
        );
        _logger.success('  Selected: ${selectedApp['name']}\n');
      }
    } catch (e) {
      _logger.warn('  Could not fetch apps: $e');
      selectedApp = {'id': '', 'name': '', 'bundleId': ''};
    }

    String testflightGroup = '';
    if ((selectedApp['id'] as String).isNotEmpty) {
      _logger.info('  Fetching TestFlight groups...');
      try {
        final groups = await service.fetchBetaGroupNames(selectedApp['id'] as String);
        if (groups.isNotEmpty) {
          testflightGroup = _prompt.selectFromList(
            'Select TestFlight group',
            groups,
            display: (g) => g,
          );
          _logger.success('  Selected group: $testflightGroup\n');
        }
      } catch (e) {
        _logger.warn('  Could not fetch TestFlight groups: $e');
      }
    }

    _logger.info('');
    final teamId = _prompt.promptRequired(
      'Apple Team ID (10 alphanumeric characters)',
      detector.detectIosTeamId(),
    );
    final profile = _prompt.selectFromList(
      'Distribution profile type',
      ['distribution', 'adhoc', 'development'],
      display: (p) => p,
    );
    final scheme = _prompt.prompt('Xcode scheme', detector.detectIosScheme() ?? 'Runner');

    return '''
ios:
  team_id: "$teamId"
  profile: $profile
  scheme: "$scheme"${testflightGroup.isNotEmpty ? '\n  testflight_group: "$testflightGroup"' : ''}
  api_key_id: "${tempConfig.resolvedApiKeyId}"
  api_issuer_id: "${tempConfig.resolvedApiIssuerId}"
  api_key_path: "${tempConfig.resolvedApiKeyPath}"
''';
  }

  Future<String?> _runAndroidSetup(String packageName) async {
    _printSection('Android / Google Play');

    _logger.info('Google Play service account JSON key required:\n');
    _logger.info('  1. Go to: Play Console -> Setup -> API access');
    _logger.info('  2. Link or create a Google Cloud project');
    _logger.info('  3. Create a Service Account with Release Manager permissions');
    _logger.info('  4. Generate and download a JSON key\n');

    final shouldOpen = _logger.confirm('Open Google Play Console in browser now?', defaultValue: true);
    if (shouldOpen) {
      await _prompt.openUrl('https://play.google.com/console/developers/api-access');
      _logger.info('\n  Waiting for service account setup...\n');
      _prompt.prompt('  Press Enter when ready', '');
    }

    _logger.info('\n  Android Signing Keystore:');
    String keystorePath = _prompt.promptPath('Path to keystore file', './keys/release.keystore');

    if (!File(keystorePath).existsSync()) {
      final generate = _logger.confirm(
        '  Keystore not found. Generate a new one?',
        defaultValue: true,
      );
      if (generate) {
        keystorePath = await _generateKeystore(keystorePath);
        if (keystorePath.isEmpty) {
          _logger.err('  Keystore generation failed.');
        }
      }
    } else {
      _logger.success('  Keystore found.\n');
    }

    final keyAlias = _prompt.prompt('Key alias', 'release');

    _logger.info('\n  Google Play Service Account:');
    String serviceAccountPath = '';

    while (true) {
      serviceAccountPath = _prompt.promptPath(
        'Path to service account JSON',
        './keys/play-service-account.json',
      );

      if (!File(serviceAccountPath).existsSync()) {
        _logger.err('  File not found: $serviceAccountPath');
        final retry = _logger.confirm('  Try a different path?', defaultValue: true);
        if (!retry) break;
        continue;
      }

      _logger.info('\n  Verifying Google Play credentials...');
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
        final retry = _logger.confirm('  Try a different path?', defaultValue: true);
        if (!retry) break;
      } catch (e) {
        _logger.err('  Unexpected error: $e');
        final retry = _logger.confirm('  Try again?', defaultValue: true);
        if (!retry) break;
      }
    }

    final track = _prompt.selectFromList(
      'Google Play release track',
      ['internal', 'alpha', 'beta', 'production'],
      display: (t) => t,
    );

    final artifact = _prompt.selectFromList(
      'Build artifact type',
      ['aab (recommended)', 'apk'],
      display: (a) => a,
    );
    final artifactValue = artifact.startsWith('aab') ? 'aab' : 'apk';

    _logger.info('');
    _logger.info('  Set keystore passwords as environment variables or in .env:');
    _logger.info('    ANDROID_KEYSTORE_PASSWORD=<password>');
    _logger.info('    ANDROID_KEY_PASSWORD=<password>\n');

    return '''
android:
  keystore: "$keystorePath"
  key_alias: "$keyAlias"
  track: $track
  artifact: $artifactValue
  service_account: "$serviceAccountPath"
  # keystore_password: ""
  # key_password: ""
''';
  }

  Future<String> _generateKeystore(String targetPath) async {
    _logger.info('\n  Generating keystore at $targetPath...\n');

    final dir = path.dirname(targetPath);
    if (!Directory(dir).existsSync()) {
      Directory(dir).createSync(recursive: true);
    }

    final result = await Process.run('keytool', [
      '-genkey', '-v',
      '-keystore', targetPath,
      '-alias', 'release',
      '-keyalg', 'RSA',
      '-keysize', '2048',
      '-validity', '10000',
    ], runInShell: true);

    if (result.exitCode != 0) {
      _logger.err('  keytool failed: ${result.stderr}');
      return '';
    }

    _logger.success('  Keystore generated at $targetPath\n');
    return targetPath;
  }

  void _printSection(String title) {
    _logger.info('\n--- $title ---');
  }

  bool _isFlutterProject() {
    final pubspec = File(path.join(Directory.current.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    return pubspec.readAsStringSync().contains('flutter:');
  }

  String _detectAppName() {
    try {
      final pubspec = File(path.join(Directory.current.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
        return yaml['name'] as String? ?? 'MyApp';
      }
    } catch (_) {}
    return 'MyApp';
  }
}
