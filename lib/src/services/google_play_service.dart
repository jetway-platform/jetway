import 'dart:io';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:mason_logger/mason_logger.dart';
import '../models/config.dart';

/// Uploads AAB/APK artifacts to Google Play using the Android Publisher API.
/// Requires a Google Play service account JSON with the correct permissions.
/// Docs: https://developers.google.com/android-publisher
class GooglePlayService {
  final Logger _logger;
  final AndroidConfig _androidConfig;
  final String _packageName;

  GooglePlayService(this._logger, this._androidConfig, this._packageName);

  /// Uploads an AAB or APK to Google Play and promotes it to the configured track.
  Future<void> uploadArtifact({
    required String artifactPath,
    String? releaseNotes,
    bool verbose = false,
  }) async {
    _logger.info('  Authenticating with Google Play...');

    final client = await _buildAuthClient();
    final publisherApi = AndroidPublisherApi(client);

    try {
      // 1. Create a new edit (all Play API changes happen in an edit session)
      _logger.info('  Creating Play Store edit...');
      final edit = await publisherApi.edits.insert(AppEdit(), _packageName);
      final editId = edit.id!;
      _logger.detail('  Edit ID: $editId');

      // 2. Upload the artifact
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

      _logger.success('  ✓ Artifact uploaded (version code: $versionCode)');

      // 3. Assign the build to the configured track
      _logger.info('  Assigning build to track: ${_androidConfig.track}...');
      await _assignToTrack(
        publisherApi,
        editId: editId,
        versionCode: int.parse(versionCode ?? '0'),
        releaseNotes: releaseNotes,
      );

      // 4. Commit the edit (makes the upload live in Play Console)
      _logger.info('  Committing Play Store edit...');
      await publisherApi.edits.commit(_packageName, editId);

      _logger.success('  ✓ Build live on Play Store (${_androidConfig.track} track)');
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

  /// Verifies the service account can authenticate with Google Play.
  /// Throws [GooglePlayException] if auth fails.
  Future<void> verifyCredentials() async {
    try {
      final client = await _buildAuthClient();
      client.close();
    } catch (e) {
      throw GooglePlayException(
        'Failed to authenticate with Google Play: $e\n'
        'Check your service account JSON file path and permissions.',
      );
    }
  }

  /// Returns all package names accessible to this service account.
  /// Note: the Play Developer API does not have a "list all apps" endpoint,
  /// so this attempts a lightweight call for the configured package name.
  /// Returns the package name if accessible, empty list otherwise.
  Future<List<String>> fetchAccessiblePackages(List<String> candidatePackages) async {
    final client = await _buildAuthClient();
    final publisherApi = AndroidPublisherApi(client);
    final accessible = <String>[];

    try {
      for (final pkg in candidatePackages) {
        try {
          // A lightweight call to check access: list tracks
          await publisherApi.edits.insert(AppEdit(), pkg);
          accessible.add(pkg);
        } catch (_) {
          // Not accessible — skip
        }
      }
    } finally {
      client.close();
    }

    return accessible;
  }

  Future<AuthClient> _buildAuthClient() async {

    final serviceAccountPath = _androidConfig.resolvedServiceAccountPath;

    if (!File(serviceAccountPath).existsSync()) {
      throw GooglePlayException(
        'Google Play service account file not found: $serviceAccountPath\n'
        'Create one in Google Play Console → Setup → API access',
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

  /// Maps track name to the appropriate release status.
  String _releaseStatus(String track) {
    switch (track) {
      case 'internal':
      case 'alpha':
        return 'completed'; // Internal/alpha are immediately available
      case 'beta':
        return 'completed';
      case 'production':
        return 'completed'; // Could be 'draft' for staged rollouts
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
