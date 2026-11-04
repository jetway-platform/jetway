import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import '../models/config.dart';
import '../services/flutter_build_service.dart';
import '../services/app_store_connect_service.dart';
import '../services/google_play_service.dart';

/// The main deploy command. Builds and submits to App Store and/or Google Play.
///
/// Usage:
///   flightdeck deploy                    # deploys to both platforms
///   flightdeck deploy --platform ios
///   flightdeck deploy --platform android
///   flightdeck deploy --track beta
///   flightdeck deploy --build-number 42
///   flightdeck deploy --skip-build       # upload pre-built artifacts
class DeployCommand extends Command<int> {
  @override
  final String name = 'deploy';

  @override
  final String description = 'Build and deploy your Flutter app to App Store and/or Google Play.';

  final Logger _logger;

  DeployCommand(this._logger) {
    argParser
      ..addOption(
        'platform',
        abbr: 'p',
        help: 'Target platform.',
        allowed: ['ios', 'android', 'all'],
        defaultsTo: 'all',
      )
      ..addOption(
        'track',
        abbr: 't',
        help: 'Deployment track. Overrides flightdeck.yaml track.',
        allowed: ['internal', 'alpha', 'beta', 'production'],
      )
      ..addOption(
        'build-number',
        abbr: 'b',
        help: 'Build number. Overrides pubspec.yaml build number.',
      )
      ..addOption(
        'release-notes',
        help: 'Release notes for this build.',
      )
      ..addFlag(
        'skip-build',
        help: 'Skip building — upload previously built artifacts.',
        negatable: false,
      )
      ..addFlag(
        'skip-validate',
        help: 'Skip IPA validation step (iOS only).',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Show full build output.',
        negatable: false,
      )
      ..addOption(
        'config',
        help: 'Path to flightdeck.yaml. Defaults to ./flightdeck.yaml.',
      );
  }

  @override
  Future<int> run() async {
    final platform = DeployPlatformParsing.fromString(argResults!['platform'] as String);
    final buildNumber = argResults!['build-number'] as String?;
    final releaseNotes = argResults!['release-notes'] as String?;
    final skipBuild = argResults!['skip-build'] as bool;
    final skipValidate = argResults!['skip-validate'] as bool;
    final verbose = argResults!['verbose'] as bool;
    final configPath = argResults!['config'] as String?;

    // Load and validate config
    final FlightDeckConfig config;
    try {
      config = FlightDeckConfig.fromFile(configPath);
      config.validateForPlatform(platform);
    } on FlightDeckConfigException catch (e) {
      _logger.err(e.message);
      return 1;
    }

    _printHeader(config, platform);

    final stopwatch = Stopwatch()..start();

    try {
      // --- BUILD PHASE ---
      String? ipaPath;
      String? androidArtifactPath;

      if (!skipBuild) {
        final buildService = FlutterBuildService(_logger, verbose: verbose);
        await buildService.validate();
        await buildService.pubGet();
        _logger.info('');

        if (platform == DeployPlatform.ios || platform == DeployPlatform.all) {
          _logger.info('📦 Building iOS...');
          ipaPath = await buildService.buildIos(config: config, buildNumber: buildNumber);
          _logger.info('');
        }

        if (platform == DeployPlatform.android || platform == DeployPlatform.all) {
          _logger.info('📦 Building Android...');
          androidArtifactPath = await buildService.buildAndroid(config: config, buildNumber: buildNumber);
          _logger.info('');
        }
      } else {
        _logger.info('⏩ Skipping build step (--skip-build). Locating pre-built artifacts...');
        final buildService = FlutterBuildService(_logger, verbose: verbose);

        if (platform == DeployPlatform.ios || platform == DeployPlatform.all) {
          ipaPath = buildService.findIosArtifact();
          _logger.info('  ✓ Found iOS artifact: $ipaPath');
        }

        if (platform == DeployPlatform.android || platform == DeployPlatform.all) {
          androidArtifactPath = buildService.findAndroidArtifact(config);
          _logger.info('  ✓ Found Android artifact: $androidArtifactPath');
        }
        _logger.info('');
      }

      // --- UPLOAD PHASE ---
      String? testflightUrl;
      String? playConsoleUrl;

      if (platform == DeployPlatform.ios || platform == DeployPlatform.all) {
        if (ipaPath == null) {
          throw FlightDeckBuildException('No iOS IPA found for upload.');
        }

        _logger.info('🍎 Uploading to App Store Connect...');

        final ascService = AppStoreConnectService(_logger, config.ios!);

        if (!skipValidate) {
          await ascService.validateIpa(ipaPath: ipaPath);
        }

        await ascService.uploadIpa(
          ipaPath: ipaPath,
          bundleId: config.app.bundleId,
          verbose: verbose,
        );

        // Add to TestFlight group if configured
        if (config.ios!.testflightGroup != null) {
          final appId = await ascService.getAppId(config.app.bundleId);
          if (appId != null) {
            final latestBuild = await ascService.getLatestBuild(appId);
            if (latestBuild != null) {
              await ascService.addBuildToTestFlightGroup(
                appId: appId,
                buildId: latestBuild['id'] as String,
                groupName: config.ios!.testflightGroup!,
              );
            }
          }
        }

        testflightUrl = 'https://appstoreconnect.apple.com/apps';
        _logger.info('');
      }

      if (platform == DeployPlatform.android || platform == DeployPlatform.all) {
        if (androidArtifactPath == null) {
          throw FlightDeckBuildException('No Android artifact found for upload.');
        }

        _logger.info('🤖 Uploading to Google Play...');

        final playService = GooglePlayService(
          _logger,
          config.android!,
          config.app.packageName,
        );

        await playService.uploadArtifact(
          artifactPath: androidArtifactPath,
          releaseNotes: releaseNotes,
          verbose: verbose,
        );

        playConsoleUrl = 'https://play.google.com/console/u/0/developers';
        _logger.info('');
      }

      // --- SUMMARY ---
      stopwatch.stop();
      _printSummary(
        duration: stopwatch.elapsed,
        testflightUrl: testflightUrl,
        playConsoleUrl: playConsoleUrl,
      );

      return 0;
    } on FlightDeckBuildException catch (e) {
      _logger.err('\n✗ Build failed:\n${e.message}');
      return 1;
    } on Exception catch (e) {
      _logger.err('\n✗ Deploy failed:\n$e');
      return 1;
    }
  }

  void _printHeader(FlightDeckConfig config, DeployPlatform platform) {
    final platformStr = switch (platform) {
      DeployPlatform.ios => 'iOS only',
      DeployPlatform.android => 'Android only',
      DeployPlatform.all => 'iOS + Android',
    };

    _logger.info('');
    _logger.info('🛫  FlightDeck Deploy');
    _logger.info('   App:      ${config.app.name}');
    _logger.info('   Platform: $platformStr');
    _logger.info('');
    _logger.info('─' * 48);
    _logger.info('');
  }

  void _printSummary({
    required Duration duration,
    String? testflightUrl,
    String? playConsoleUrl,
  }) {
    final seconds = duration.inSeconds;
    final timeStr = seconds > 60
        ? '${duration.inMinutes}m ${seconds % 60}s'
        : '${seconds}s';

    _logger.info('─' * 48);
    _logger.info('');
    _logger.success('✔ Deploy complete · $timeStr');
    _logger.info('');

    if (testflightUrl != null) {
      _logger.info('  🍎 App Store Connect: $testflightUrl');
    }
    if (playConsoleUrl != null) {
      _logger.info('  🤖 Play Console:      $playConsoleUrl');
    }
    _logger.info('');
  }
}
