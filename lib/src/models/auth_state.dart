class AuthState {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final String? userEmail;
  final String? userName;
  final DateTime savedAt;

  const AuthState({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'bearer',
    this.userEmail,
    this.userName,
    required this.savedAt,
  });

  factory AuthState.fromJson(Map<String, dynamic> json) {
    return AuthState(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: (json['token_type'] as String?) ?? 'bearer',
      userEmail: json['user_email'] as String?,
      userName: json['user_name'] as String?,
      savedAt: json['saved_at'] != null
          ? DateTime.parse(json['saved_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      'token_type': tokenType,
      if (userEmail != null) 'user_email': userEmail,
      if (userName != null) 'user_name': userName,
      'saved_at': savedAt.toIso8601String(),
    };
  }

  AuthState copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    String? userEmail,
    String? userName,
    DateTime? savedAt,
  }) {
    return AuthState(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  @override
  String toString() =>
      'AuthState(email: $userEmail, name: $userName, type: $tokenType, savedAt: $savedAt)';
}
