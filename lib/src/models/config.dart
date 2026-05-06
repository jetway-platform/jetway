import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;

/// Represents a fully parsed and validated flightdeck.yaml config.
class FlightDeckConfig {
  final AppConfig app;
  final IosConfig? ios;
  final AndroidConfig? android;

  const FlightDeckConfig({
    required this.app,
    this.ios,
    this.android,
  });

  /// Loads config from [filePath], defaults to ./flightdeck.yaml
  factory FlightDeckConfig.fromFile([String? filePath]) {
    final configPath = filePath ?? path.join(Directory.current.path, 'flightdeck.yaml');
    final file = File(configPath);

    if (!file.existsSync()) {
      throw FlightDeckConfigException(
        'No flightdeck.yaml found at $configPath\n'
        'Run: flightdeck init',
      );
    }

    final raw = loadYaml(file.readAsStringSync()) as YamlMap;
    return FlightDeckConfig._fromYaml(raw);
  }

  factory FlightDeckConfig._fromYaml(YamlMap yaml) {
    final appYaml = yaml['app'] as YamlMap?;
    if (appYaml == null) {
      throw FlightDeckConfigException('Missing required "app" section in flightdeck.yaml');
    }

    return FlightDeckConfig(
      app: AppConfig.fromYaml(appYaml),
      ios: yaml['ios'] != null ? IosConfig.fromYaml(yaml['ios'] as YamlMap) : null,
      android: yaml['android'] != null ? AndroidConfig.fromYaml(yaml['android'] as YamlMap) : null,
    );
  }

  /// Validates config is suitable for deploying to a given platform.
  void validateForPlatform(DeployPlatform platform) {
    switch (platform) {
      case DeployPlatform.ios:
        if (ios == null) {
          throw FlightDeckConfigException('Missing "ios" section in flightdeck.yaml');
        }
        ios!.validate();
      case DeployPlatform.android:
        if (android == null) {
          throw FlightDeckConfigException('Missing "android" section in flightdeck.yaml');
        }
        android!.validate();
      case DeployPlatform.all:
        validateForPlatform(DeployPlatform.ios);
        validateForPlatform(DeployPlatform.android);
    }
  }
}

class AppConfig {
  final String name;
  final String bundleId;     // iOS bundle identifier
  final String packageName;  // Android package name
  final String? version;     // Override pubspec.yaml version

  const AppConfig({
    required this.name,
    required this.bundleId,
    required this.packageName,
    this.version,
  });

  factory AppConfig.fromYaml(YamlMap yaml) {
    _requireKey(yaml, 'name', 'app');
    _requireKey(yaml, 'bundle_id', 'app');
    _requireKey(yaml, 'package_name', 'app');

    return AppConfig(
      name: yaml['name'] as String,
      bundleId: yaml['bundle_id'] as String,
      packageName: yaml['package_name'] as String,
      version: yaml['version'] as String?,
    );
  }
}

class IosConfig {
  final String teamId;
  final String profile;              // 'distribution' | 'adhoc' | 'development'
  final String? testflightGroup;     // TestFlight group to add build to
  final String? apiKeyId;            // App Store Connect API Key ID
  final String? apiIssuerId;         // App Store Connect Issuer ID
  final String? apiKeyPath;          // Path to .p8 key file
  final String? exportOptionsPlist;  // Custom ExportOptions.plist path
  final String? scheme;              // Xcode scheme (defaults to app name)

  const IosConfig({
    required this.teamId,
    required this.profile,
    this.testflightGroup,
    this.apiKeyId,
    this.apiIssuerId,
    this.apiKeyPath,
    this.exportOptionsPlist,
    this.scheme,
  });

  factory IosConfig.fromYaml(YamlMap yaml) {
    _requireKey(yaml, 'team_id', 'ios');

    return IosConfig(
      teamId: yaml['team_id'] as String,
      profile: yaml['profile'] as String? ?? 'distribution',
      testflightGroup: yaml['testflight_group'] as String?,
      apiKeyId: yaml['api_key_id'] as String?,
      apiIssuerId: yaml['api_issuer_id'] as String?,
      apiKeyPath: yaml['api_key_path'] as String?,
      exportOptionsPlist: yaml['export_options_plist'] as String?,
      scheme: yaml['scheme'] as String?,
    );
  }

