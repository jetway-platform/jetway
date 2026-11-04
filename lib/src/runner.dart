import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/init_command.dart';
import 'commands/setup_command.dart';
import 'commands/deploy_command.dart';
import 'commands/build_command.dart';
import 'commands/certs_command.dart';
import 'commands/env_command.dart';

class JetwayRunner {
  static const version = '0.2.5';
  final Logger _logger = Logger();

  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>(
      'jetway',
      'Deploy Flutter apps to App Store & Google Play — one command.',
    )
      ..addCommand(InitCommand(_logger))
      ..addCommand(SetupCommand(_logger))
      ..addCommand(DeployCommand(_logger))
      ..addCommand(BuildCommand(_logger))
      ..addCommand(CertsCommand(_logger))
      ..addCommand(EnvCommand(_logger));

    runner.argParser
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Enable verbose logging.',
      )
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the current version.',
      );

    try {
      if (args.contains('--version')) {
        _logger.info('jetway v$version');
        return 0;
      }

      if (args.isEmpty) {
        _logger.info(runner.usage);
        return 0;
      }

      return await runner.run(args) ?? 0;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info(e.usage);
      return 64;
    } catch (e) {
      _logger.err('Unexpected error: $e');
      return 1;
    }
  }
}
