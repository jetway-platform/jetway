import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import '../models/config.dart';
import '../services/app_store_connect_service.dart';
import '../utils/project_detector.dart';

/// Re-runs the guided credential setup for one or both platforms
/// on an existing flightdeck.yaml without overwriting unrelated sections.
///
/// Usage:
///   flightdeck setup                   # re-setup both platforms
///   flightdeck setup --platform ios    # iOS only
///   flightdeck setup --platform android
class SetupCommand extends Command<int> {
  @override
  final String name = 'setup';

  @override
  final String description =
      'Re-run the guided credential setup for iOS and/or Android on an existing project.';

  final Logger _logger;

  SetupCommand(this._logger) {
    argParser.addOption(
      'platform',
      abbr: 'p',
      allowed: ['ios', 'android', 'all'],
      defaultsTo: 'all',
      help: 'Which platform to re-setup.',
    );
  }

  @override
  Future<int> run() async {
    final platform = argResults!['platform'] as String;

    // Ensure we're in a Flutter project
    if (!_isFlutterProject()) {
      _logger.err('No pubspec.yaml found. Run from the root of your Flutter project.');
      return 1;
    }

    // Load existing config if present; otherwise start with empty sections
    final configFile = File(path.join(Directory.current.path, 'flightdeck.yaml'));
    Map<String, dynamic> existing = {};
    if (configFile.existsSync()) {
      try {
        final yaml = loadYaml(configFile.readAsStringSync()) as YamlMap;
        existing = _yamlMapToDart(yaml);
      } catch (e) {
        _logger.warn('Could not parse existing flightdeck.yaml: $e');
      }
    } else {
      _logger.warn('No flightdeck.yaml found. Run `flightdeck init` for the full wizard.');
      return 1;
    }

    _logger.info('\n🛫  FlightDeck Setup — Credential Refresh\n');

    String? iosBlock;
    String? androidBlock;

    final detector = ProjectDetector();

    if (platform == 'ios' || platform == 'all') {
      _printSection('iOS / App Store Connect');
      iosBlock = await _runIosSetup(detector);
      if (iosBlock == null) return 1;
    }

    if (platform == 'android' || platform == 'all') {
      _printSection('Android / Google Play');
      final packageName = (existing['app'] as Map?)?.entries
          .firstWhere((e) => e.key == 'package_name', orElse: () => MapEntry('', ''))
          .value as String? ?? '';
      androidBlock = await _runAndroidSetup(packageName);
      if (androidBlock == null) return 1;
    }

    // Re-write flightdeck.yaml, preserving app section
    final appSection = _rebuildAppSection(existing);
    final iosSection = iosBlock ?? _rebuildSection(existing, 'ios');
    final androidSection = androidBlock ?? _rebuildSection(existing, 'android');

    configFile.writeAsStringSync(
      '# flightdeck.yaml — Flutter deployment config\n\n'
      '$appSection$iosSection$androidSection',
    );

    _logger.info('');
    _logger.success('✅  flightdeck.yaml updated!\n');
    return 0;
  }

  // ── iOS setup (same logic as InitCommand) ─────────────────────────────

  Future<String?> _runIosSetup(ProjectDetector detector) async {
    _logger.info('You need an App Store Connect API Key.\n');
    _logger.info('  → appstoreconnect.apple.com/access/integrations/api\n');

    final shouldOpen = _logger.confirm('Open App Store Connect in browser?', defaultValue: true);
    if (shouldOpen) {
      await _openUrl('https://appstoreconnect.apple.com/access/integrations/api');
      _prompt('  Press Enter when ready', '');
    }

    late IosConfig tempConfig;
    while (true) {
      _logger.info('');
      final keyId = _promptRequired('API Key ID');
      final issuerId = _promptRequired('Issuer ID');
      final keyPath = _promptPath('Path to .p8 file', './keys/AuthKey.p8');

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
        _logger.success('  ✓ Connected to App Store Connect!\n');
        break;
      } on AppStoreConnectException catch (e) {
        _logger.err('  ✗ ${e.message}');
        if (!_logger.confirm('  Retry?', defaultValue: true)) return null;
      } catch (e) {
        _logger.err('  ✗ Unexpected error: $e');
        if (!_logger.confirm('  Retry?', defaultValue: true)) return null;
      }
    }

    final service = AppStoreConnectService(_logger, tempConfig);
    Map<String, dynamic> selectedApp = {'id': '', 'name': '', 'bundleId': ''};
    try {
      _logger.info('  Fetching your apps...');
      final apps = await service.fetchApps();
      if (apps.isNotEmpty) {
        selectedApp = _selectFromList('Select your iOS app', apps, display: (a) => '${a['name']} (${a['bundleId']})');
        _logger.success('  ✓ Selected: ${selectedApp['name']}\n');
      }
    } catch (e) {
      _logger.warn('  Could not fetch apps: $e');
    }

