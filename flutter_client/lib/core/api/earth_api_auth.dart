part of 'earth_api.dart';

extension EarthApiAuth on EarthApi {
  // --- Auth & Session ---

  Future<Map<String, dynamic>> session() async =>
      (await _request('/api/auth/me')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> login(String email, String password,
          {String? otp}) async =>
      (await _request('/api/auth/login', method: 'POST', body: {
        'email': email,
        'password': password,
        if (otp != null && otp.isNotEmpty) 'otp': otp,
      })) as Map<String, dynamic>;

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

  Future<void> logout() async {
    await _request('/api/auth/logout', method: 'POST');
  }
}
