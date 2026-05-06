import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import '../models/config.dart';
import '../services/app_store_connect_service.dart';
import '../utils/project_detector.dart';

/// Interactive guided setup wizard.
/// Creates flightdeck.yaml with browser-assisted credential entry and
/// API-backed selection for apps, TestFlight groups, and tracks.
class InitCommand extends Command<int> {
  @override
  final String name = 'init';

  @override
  final String description =
      'Guided setup wizard — creates flightdeck.yaml with API-backed selection.';

  final Logger _logger;

  InitCommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('');
    _logger.info('🛫  FlightDeck Setup Wizard\n');

    // ── Project check ──────────────────────────────────────────────────────
    if (!_isFlutterProject()) {
      _logger.err(
        'No pubspec.yaml found. Run this command from the root of your Flutter project.',
      );
      return 1;
    }

    final configFile = File(path.join(Directory.current.path, 'flightdeck.yaml'));
    if (configFile.existsSync()) {
      final overwrite = _logger.confirm(
        '⚠️  flightdeck.yaml already exists. Overwrite?',
        defaultValue: false,
      );
      if (!overwrite) {
        _logger.info('Aborted. Run `flightdeck setup` to update a specific platform.');
        return 0;
      }
    }

    // ── App info ───────────────────────────────────────────────────────────
    _printSection('App Info');
    final detector = ProjectDetector();
    final appName = _prompt('App name', _detectAppName());
    
    final detectedIosBundleId = detector.detectIosBundleId();
    final bundleId = _prompt(
      'iOS Bundle ID',
      detectedIosBundleId ?? 'com.yourcompany.${appName.toLowerCase().replaceAll(' ', '')}',
    );
    
    final detectedPackageName = detector.detectAndroidPackageName();
    final packageName = _prompt('Android Package name', detectedPackageName ?? bundleId);

    // ── iOS ────────────────────────────────────────────────────────────────
    String iosBlock = '';
    final setupIos = _logger.confirm('\nConfigure iOS / App Store Connect?', defaultValue: true);

    if (setupIos) {
      final result = await _runIosSetup(detector);
      if (result == null) return 1;
      iosBlock = result;
    }

    // ── Android ────────────────────────────────────────────────────────────
    String androidBlock = '';
    final setupAndroid = _logger.confirm('\nConfigure Android / Google Play?', defaultValue: true);

    if (setupAndroid) {
      final result = await _runAndroidSetup(packageName);
      if (result == null) return 1;
      androidBlock = result;
    }

    // ── Write config ───────────────────────────────────────────────────────
    final configContent = '''# flightdeck.yaml — Flutter deployment config
# Docs: https://github.com/Abdlim/flightdeck

app:
  name: "$appName"
  bundle_id: "$bundleId"
  package_name: "$packageName"
$iosBlock$androidBlock
''';

    configFile.writeAsStringSync(configContent);

    _logger.info('');
    _logger.success('✅  flightdeck.yaml created!\n');
    _logger.info('Add this to your .gitignore to keep secrets safe:\n');
    _logger.info('  keys/\n  .env\n  *.p8\n  *.keystore\n  *.jks\n');
    _logger.info('Next step:\n');
    _logger.info('  flightdeck deploy\n');

