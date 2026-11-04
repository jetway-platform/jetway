import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../services/auth_storage.dart';
import '../services/jetway_api_client.dart';

class LogoutCommand extends Command<int> {
  @override
  final String name = 'logout';

  @override
  final String description = 'Log out of Jetway Cloud and remove stored credentials.';

  final Logger _logger;
  final JetwayApiClient _apiClient;
  final AuthStorage _authStorage;

  LogoutCommand(
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
      _logger.info('You are not currently logged in.');
      _logger.info('Jetway CLI is operating in standalone local mode.');
      _logger.info('');
      return 0;
    }

    final progress = _logger.progress('Revoking cloud session...');
    try {
      await _apiClient.logout(
        refreshToken: authState.refreshToken,
        accessToken: authState.accessToken,
      );
      progress.complete('Session revoked.');
    } catch (_) {
      progress.complete('Local credentials removed.');
    }

    await _authStorage.clear();

    _logger.info('');
    _logger.success('Logged out successfully.');
    _logger.info('  Removed credentials file: ~/.jetway/credentials.json');
    _logger.info('  Local-first build and deployment operations remain fully operational.');
    _logger.info('');
    return 0;
  }
}
