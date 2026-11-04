import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../models/config.dart';
import '../services/flutter_build_service.dart';

class BuildCommand extends Command<int> {
  @override
  final String name = 'build';

  @override
  final String description = 'Build release artifacts for iOS and/or Android without uploading.';

  final Logger _logger;

  BuildCommand(this._logger) {
    argParser
      ..addOption(
        'platform',
        abbr: 'p',
        allowed: ['ios', 'android', 'all'],
        defaultsTo: 'all',
        help: 'Target platform.',
      )
      ..addOption(
        'build-number',
        abbr: 'b',
        help: 'Build number override.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show verbose build output.',
      );
  }

  @override
  Future<int> run() async {
    final platform = DeployPlatformParsing.fromString(argResults!['platform'] as String);
    final buildNumber = argResults!['build-number'] as String?;
    final verbose = argResults!['verbose'] as bool;

    final FlightDeckConfig config;
    try {
      config = FlightDeckConfig.fromFile();
    } on FlightDeckConfigException catch (e) {
      _logger.err(e.message);
      return 1;
    }

    _logger.info('\nFlightDeck Build\n');

    try {
      final buildService = FlutterBuildService(_logger, verbose: verbose);
      await buildService.validate();
      await buildService.pubGet();
      _logger.info('');

      if (platform == DeployPlatform.ios || platform == DeployPlatform.all) {
        _logger.info('Building iOS...');
        final ipaPath = await buildService.buildIos(config: config, buildNumber: buildNumber);
        _logger.info('  Output: $ipaPath\n');
      }

      if (platform == DeployPlatform.android || platform == DeployPlatform.all) {
        _logger.info('Building Android...');
        final artifactPath = await buildService.buildAndroid(config: config, buildNumber: buildNumber);
        _logger.info('  Output: $artifactPath\n');
      }

      _logger.success('Build complete.\n');
      return 0;
    } on FlightDeckBuildException catch (e) {
      _logger.err('Build failed: ${e.message}');
      return 1;
    }
  }
}
