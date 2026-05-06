import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/init_command.dart';
import 'commands/setup_command.dart';
import 'commands/deploy_command.dart';
import 'commands/build_command.dart';
import 'commands/certs_command.dart';
import 'commands/env_command.dart';

class FlightDeckRunner {
  final Logger _logger = Logger();

  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>(
      'flightdeck',
      '🛫  Deploy Flutter apps to App Store & Google Play — one command.',
    )
      ..addCommand(InitCommand(_logger))
      ..addCommand(SetupCommand(_logger))
      ..addCommand(DeployCommand(_logger))
      ..addCommand(BuildCommand(_logger))
      ..addCommand(CertsCommand(_logger))
      ..addCommand(EnvCommand(_logger));

    // Add global flags
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
        _logger.info('flightdeck v0.1.0');
        return 0;
      }

      if (args.isEmpty) {
        _printBanner();
        _logger.info(runner.usage);
        return 0;
      }

      return await runner.run(args) ?? 0;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info(e.usage);
      return 64; // EX_USAGE
    } catch (e) {
      _logger.err('Unexpected error: $e');
      return 1;
    }
  }

  void _printBanner() {
    _logger.info('''

  ██████╗ ██╗     ██╗ ██████╗ ██╗  ██╗████████╗██████╗ ███████╗ ██████╗██╗  ██╗
  ██╔════╝ ██║    ██║██╔════╝ ██║  ██║╚══██╔══╝██╔══██╗██╔════╝██╔════╝██║ ██╔╝
  █████╗   ██║    ██║██║  ███╗███████║   ██║   ██║  ██║█████╗  ██║     █████╔╝ 
  ██╔══╝   ██║    ██║██║   ██║██╔══██║   ██║   ██║  ██║██╔══╝  ██║     ██╔═██╗ 
  ██║      ███████╗██║╚██████╔╝██║  ██║   ██║   ██████╔╝███████╗╚██████╗██║  ██╗
  ╚═╝      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═════╝ ╚══════╝ ╚═════╝╚═╝  ╚═╝

  Deploy Flutter apps to App Store & Google Play — one command.
''');
  }
}
