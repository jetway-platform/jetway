import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import '../models/config.dart';

/// Manages Apple certificates and provisioning profiles.
///
/// Usage:
///   flightdeck certs sync     # download/refresh certs from Apple
///   flightdeck certs check    # check current cert status
///   flightdeck certs list     # list available profiles
class CertsCommand extends Command<int> {
  @override
  final String name = 'certs';

  @override
  final String description = 'Manage Apple certificates and provisioning profiles.';

  final Logger _logger;

  CertsCommand(this._logger) {
    addSubcommand(_CertsSyncSubcommand(_logger));
    addSubcommand(_CertsCheckSubcommand(_logger));
    addSubcommand(_CertsListSubcommand(_logger));
  }

  @override
  Future<int> run() async {
    _logger.info(usage);
    return 0;
  }
}

class _CertsSyncSubcommand extends Command<int> {
  @override
  final String name = 'sync';

  @override
  final String description = 'Download and install the latest Apple certificates and provisioning profiles.';

  final Logger _logger;

  _CertsSyncSubcommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('\n🔐 FlightDeck Certs Sync\n');

    final FlightDeckConfig config;
    try {
      config = FlightDeckConfig.fromFile();
    } on FlightDeckConfigException catch (e) {
      _logger.err(e.message);
      return 1;
    }

    if (config.ios == null) {
      _logger.err('No iOS config found in flightdeck.yaml');
      return 1;
    }

    try {
      // Step 1: Use xcrun to download provisioning profiles via Apple API
      _logger.info('  Fetching provisioning profiles from Apple...');
      final profilesResult = await _runXcrun([
        'altool',
        '--list-provisioning-profiles',
        '--apiKey', config.ios!.resolvedApiKeyId,
        '--apiIssuer', config.ios!.resolvedApiIssuerId,
      ]);

      if (profilesResult.exitCode != 0) {
        throw Exception('Failed to fetch profiles: ${profilesResult.stderr}');
      }

      _logger.success('  ✓ Provisioning profiles fetched');

      // Step 2: Check for expired certificates in the keychain
      _logger.info('  Checking certificates in keychain...');
      final certResult = await _runProcess('security', [
        'find-identity',
        '-v',
        '-p', 'codesigning',
      ]);

      final certOutput = certResult.stdout as String;
      final certCount = RegExp(r'valid identities found').hasMatch(certOutput)
          ? certOutput.split('\n').where((l) => l.contains('iPhone Distribution')).length
          : 0;

      _logger.success('  ✓ Found $certCount valid distribution certificate(s)');

      // Step 3: Refresh Xcode's automatic signing if needed
      _logger.info('  Refreshing Xcode provisioning profile cache...');
      await _runProcess('defaults', [
        'write',
        'com.apple.dt.Xcode',
        'IDEProvisioningTeamManagerLastCheckedDate',
        '0',
      ]);

      _logger.info('');
      _logger.success('✔ Certificates synced successfully\n');
      return 0;
    } catch (e) {
      _logger.err('Cert sync failed: $e');
      return 1;
    }
  }

  Future<ProcessResult> _runXcrun(List<String> args) =>
      Process.run('xcrun', args);

  Future<ProcessResult> _runProcess(String exe, List<String> args) =>
      Process.run(exe, args);
}

class _CertsCheckSubcommand extends Command<int> {
  @override
  final String name = 'check';

  @override
  final String description = 'Check status of installed certificates and provisioning profiles.';

  final Logger _logger;

  _CertsCheckSubcommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('\n🔐 Certificate Status\n');

    // List valid signing identities from keychain
    final result = await Process.run('security', [
      'find-identity',
      '-v',
      '-p', 'codesigning',
    ]);

    final lines = (result.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty && l.contains(')'))
        .toList();

    if (lines.isEmpty) {
      _logger.warn('  No valid code signing identities found in keychain.');
      _logger.info('  Run: flightdeck certs sync');
      return 1;
    }

    for (final line in lines) {
      final isDistribution = line.contains('iPhone Distribution') || line.contains('Apple Distribution');
      final icon = isDistribution ? '✓' : '○';
      final color = isDistribution ? '  $icon ' : '  $icon ';
      _logger.info('$color${line.trim()}');
    }

    _logger.info('');
    return 0;
  }
}

class _CertsListSubcommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description = 'List available provisioning profiles.';

  final Logger _logger;

  _CertsListSubcommand(this._logger);

  @override
  Future<int> run() async {
    _logger.info('\n📋 Provisioning Profiles\n');

    // Provisioning profiles are stored in ~/Library/MobileDevice/Provisioning Profiles/
    final profilesDir = Directory(
      '${Platform.environment['HOME']}/Library/MobileDevice/Provisioning Profiles',
    );

    if (!profilesDir.existsSync()) {
      _logger.warn('  No provisioning profiles directory found.');
      _logger.info('  Run: flightdeck certs sync');
      return 1;
    }

    final profiles = profilesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mobileprovision'))
        .toList();

    if (profiles.isEmpty) {
      _logger.warn('  No provisioning profiles installed.');
      _logger.info('  Run: flightdeck certs sync');
      return 1;
    }

    for (final profile in profiles) {
      // Read profile metadata using security command
      final result = await Process.run('security', [
        'cms',
        '-D',
        '-i', profile.path,
      ]);

      if (result.exitCode == 0) {
        final content = result.stdout as String;
        final nameMatch = RegExp(r'<key>Name</key>\s*<string>(.*?)</string>').firstMatch(content);
        final expiryMatch = RegExp(r'<key>ExpirationDate</key>\s*<date>(.*?)</date>').firstMatch(content);

        final name = nameMatch?.group(1) ?? 'Unknown';
        final expiry = expiryMatch?.group(1)?.substring(0, 10) ?? 'Unknown';

        _logger.info('  • $name (expires: $expiry)');
      }
    }

    _logger.info('');
    return 0;
  }
}
