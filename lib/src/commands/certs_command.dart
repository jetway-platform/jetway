import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../models/config.dart';
import '../services/app_store_connect_service.dart';

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
  final String description = 'Verify signing credentials and refresh Xcode provisioning cache.';

  final Logger _logger;

  _CertsSyncSubcommand(this._logger);

  @override
  Future<int> run() async {
    if (!Platform.isMacOS) {
      _logger.err('certs command is only supported on macOS.');
      return 1;
    }

    _logger.info('\nFlightDeck Certs Sync\n');

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
      _logger.info('  Verifying App Store Connect API credentials...');
      final asc = AppStoreConnectService(_logger, config.ios!);
      await asc.verifyCredentials();
      _logger.success('  App Store Connect credentials verified.');

      _logger.info('  Checking certificates in keychain...');
      final certResult = await Process.run('security', [
        'find-identity',
        '-v',
        '-p', 'codesigning',
      ]);

      final certOutput = certResult.stdout as String;
      final certCount = RegExp(r'valid identities found').hasMatch(certOutput)
          ? certOutput.split('\n').where((l) => l.contains('iPhone Distribution') || l.contains('Apple Distribution')).length
          : 0;

      _logger.success('  Found $certCount distribution certificate(s).');

      _logger.info('  Refreshing Xcode provisioning cache...');
      await Process.run('defaults', [
        'write',
        'com.apple.dt.Xcode',
        'IDEProvisioningTeamManagerLastCheckedDate',
        '0',
      ]);

      _logger.info('');
      _logger.success('Certificates synced successfully.\n');
      return 0;
    } catch (e) {
      _logger.err('Cert sync failed: $e');
      return 1;
    }
  }
}

class _CertsCheckSubcommand extends Command<int> {
  @override
  final String name = 'check';

  @override
  final String description = 'Check installed code signing identities in the macOS keychain.';

  final Logger _logger;

  _CertsCheckSubcommand(this._logger);

  @override
  Future<int> run() async {
    if (!Platform.isMacOS) {
      _logger.err('certs check is only supported on macOS.');
      return 1;
    }

    _logger.info('\nCertificate Status\n');

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
      return 1;
    }

    for (final line in lines) {
      _logger.info('  ${line.trim()}');
    }

    _logger.info('');
    return 0;
  }
}

class _CertsListSubcommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description = 'List installed provisioning profiles.';

  final Logger _logger;

  _CertsListSubcommand(this._logger);

  @override
  Future<int> run() async {
    if (!Platform.isMacOS) {
      _logger.err('certs list is only supported on macOS.');
      return 1;
    }

    _logger.info('\nProvisioning Profiles\n');

    final profilesDir = Directory(
      '${Platform.environment['HOME']}/Library/MobileDevice/Provisioning Profiles',
    );

    if (!profilesDir.existsSync()) {
      _logger.warn('  No provisioning profiles directory found.');
      return 1;
    }

    final profiles = profilesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mobileprovision'))
        .toList();

    if (profiles.isEmpty) {
      _logger.warn('  No provisioning profiles installed.');
      return 1;
    }

    for (final profile in profiles) {
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
