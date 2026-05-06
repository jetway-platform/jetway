import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Manages FlightDeck secrets and environment variables.
///
/// Usage:
///   flightdeck env set KEY value
///   flightdeck env get KEY
///   flightdeck env list
///   flightdeck env check    # check all required vars are set
class EnvCommand extends Command<int> {
  @override
  final String name = 'env';

  @override
  final String description = 'Manage FlightDeck environment variables and secrets.';

  final Logger _logger;

  EnvCommand(this._logger) {
    addSubcommand(_EnvSetSubcommand(_logger));
    addSubcommand(_EnvGetSubcommand(_logger));
    addSubcommand(_EnvListSubcommand(_logger));
    addSubcommand(_EnvCheckSubcommand(_logger));
  }

  @override
  Future<int> run() async {
    _logger.info(usage);
    return 0;
  }
}

/// All environment variables FlightDeck recognises.
const _knownVars = {
  // iOS / App Store Connect
  'APP_STORE_API_KEY_ID': 'App Store Connect API Key ID',
  'APP_STORE_API_ISSUER_ID': 'App Store Connect Issuer ID',
  'APP_STORE_API_KEY_PATH': 'Path to .p8 API key file',
  // Android / Google Play
  'GOOGLE_PLAY_SERVICE_ACCOUNT': 'Path to Google Play service account JSON',
  'ANDROID_KEYSTORE_PASSWORD': 'Android keystore password',
  'ANDROID_KEY_PASSWORD': 'Android key password',
};

class _EnvSetSubcommand extends Command<int> {
  @override
  final String name = 'set';

  @override
  final String description = 'Set an environment variable in .env file.';

  final Logger _logger;

  _EnvSetSubcommand(this._logger);

  @override
  String get invocation => 'flightdeck env set KEY VALUE';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      _logger.err('Usage: flightdeck env set KEY VALUE');
      return 64;
    }

    final key = rest[0].toUpperCase();
    final value = rest[1];

    if (!_knownVars.containsKey(key)) {
      _logger.warn('Unknown variable: $key');
      _logger.info('Known variables: ${_knownVars.keys.join(', ')}');
    }

    final envFile = File('.env');
    final lines = envFile.existsSync() ? envFile.readAsLinesSync() : <String>[];

    // Update existing or append
    final existing = lines.indexWhere((l) => l.startsWith('$key='));
    if (existing >= 0) {
      lines[existing] = '$key=$value';
    } else {
      lines.add('$key=$value');
    }

    envFile.writeAsStringSync(lines.join('\n') + '\n');
    _logger.success('✓ Set $key in .env');

    // Remind about .gitignore
    final gitignore = File('.gitignore');
    if (gitignore.existsSync() && !gitignore.readAsStringSync().contains('.env')) {
      _logger.warn('⚠️  Add .env to your .gitignore to avoid committing secrets!');
    }

    return 0;
  }
}

class _EnvGetSubcommand extends Command<int> {
  @override
  final String name = 'get';

  @override
  final String description = 'Get the value of an environment variable.';

  final Logger _logger;

  _EnvGetSubcommand(this._logger);

  @override
  String get invocation => 'flightdeck env get KEY';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      _logger.err('Usage: flightdeck env get KEY');
      return 64;
    }

    final key = rest[0].toUpperCase();
    final value = Platform.environment[key] ?? _readFromEnvFile(key);

    if (value == null) {
      _logger.warn('$key is not set');
      return 1;
    }

    // Mask sensitive values
    final masked = value.length > 4
        ? '${'*' * (value.length - 4)}${value.substring(value.length - 4)}'
        : '****';
    _logger.info('$key = $masked');
    return 0;
  }

  String? _readFromEnvFile(String key) {
    final envFile = File('.env');
    if (!envFile.existsSync()) return null;
    for (final line in envFile.readAsLinesSync()) {
      if (line.startsWith('$key=')) {
        return line.substring(key.length + 1);
      }
    }
    return null;
  }
}

class _EnvListSubcommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description = 'List all FlightDeck environment variables and their status.';

  final Logger _logger;

  _EnvListSubcommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('\n🔑 FlightDeck Environment Variables\n');

    final envContent = File('.env').existsSync()
        ? Map.fromEntries(
            File('.env').readAsLinesSync()
              .where((l) => l.contains('=') && !l.startsWith('#'))
              .map((l) {
                final idx = l.indexOf('=');
                return MapEntry(l.substring(0, idx), l.substring(idx + 1));
              }),
          )
        : <String, String>{};

    for (final entry in _knownVars.entries) {
      final key = entry.key;
      final desc = entry.value;
      final value = Platform.environment[key] ?? envContent[key];
      final isSet = value != null && value.isNotEmpty;
      final status = isSet ? '✓ set' : '✗ not set';
      _logger.info('  ${isSet ? "✓" : "✗"} $key');
      _logger.info('    $desc — $status');
    }

    _logger.info('');
    return 0;
  }
}

class _EnvCheckSubcommand extends Command<int> {
  @override
  final String name = 'check';

  @override
  final String description = 'Check all required environment variables are configured.';

  final Logger _logger;

  _EnvCheckSubcommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('\n🔍 Checking FlightDeck environment...\n');

    final envContent = File('.env').existsSync()
        ? Map.fromEntries(
            File('.env').readAsLinesSync()
              .where((l) => l.contains('=') && !l.startsWith('#'))
              .map((l) {
                final idx = l.indexOf('=');
                return MapEntry(l.substring(0, idx), l.substring(idx + 1));
              }),
          )
        : <String, String>{};

    var allGood = true;
    for (final entry in _knownVars.entries) {
      final key = entry.key;
      final value = Platform.environment[key] ?? envContent[key];
      final isSet = value != null && value.isNotEmpty;
      if (!isSet) {
        _logger.warn('  ✗ $key — not set');
        allGood = false;
      } else {
        _logger.success('  ✓ $key');
      }
    }

    _logger.info('');
    if (allGood) {
      _logger.success('✔ All environment variables are configured.\n');
    } else {
      _logger.warn('Some variables are missing. Run: flightdeck env set KEY VALUE\n');
    }

    return allGood ? 0 : 1;
  }
}