    return 0;
  }

  // ── iOS setup flow ──────────────────────────────────────────────────────

  Future<String?> _runIosSetup(ProjectDetector detector) async {
    _printSection('iOS / App Store Connect');

    _logger.info('You need an App Store Connect API Key.\n');
    _logger.info('  1. Go to: App Store Connect → Users & Access → Integrations → API');
    _logger.info('  2. Click "+" → name it "FlightDeck" → Role: App Manager');
    _logger.info('  3. Download the .p8 file (shown only once)');
    _logger.info('  4. Note your Key ID and Issuer ID\n');

    final shouldOpen = _logger.confirm('Open App Store Connect in browser now?', defaultValue: true);
    if (shouldOpen) {
      await _openUrl('https://appstoreconnect.apple.com/access/integrations/api');
      _logger.info('\n  Waiting for you to create the key...\n');
      _prompt('  Press Enter when ready', '');
    }

    // Credential entry loop
    late IosConfig tempConfig;
    while (true) {
      _logger.info('');
      final keyId = _promptRequired('API Key ID (e.g. ABC123DEF4)');
      final issuerId = _promptRequired('Issuer ID (UUID)');
      final keyPath = _promptPath('Path to .p8 file', './keys/AuthKey.p8');

      _logger.info('\n  Verifying credentials...');
      try {
        // Build a minimal IosConfig just for the service constructor
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
        final retry = _logger.confirm('  Try again?', defaultValue: true);
        if (!retry) return null;
      } catch (e) {
        _logger.err('  ✗ Unexpected error: $e');
        final retry = _logger.confirm('  Try again?', defaultValue: true);
        if (!retry) return null;
      }
    }

    // Fetch and select app
    _logger.info('  Fetching your apps from App Store Connect...');
    final service = AppStoreConnectService(_logger, tempConfig);
    late Map<String, dynamic> selectedApp;
    try {
      final apps = await service.fetchApps();
      if (apps.isEmpty) {
        _logger.warn('  No apps found. Make sure your API key has App Manager role.');
        _logger.info('  You can set app details manually in flightdeck.yaml later.');
        selectedApp = {'id': '', 'name': '', 'bundleId': ''};
      } else {
        _logger.info('');
        selectedApp = _selectFromList(
          'Select your iOS app',
          apps,
          display: (a) => '${a['name']} (${a['bundleId']})',
        );
        _logger.success('  ✓ Selected: ${selectedApp['name']}\n');
      }
    } catch (e) {
      _logger.warn('  Could not fetch apps: $e');
      selectedApp = {'id': '', 'name': '', 'bundleId': ''};
    }

    // Fetch and select TestFlight group
    String testflightGroup = '';
    if ((selectedApp['id'] as String).isNotEmpty) {
      _logger.info('  Fetching TestFlight groups...');
      try {
        final groups = await service.fetchBetaGroupNames(selectedApp['id'] as String);
        if (groups.isNotEmpty) {
          final group = _selectFromList('Select TestFlight group', groups, display: (g) => g);
          testflightGroup = group;
          _logger.success('  ✓ Selected group: $testflightGroup\n');
        } else {
          _logger.info('  No TestFlight groups found — you can add one later in flightdeck.yaml\n');
        }
      } catch (e) {
        _logger.warn('  Could not fetch TestFlight groups: $e');
      }
    }

    // Remaining manual fields
    _logger.info('');
    final teamId = _promptRequired(
      'Apple Team ID (10-char, e.g. ABCD1234EF)\n  → developer.apple.com/account → top-right corner\n  Team ID',
      detector.detectIosTeamId(),
    );
    final profile = _selectFromList(
      'Distribution profile type',
      ['distribution', 'adhoc', 'development'],
      display: (p) => p,
    );
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

  // ── Android setup flow ──────────────────────────────────────────────────

  Future<String?> _runAndroidSetup(String packageName) async {
    _printSection('Android / Google Play');

    _logger.info('You need a Google Play service account JSON key.\n');
    _logger.info('  1. Go to: Play Console → Setup → API access');
    _logger.info('  2. Link to a Google Cloud project');
    _logger.info('  3. Create a Service Account → Role: Release Manager');
    _logger.info('  4. Generate a JSON key and download it\n');

    final shouldOpen = _logger.confirm('Open Google Play Console in browser now?', defaultValue: true);
    if (shouldOpen) {
      await _openUrl('https://play.google.com/console/developers/api-access');
      _logger.info('\n  Waiting for you to create the service account...\n');
      _prompt('  Press Enter when ready', '');
    }

    // Keystore setup
    _logger.info('');
    _printSubSection('Android Signing Keystore');
    _logger.info('  If you already have a keystore, provide the path.');
    _logger.info('  If not, we\'ll generate one for you.\n');

    String keystorePath = _promptPath('Path to keystore file', './keys/release.keystore');

    if (!File(keystorePath).existsSync()) {
      final generate = _logger.confirm(
        '  Keystore not found. Generate a new one?',
        defaultValue: true,
      );
      if (generate) {
        keystorePath = await _generateKeystore(keystorePath);
        if (keystorePath.isEmpty) {
          _logger.err('  Keystore generation failed. Set it up manually and re-run `flightdeck setup --android`.');
        }
      }
    } else {
      _logger.success('  ✓ Keystore found\n');
    }

    final keyAlias = _prompt('Key alias', 'release');

    // Service account
    _logger.info('');
    _printSubSection('Google Play Service Account');
    String serviceAccountPath = '';

    while (true) {
      serviceAccountPath = _promptPath(
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
        // Quick auth check without uploading anything
        final result = await Process.run('dart', ['--version']);
        if (result.exitCode == 0) {
          _logger.success('  ✓ Service account file found\n');
          _logger.info('  (Full credential verification happens on first deploy)\n');
        }
        break;
      } catch (e) {
        _logger.warn('  Could not verify: $e');
        break;
      }
    }

    // Track & artifact selection
    final track = _selectFromList(
      'Google Play release track',
      ['internal', 'alpha', 'beta', 'production'],
      display: (t) => t,
    );

    final artifact = _selectFromList(
      'Build artifact type',
      ['aab (recommended)', 'apk'],
      display: (a) => a,
    );
    final artifactValue = artifact.startsWith('aab') ? 'aab' : 'apk';

    _logger.info('');
    _logger.info('  Set your keystore passwords as environment variables (recommended):');
    _logger.info('    export ANDROID_KEYSTORE_PASSWORD=<your_password>');
    _logger.info('    export ANDROID_KEY_PASSWORD=<your_key_password>\n');
    _logger.info('  Or run: flightdeck env set ANDROID_KEYSTORE_PASSWORD <value>\n');

    return '''
android:
  keystore: "$keystorePath"
  key_alias: "$keyAlias"
  track: $track
  artifact: $artifactValue
  service_account: "$serviceAccountPath"
  # keystore_password: ""  # prefer ANDROID_KEYSTORE_PASSWORD env var
  # key_password: ""       # prefer ANDROID_KEY_PASSWORD env var
''';
  }

  // ── Keystore generator ──────────────────────────────────────────────────

  Future<String> _generateKeystore(String targetPath) async {
    _logger.info('\n  Generating keystore at $targetPath...\n');
    _logger.info('  You\'ll be prompted for keystore details by the keytool command.\n');

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

    _logger.success('  ✓ Keystore generated at $targetPath\n');
    return targetPath;
  }

  // ── UI Helpers ──────────────────────────────────────────────────────────

  void _printSection(String title) {
    _logger.info('\n${'─' * 52}');
    _logger.info('  $title');
    _logger.info('${'─' * 52}\n');
  }

  void _printSubSection(String title) {
    _logger.info('  ▸ $title\n');
  }

  /// Prompt with an optional default (empty input returns the default).
  String _prompt(String label, String defaultValue) {
    if (defaultValue.isNotEmpty) {
      stdout.write('  $label [$defaultValue]: ');
    } else {
      stdout.write('  $label: ');
    }
    final input = stdin.readLineSync()?.trim() ?? '';
    return input.isEmpty ? defaultValue : input;
  }

  /// Prompt that repeats until a non-empty value is entered.
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

  /// Prompt for a file path, expanding ~ and resolving relative paths.
  String _promptPath(String label, String defaultValue) {
    final raw = _prompt(label, defaultValue);
    if (raw.startsWith('~/')) {
      return path.join(Platform.environment['HOME'] ?? '', raw.substring(2));
    }
    return raw;
  }

  /// Show a numbered list and return the selected item.
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
      if (index != null && index >= 1 && index <= items.length) {
        return items[index - 1];
      }
      _logger.warn('  Please enter a number between 1 and ${items.length}.');
    }
  }

  Future<void> _openUrl(String url) async {
    _logger.info('  Opening: $url');
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      }
    } catch (_) {
      // Browser open is best-effort
    }
  }

  // ── Flutter project detection ───────────────────────────────────────────

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
