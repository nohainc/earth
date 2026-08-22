part of 'earth_api.dart';

extension EarthApiAuth on EarthApi {
  // --- Auth & Session ---

  Future<Map<String, dynamic>> session() async =>
      (await _request('/api/auth/me')) as Map<String, dynamic>;

  Future<EarthState> updateDisplayName(String displayName) async {
    await _request('/api/auth/profile', method: 'PATCH', body: {
      'displayName': displayName.trim(),
    });
    return world();
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String? otp}) async {
    final response = (await _request('/api/auth/login', method: 'POST', body: {
      'email': email,
      'password': password,
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    })) as Map<String, dynamic>;
    final token = response['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await AuthStorage.saveToken(token);
    }
    return response;
  }

  Future<Map<String, dynamic>> enrollMfa() async =>
      (await _request('/api/auth/mfa/enroll', method: 'POST'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> confirmMfa(String code) async =>
      (await _request('/api/auth/mfa/confirm',
          method: 'POST', body: {'code': code})) as Map<String, dynamic>;

  Future<void> disableMfa(String code) async {
    await _request('/api/auth/mfa/disable',
        method: 'POST', body: {'code': code});
  }

  Future<List<dynamic>> sessions() async {
    final response =
        (await _request('/api/auth/sessions')) as Map<String, dynamic>;
    return (response['sessions'] as List<dynamic>?) ?? const [];
  }

  Future<void> revokeSession(String sessionId) async {
    await _request('/api/auth/sessions/$sessionId', method: 'DELETE');
  }

  Future<void> revokeAllSessions() async {
    await _request('/api/auth/sessions', method: 'DELETE');
  }

  Future<Map<String, dynamic>> register(
          String email, String password, String displayName,
          {String passwordConfirmation = ''}) async =>
      (await _request('/api/auth/register', method: 'POST', body: {
        'email': email,
        'password': password,
        'passwordConfirmation': passwordConfirmation,
        'displayName': displayName,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> resendVerification(String email) async =>
      (await _request('/api/auth/verify-email/resend',
          method: 'POST', body: {'email': email})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> verifyEmail(String token) async =>
      (await _request(
              '/api/auth/verify-email?token=${Uri.encodeQueryComponent(token)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> requestPasswordReset(String email) async =>
      (await _request('/api/auth/password-reset/request',
          method: 'POST',
          body: {
            'email': email,
          })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> completePasswordReset(
          String token, String password) async =>
      (await _request('/api/auth/password-reset/complete',
          method: 'POST',
          body: {
            'token': token,
            'password': password,
          })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> rebirth(String displayName,
      {String? dynastyName, String? startingCityId}) async {
    final response = (await _request('/api/auth/rebirth',
        method: 'POST',
        body: {
          'displayName': displayName,
          if (dynastyName != null && dynastyName.isNotEmpty)
            'dynastyName': dynastyName,
          if (startingCityId != null && startingCityId.isNotEmpty)
            'startingCityId': startingCityId,
        })) as Map<String, dynamic>;
    final token = response['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await AuthStorage.saveToken(token);
    }
    return response;
  }

  Future<Map<String, dynamic>> claimHeir() async {
    final response = (await _request('/api/auth/claim-heir',
        method: 'POST', body: {})) as Map<String, dynamic>;
    final token = response['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await AuthStorage.saveToken(token);
    }
    return response;
  }

  Future<void> logout() async {
    try {
      await _request('/api/auth/logout', method: 'POST');
    } finally {
      await AuthStorage.clearToken();
    }
  }
}
