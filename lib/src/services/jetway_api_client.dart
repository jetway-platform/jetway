import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_storage.dart';

class JetwayApiException implements Exception {
  final String message;
  final int? statusCode;

  const JetwayApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? 'JetwayApiException($statusCode): $message' : 'JetwayApiException: $message';
}

class JetwayAuthException implements Exception {
  final String message;

  const JetwayAuthException(this.message);

  @override
  String toString() => 'JetwayAuthException: $message';
}

class DeviceCodeResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int expiresIn;
  final int interval;

  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> json) {
    final payload = (json['data'] as Map<String, dynamic>?) ?? json;
    return DeviceCodeResponse(
      deviceCode: payload['device_code'] as String,
      userCode: payload['user_code'] as String,
      verificationUri: payload['verification_uri'] as String,
      verificationUriComplete: payload['verification_uri_complete'] as String,
      expiresIn: (payload['expires_in'] as num?)?.toInt() ?? 900,
      interval: (payload['interval'] as num?)?.toInt() ?? 3,
    );
  }
}

enum DeviceTokenStatus {
  authorized,
  pending,
  slowDown,
  denied,
  expired,
  unknown,
}

class DeviceTokenPollResult {
  final DeviceTokenStatus status;
  final String? accessToken;
  final String? refreshToken;
  final String? tokenType;
  final String? error;
  final String? message;

  const DeviceTokenPollResult({
    required this.status,
    this.accessToken,
    this.refreshToken,
    this.tokenType,
    this.error,
    this.message,
  });
}

class UserProfile {
  final int id;
  final String email;
  final String? fullName;
  final String? displayName;
  final String? avatarUrl;
  final bool hasWorkspace;

  const UserProfile({
    required this.id,
    required this.email,
    this.fullName,
    this.displayName,
    this.avatarUrl,
    required this.hasWorkspace,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final root = (json['data'] as Map<String, dynamic>?) ?? json;
    final userRaw = (root['user'] as Map<String, dynamic>?) ?? root;

    return UserProfile(
      id: (userRaw['id'] as num).toInt(),
      email: userRaw['email'] as String,
      fullName: userRaw['full_name'] as String?,
      displayName: (userRaw['display_name'] as String?) ??
          (userRaw['displayName'] as String?) ??
          userRaw['full_name'] as String?,
      avatarUrl: (userRaw['avatar_url'] as String?) ??
          (userRaw['avatarUrl'] as String?),
      hasWorkspace: (root['has_workspace'] as bool?) ??
          (root['hasWorkspace'] as bool?) ??
          false,
    );
  }
}

class JetwayApiClient {
  final String baseUrl;
  final AuthStorage authStorage;
  final http.Client _httpClient;
  final Duration timeout;

  JetwayApiClient({
    String? baseUrl,
    AuthStorage? authStorage,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : baseUrl = _normalizeBaseUrl(baseUrl ??
            Platform.environment['JETWAY_API_URL'] ??
            'https://api.jetway.dev'),
        authStorage = authStorage ?? AuthStorage(),
        _httpClient = httpClient ?? http.Client();

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Uri _resolveUri(String path) {
    // If baseUrl doesn't end with /v1 and path starts with /v1, keep path as is.
    // If baseUrl already ends with /v1 and path starts with /v1, strip leading /v1.
    var cleanPath = path;
    if (baseUrl.endsWith('/v1') && cleanPath.startsWith('/v1')) {
      cleanPath = cleanPath.substring(3);
    }
    return Uri.parse('$baseUrl$cleanPath');
  }

  Future<DeviceCodeResponse> requestDeviceCode({String? clientInfo}) async {
    final uri = _resolveUri('/v1/auth/device/code');
    final response = await _postJson(
      uri,
      body: {'client_info': clientInfo ?? 'jetway-cli/0.2.5'},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return DeviceCodeResponse.fromJson(json);
    }

    throw _parseError(response);
  }

  Future<DeviceTokenPollResult> pollDeviceToken(String deviceCode) async {
    final uri = _resolveUri('/v1/auth/device/token');
    final response = await _postJson(
      uri,
      body: {'device_code': deviceCode},
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final payload = (json['data'] as Map<String, dynamic>?) ?? json;

      return DeviceTokenPollResult(
        status: DeviceTokenStatus.authorized,
        accessToken: payload['access_token'] as String?,
        refreshToken: payload['refresh_token'] as String?,
        tokenType: payload['token_type'] as String? ?? 'bearer',
      );
    }

    if (response.statusCode == 400) {
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final errorObj = (json['error'] as Map<String, dynamic>?) ?? json;
        final error = (errorObj['error'] as String?) ?? (json['detail'] as String?);
        final message = (errorObj['message'] as String?) ?? (json['message'] as String?);

        switch (error) {
          case 'authorization_pending':
            return DeviceTokenPollResult(
              status: DeviceTokenStatus.pending,
              error: error,
              message: message,
            );
          case 'slow_down':
            return DeviceTokenPollResult(
              status: DeviceTokenStatus.slowDown,
              error: error,
              message: message,
            );
          case 'access_denied':
            return DeviceTokenPollResult(
              status: DeviceTokenStatus.denied,
              error: error,
              message: message,
            );
          case 'expired_token':
            return DeviceTokenPollResult(
              status: DeviceTokenStatus.expired,
              error: error,
              message: message,
            );
          default:
            return DeviceTokenPollResult(
              status: DeviceTokenStatus.unknown,
              error: error,
              message: message,
            );
        }
      } catch (_) {
        throw JetwayApiException(
          'Failed to parse device token polling response',
          statusCode: response.statusCode,
        );
      }
    }

    throw _parseError(response);
  }

  Future<UserProfile> getProfile({String? token}) async {
    final accessToken = token ?? await authStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const JetwayAuthException('No credentials found. Please run `jetway login`.');
    }

    final uri = _resolveUri('/v1/auth/profile');
    final response = await _getJson(uri, token: accessToken);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UserProfile.fromJson(json);
    }

    if (response.statusCode == 401) {
      throw const JetwayAuthException('Session expired or invalid. Please re-authenticate via `jetway login`.');
    }

    throw _parseError(response);
  }

  Future<void> logout({String? refreshToken, String? accessToken}) async {
    final token = accessToken ?? await authStorage.getAccessToken();
    final state = await authStorage.read();
    final refToken = refreshToken ?? state?.refreshToken;

    if (refToken != null && refToken.isNotEmpty) {
      try {
        final uri = _resolveUri('/v1/auth/logout');
        await _postJson(
          uri,
          token: token,
          body: {'refresh_token': refToken},
        );
      } catch (_) {
        // Silently proceed with local credential deletion even if offline
      }
    }

    await authStorage.clear();
  }

  Future<http.Response> _getJson(Uri uri, {String? token}) async {
    final headers = {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      return await _httpClient.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw const JetwayApiException('Request timed out. Please check your internet connection.');
    } on SocketException {
      throw const JetwayApiException('Unable to connect to Jetway API. Please check your network.');
    }
  }

  Future<http.Response> _postJson(
    Uri uri, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      return await _httpClient
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const JetwayApiException('Request timed out. Please check your internet connection.');
    } on SocketException {
      throw const JetwayApiException('Unable to connect to Jetway API. Please check your network.');
    }
  }

  JetwayApiException _parseError(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorObj = json['error'] as Map<String, dynamic>?;
      final message = (errorObj?['message'] as String?) ??
          (json['message'] as String?) ??
          (json['detail'] as String?) ??
          'Request failed';
      return JetwayApiException(message, statusCode: response.statusCode);
    } catch (_) {
      return JetwayApiException(
        'Server returned status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}
