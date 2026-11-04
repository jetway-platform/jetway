import 'dart:io';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:mason_logger/mason_logger.dart';

import '../models/config.dart';

class GooglePlayService {
  final Logger _logger;
  final AndroidConfig _androidConfig;
  final String _packageName;

  GooglePlayService(this._logger, this._androidConfig, this._packageName);

  Future<void> uploadArtifact({
    required String artifactPath,
    String? releaseNotes,
    bool verbose = false,
  }) async {
    _logger.info('  Authenticating with Google Play...');

    final client = await _buildAuthClient();
    final publisherApi = AndroidPublisherApi(client);

    try {
      _logger.info('  Creating Play Store edit...');
      final edit = await publisherApi.edits.insert(AppEdit(), _packageName);
      final editId = edit.id!;

      final isAab = artifactPath.endsWith('.aab');
      _logger.info('  Uploading ${isAab ? 'AAB' : 'APK'} to Google Play...');

      String? versionCode;
      if (isAab) {
        final bundle = await _uploadAab(publisherApi, editId, artifactPath);
        versionCode = bundle.versionCode?.toString();
      } else {
        final apk = await _uploadApk(publisherApi, editId, artifactPath);
        versionCode = apk.versionCode?.toString();
      }

      _logger.success('  Artifact uploaded (version code: $versionCode)');

      _logger.info('  Assigning build to track: ${_androidConfig.track}...');
      await _assignToTrack(
        publisherApi,
        editId: editId,
        versionCode: int.parse(versionCode ?? '0'),
        releaseNotes: releaseNotes,
      );

      _logger.info('  Committing Play Store edit...');
      await publisherApi.edits.commit(_packageName, editId);

      _logger.success('  Build live on Google Play (${_androidConfig.track} track)');
    } finally {
      client.close();
    }
  }

  Future<Bundle> _uploadAab(
    AndroidPublisherApi api,
    String editId,
    String artifactPath,
  ) async {
    final file = File(artifactPath);
    final media = Media(file.openRead(), file.lengthSync());

    return api.edits.bundles.upload(
      _packageName,
      editId,
      uploadMedia: media,
    );
  }

  Future<Apk> _uploadApk(
    AndroidPublisherApi api,
    String editId,
    String artifactPath,
  ) async {
    final file = File(artifactPath);
    final media = Media(file.openRead(), file.lengthSync());

    return api.edits.apks.upload(
      _packageName,
      editId,
      uploadMedia: media,
    );
  }

  Future<void> _assignToTrack(
    AndroidPublisherApi api, {
    required String editId,
    required int versionCode,
    String? releaseNotes,
  }) async {
    final track = Track(
      track: _androidConfig.track,
      releases: [
        TrackRelease(
          status: _releaseStatus(_androidConfig.track),
          versionCodes: ['$versionCode'],
          releaseNotes: releaseNotes != null
              ? [
                  LocalizedText(
                    language: 'en-US',
                    text: releaseNotes,
                  ),
                ]
              : null,
        ),
      ],
    );

    await api.edits.tracks.update(
      track,
      _packageName,
      editId,
      _androidConfig.track,
    );
  }

  Future<void> verifyCredentials() async {
    try {
      final client = await _buildAuthClient();
      client.close();
    } catch (e) {
      throw GooglePlayException(
        'Failed to authenticate with Google Play: $e\n'
        'Check service account JSON file path and permissions in Google Play Console.',
      );
    }
  }

  Future<AuthClient> _buildAuthClient() async {
    final serviceAccountPath = _androidConfig.resolvedServiceAccountPath;

    if (!File(serviceAccountPath).existsSync()) {
      throw GooglePlayException(
        'Google Play service account file not found: $serviceAccountPath\n'
        'Configure service account in Google Play Console -> Setup -> API access',
      );
    }

    final credentials = ServiceAccountCredentials.fromJson(
      File(serviceAccountPath).readAsStringSync(),
    );

    return clientViaServiceAccount(
      credentials,
      [AndroidPublisherApi.androidpublisherScope],
    );
  }

  String _releaseStatus(String track) {
    switch (track) {
      case 'internal':
      case 'alpha':
      case 'beta':
      case 'production':
      default:
        return 'completed';
    }
  }
}

class GooglePlayException implements Exception {
  final String message;
  GooglePlayException(this.message);

  @override
  String toString() => message;
}
