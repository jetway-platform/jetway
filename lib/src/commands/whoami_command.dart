import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../services/auth_storage.dart';
import '../services/jetway_api_client.dart';

class WhoamiCommand extends Command<int> {
  @override
  final String name = 'whoami';

  @override
  final String description = 'Display the currently authenticated Jetway Cloud user and workspace.';

  final Logger _logger;
  final JetwayApiClient _apiClient;
  final AuthStorage _authStorage;

  WhoamiCommand(
    this._logger, {
    JetwayApiClient? apiClient,
    AuthStorage? authStorage,
  })  : _authStorage = authStorage ?? AuthStorage(),
        _apiClient = apiClient ?? JetwayApiClient(authStorage: authStorage);

  @override
  Future<int> run() async {
    final authState = await _authStorage.read();

    if (authState == null || authState.accessToken.isEmpty) {
      _logger.info('');
      _logger.info(styleBold.wrap('Jetway Session Status:'));
      _logger.info('  Status:    ${yellow.wrap('Not logged in')}' );
      _logger.info('  Mode:      Standalone local mode (Local-First)');
      _logger.info('');
      _logger.info('Run ${lightCyan.wrap('jetway login')} to link your terminal to Jetway Cloud.');
      _logger.info('');
      return 0;
    }

    final progress = _logger.progress('Retrieving developer profile...');
    UserProfile profile;
    try {
      profile = await _apiClient.getProfile(token: authState.accessToken);
      progress.complete('Profile loaded.');
    } on JetwayAuthException catch (e) {
      progress.fail(e.message);
      _logger.info('');
      _logger.info('Run ${lightCyan.wrap('jetway login')} to renew your session.');
      _logger.info('');
      return 1;
    } catch (e) {
      progress.fail('Failed to fetch profile: $e');
      return 1;
    }

    _logger.info('');
    _logger.info(styleBold.wrap('Jetway Cloud Identity'));
    _logger.info('  ${styleBold.wrap('Name:')}        ${profile.displayName ?? profile.fullName ?? '—'}');
    _logger.info('  ${styleBold.wrap('Email:')}       ${lightCyan.wrap(profile.email)}');
    _logger.info('  ${styleBold.wrap('User ID:')}     ${profile.id}');
    _logger.info('  ${styleBold.wrap('Workspace:')}   ${profile.hasWorkspace ? green.wrap('Active') : darkGray.wrap('None')}');
    _logger.info('  ${styleBold.wrap('Endpoint:')}    ${_apiClient.baseUrl}');
    _logger.info('  ${styleBold.wrap('Storage:')}     ~/.jetway/credentials.json');
    _logger.info('');
    return 0;
  }
}

