import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../models/auth_state.dart';
import '../services/auth_storage.dart';
import '../services/jetway_api_client.dart';

class LoginCommand extends Command<int> {
  @override
  final String name = 'login';

  @override
  final String description = 'Authenticate with Jetway Cloud using device code authorization.';

  final Logger _logger;
  final JetwayApiClient _apiClient;
  final AuthStorage _authStorage;

  LoginCommand(
    this._logger, {
    JetwayApiClient? apiClient,
    AuthStorage? authStorage,
  })  : _authStorage = authStorage ?? AuthStorage(),
        _apiClient = apiClient ?? JetwayApiClient(authStorage: authStorage) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Force re-authentication even if already logged in.',
    );
  }

  @override
  Future<int> run() async {
    final force = argResults?['force'] as bool? ?? false;

    // Check existing login status
    final existingAuth = await _authStorage.read();
    if (existingAuth != null && !force) {
      try {
        final profile = await _apiClient.getProfile(token: existingAuth.accessToken);
        _logger.info('');
        _logger.info('Already authenticated as ${lightCyan.wrap(profile.email)}.');
        final reauth = _logger.confirm('Do you want to re-authenticate?', defaultValue: false);
        if (!reauth) {
          _logger.info('Staying logged in. Standalone and cloud operations available.');
          return 0;
        }
      } catch (_) {
        // If profile fetch fails, credentials might be stale -> proceed with login
      }
    }

    _logger.info('');
    _logger.info(styleBold.wrap('Jetway Cloud Device Authorization'));

    final fetchProgress = _logger.progress('Requesting authorization code...');
    DeviceCodeResponse deviceCodeRes;
    try {
      deviceCodeRes = await _apiClient.requestDeviceCode();
      fetchProgress.complete('Authorization code issued.');
    } catch (e) {
      fetchProgress.fail('Failed to request device authorization: $e');
      return 1;
    }

    _printAuthCodeBox(deviceCodeRes);

    // Attempt to open the system browser automatically
    _logger.info('Opening browser for authorization...');
    final browserOpened = await _openBrowser(deviceCodeRes.verificationUriComplete);
    if (!browserOpened) {
      _logger.info('Please open the URL above manually in your browser.');
    }

    // Polling loop
    final pollProgress = _logger.progress('Waiting for authorization in browser...');
    var intervalSeconds = deviceCodeRes.interval;
    final expiresAt = DateTime.now().add(Duration(seconds: deviceCodeRes.expiresIn));

    while (DateTime.now().isBefore(expiresAt)) {
      await Future<void>.delayed(Duration(seconds: intervalSeconds));

      try {
        final pollResult = await _apiClient.pollDeviceToken(deviceCodeRes.deviceCode);

        switch (pollResult.status) {
          case DeviceTokenStatus.authorized:
            final accessToken = pollResult.accessToken;
            if (accessToken == null || accessToken.isEmpty) {
              pollProgress.fail('Server granted authorization but returned empty token.');
              return 1;
            }

            var authState = AuthState(
              accessToken: accessToken,
              refreshToken: pollResult.refreshToken,
              tokenType: pollResult.tokenType ?? 'bearer',
              savedAt: DateTime.now(),
            );

            // Fetch and save user profile context
            try {
              final profile = await _apiClient.getProfile(token: accessToken);
              authState = authState.copyWith(
                userEmail: profile.email,
                userName: profile.displayName ?? profile.fullName,
              );
            } catch (_) {
              // Proceed even if profile metadata fetch fails
            }

            await _authStorage.write(authState);
            pollProgress.complete('Device authorization granted!');

            _logger.info('');
            _logger.success('Successfully logged into Jetway Cloud.');
            if (authState.userEmail != null) {
              _logger.info('  ${styleBold.wrap('Developer:')} ${authState.userName ?? '—'} (${authState.userEmail})');
            }
            _logger.info('  ${styleBold.wrap('Credentials:')} ~/.jetway/credentials.json (chmod 600)');
            _logger.info('');
            return 0;

          case DeviceTokenStatus.pending:
            // Keep polling
            break;

          case DeviceTokenStatus.slowDown:
            intervalSeconds += 5;
            break;

          case DeviceTokenStatus.denied:
            pollProgress.fail('Authorization denied by user.');
            return 1;

          case DeviceTokenStatus.expired:
            pollProgress.fail('Authorization code expired. Please run `jetway login` again.');
            return 1;

          case DeviceTokenStatus.unknown:
            pollProgress.fail('Unexpected authorization status: ${pollResult.error}');
            return 1;
        }
      } catch (e) {
        pollProgress.fail('Polling error: $e');
        return 1;
      }
    }

    pollProgress.fail('Authorization timed out after ${deviceCodeRes.expiresIn}s. Please run `jetway login` again.');
    return 1;
  }

  void _printAuthCodeBox(DeviceCodeResponse response) {
    _logger.info('');
    _logger.info(lightGray.wrap('┌────────────────────────────────────────────────────────────┐'));
    _logger.info('${lightGray.wrap('│')}  JETWAY DEVICE AUTHORIZATION CODE');
    _logger.info('${lightGray.wrap('│')}');
    _logger.info('${lightGray.wrap('│')}  Code: ${styleBold.wrap(lightCyan.wrap(response.userCode))}');
    _logger.info('${lightGray.wrap('│')}');
    _logger.info('${lightGray.wrap('│')}  Complete authorization in browser at:');
    _logger.info('${lightGray.wrap('│')}  ${response.verificationUriComplete}');
    _logger.info(lightGray.wrap('└────────────────────────────────────────────────────────────┘'));
    _logger.info('');
  }

  Future<bool> _openBrowser(String url) async {
    try {
      if (Platform.isMacOS) {
        final res = await Process.run('open', [url]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [url]);
        return res.exitCode == 0;
      } else if (Platform.isWindows) {
        final res = await Process.run('cmd', ['/c', 'start', '', url]);
        return res.exitCode == 0;
      }
    } catch (_) {
      // Browser launch failed or running in headless terminal
    }
    return false;
  }
}