    String testflightGroup = '';
    if ((selectedApp['id'] as String).isNotEmpty) {
      try {
        _logger.info('  Fetching TestFlight groups...');
        final groups = await service.fetchBetaGroupNames(selectedApp['id'] as String);
        if (groups.isNotEmpty) {
          testflightGroup = _selectFromList('Select TestFlight group', groups, display: (g) => g);
          _logger.success('  ✓ Selected: $testflightGroup\n');
        }
      } catch (e) {
        _logger.warn('  Could not fetch TestFlight groups: $e');
      }
    }

    _logger.info('');
    final teamId = _promptRequired('Apple Team ID (e.g. ABCD1234EF)\n  Team ID', detector.detectIosTeamId());
    final profile = _selectFromList('Distribution profile', ['distribution', 'adhoc', 'development'], display: (p) => p);
    final scheme = _prompt('Xcode scheme', detector.detectIosScheme() ?? 'Runner');

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

  // ── Android setup ─────────────────────────────────────────────────────

  Future<String?> _runAndroidSetup(String packageName) async {
    _logger.info('  → play.google.com/console/developers/api-access\n');

    final shouldOpen = _logger.confirm('Open Google Play Console in browser?', defaultValue: true);
    if (shouldOpen) {
      await _openUrl('https://play.google.com/console/developers/api-access');
      _prompt('  Press Enter when ready', '');
    }

    final keystorePath = _promptPath('Path to keystore file', './keys/release.keystore');
    final keyAlias = _prompt('Key alias', 'release');

    _logger.info('');
    String serviceAccountPath = '';
    while (true) {
      serviceAccountPath = _promptPath('Path to service account JSON', './keys/play-service-account.json');
      if (File(serviceAccountPath).existsSync()) {
        _logger.success('  ✓ Service account file found\n');
        break;
      }
      _logger.err('  File not found: $serviceAccountPath');
      if (!_logger.confirm('  Try again?', defaultValue: true)) break;
    }

    final track = _selectFromList('Play Store track', ['internal', 'alpha', 'beta', 'production'], display: (t) => t);
    final artifactRaw = _selectFromList('Build artifact', ['aab (recommended)', 'apk'], display: (a) => a);
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

  // ── Config helpers ────────────────────────────────────────────────────

  String _rebuildAppSection(Map<String, dynamic> existing) {
    final app = existing['app'] as Map? ?? {};
    final name = app['name'] ?? 'MyApp';
    final bundleId = app['bundle_id'] ?? 'com.yourcompany.myapp';
    final packageName = app['package_name'] ?? bundleId;
    return 'app:\n  name: "$name"\n  bundle_id: "$bundleId"\n  package_name: "$packageName"\n';
  }

  String _rebuildSection(Map<String, dynamic> existing, String section) {
    if (!existing.containsKey(section)) return '';
    // Re-serialize a simplified version of the section
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

  // ── Shared UI helpers ─────────────────────────────────────────────────

  void _printSection(String title) {
    _logger.info('\n${'─' * 52}');
    _logger.info('  $title');
    _logger.info('${'─' * 52}\n');
  }

  String _prompt(String label, String defaultValue) {
    if (defaultValue.isNotEmpty) {
      stdout.write('  $label [$defaultValue]: ');
    } else {
      stdout.write('  $label: ');
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  String _promptRequired(String label, [String? defaultValue]) {
    while (true) {
      if (defaultValue != null && defaultValue.isNotEmpty) {
        stdout.write('  $label [$defaultValue]: ');
      } else {
        stdout.write('  $label: ');
      }
      final input = stdin.readLineSync()?.trim() ?? '';
      if (input.isNotEmpty) return input;
      if (defaultValue != null && defaultValue.isNotEmpty) return defaultValue;
      _logger.warn('  This field is required.');
    }
  }

  String _promptPath(String label, String defaultValue) {
    final raw = _prompt(label, defaultValue);
    if (raw.startsWith('~/')) {
      return path.join(Platform.environment['HOME'] ?? '', raw.substring(2));
    }
    return raw;
  }

  T _selectFromList<T>(String label, List<T> items, {required String Function(T) display}) {
    _logger.info('  $label:\n');
    for (var i = 0; i < items.length; i++) {
      _logger.info('    ${i + 1}) ${display(items[i])}');
    }
    _logger.info('');
    while (true) {
      stdout.write('  Enter number [1]: ');
      final input = stdin.readLineSync()?.trim() ?? '';
      final index = input.isEmpty ? 1 : int.tryParse(input);
      if (index != null && index >= 1 && index <= items.length) return items[index - 1];
      _logger.warn('  Enter a number between 1 and ${items.length}.');
    }
  }

  Future<void> _openUrl(String url) async {
    _logger.info('  Opening: $url');
    try {
      if (Platform.isMacOS) await Process.run('open', [url]);
      else if (Platform.isLinux) await Process.run('xdg-open', [url]);
      else if (Platform.isWindows) await Process.run('start', [url], runInShell: true);
    } catch (_) {}
  }

  bool _isFlutterProject() {
    final pubspec = File(path.join(Directory.current.path, 'pubspec.yaml'));
    return pubspec.existsSync() && pubspec.readAsStringSync().contains('flutter:');
  }
}