  void validate() {
    // API key auth (preferred) or will fall back to local Xcode credentials
    final hasApiAuth = apiKeyId != null && apiIssuerId != null && apiKeyPath != null;
    final hasEnvApiAuth =
        Platform.environment.containsKey('APP_STORE_API_KEY_ID') &&
        Platform.environment.containsKey('APP_STORE_API_ISSUER_ID') &&
        Platform.environment.containsKey('APP_STORE_API_KEY_PATH');

    if (!hasApiAuth && !hasEnvApiAuth) {
      throw FlightDeckConfigException(
        'iOS deployment requires App Store Connect API credentials.\n'
        'Set api_key_id, api_issuer_id, api_key_path in flightdeck.yaml\n'
        'or set APP_STORE_API_KEY_ID, APP_STORE_API_ISSUER_ID, APP_STORE_API_KEY_PATH env vars.',
      );
    }
  }

  /// Resolved API Key ID (config > env var)
  String get resolvedApiKeyId =>
      apiKeyId ?? Platform.environment['APP_STORE_API_KEY_ID'] ?? '';

  String get resolvedApiIssuerId =>
      apiIssuerId ?? Platform.environment['APP_STORE_API_ISSUER_ID'] ?? '';

  String get resolvedApiKeyPath =>
      apiKeyPath ?? Platform.environment['APP_STORE_API_KEY_PATH'] ?? '';
}

class AndroidConfig {
  final String keystorePath;
  final String? keystorePassword;   // Can be set via env ANDROID_KEYSTORE_PASSWORD
  final String? keyAlias;
  final String? keyPassword;        // Can be set via env ANDROID_KEY_PASSWORD
  final String track;               // 'internal' | 'alpha' | 'beta' | 'production'
  final String artifact;            // 'aab' | 'apk'
  final String? serviceAccountPath; // Google Play service account JSON

  const AndroidConfig({
    required this.keystorePath,
    required this.track,
    required this.artifact,
    this.keystorePassword,
    this.keyAlias,
    this.keyPassword,
    this.serviceAccountPath,
  });

  factory AndroidConfig.fromYaml(YamlMap yaml) {
    _requireKey(yaml, 'keystore', 'android');

    final track = yaml['track'] as String? ?? 'internal';
    const validTracks = ['internal', 'alpha', 'beta', 'production'];
    if (!validTracks.contains(track)) {
      throw FlightDeckConfigException(
        'Invalid android.track: "$track". Must be one of: ${validTracks.join(', ')}',
      );
    }

    final artifact = yaml['artifact'] as String? ?? 'aab';
    if (!['aab', 'apk'].contains(artifact)) {
      throw FlightDeckConfigException(
        'Invalid android.artifact: "$artifact". Must be "aab" or "apk".',
      );
    }

    return AndroidConfig(
      keystorePath: yaml['keystore'] as String,
      keystorePassword: yaml['keystore_password'] as String?,
      keyAlias: yaml['key_alias'] as String?,
      keyPassword: yaml['key_password'] as String?,
      track: track,
      artifact: artifact,
      serviceAccountPath: yaml['service_account'] as String?,
    );
  }

  void validate() {
    if (!File(keystorePath).existsSync()) {
      throw FlightDeckConfigException(
        'Android keystore not found at: $keystorePath',
      );
    }

    final hasServiceAccount = serviceAccountPath != null ||
        Platform.environment.containsKey('GOOGLE_PLAY_SERVICE_ACCOUNT');
    if (!hasServiceAccount) {
      throw FlightDeckConfigException(
        'Android deployment requires a Google Play service account.\n'
        'Set android.service_account in flightdeck.yaml\n'
        'or set GOOGLE_PLAY_SERVICE_ACCOUNT env var (path to JSON file).',
      );
    }
  }

  String get resolvedServiceAccountPath =>
      serviceAccountPath ?? Platform.environment['GOOGLE_PLAY_SERVICE_ACCOUNT'] ?? '';

  String get resolvedKeystorePassword =>
      keystorePassword ?? Platform.environment['ANDROID_KEYSTORE_PASSWORD'] ?? '';

  String get resolvedKeyPassword =>
      keyPassword ?? Platform.environment['ANDROID_KEY_PASSWORD'] ?? '';
}

enum DeployPlatform { ios, android, all }

extension DeployPlatformParsing on DeployPlatform {
  static DeployPlatform fromString(String value) {
    switch (value.toLowerCase()) {
      case 'ios':
        return DeployPlatform.ios;
      case 'android':
        return DeployPlatform.android;
      case 'all':
        return DeployPlatform.all;
      default:
        throw FlightDeckConfigException('Unknown platform: $value. Use ios, android, or all.');
    }
  }
}

class FlightDeckConfigException implements Exception {
  final String message;
  FlightDeckConfigException(this.message);

  @override
  String toString() => message;
}

void _requireKey(YamlMap yaml, String key, String section) {
  if (!yaml.containsKey(key) || yaml[key] == null) {
    throw FlightDeckConfigException('Missing required "$section.$key" in flightdeck.yaml');
  }
}
