// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveToken(String token) async {
  try {
    html.window.localStorage['earth_auth_token'] = token;
    html.window.sessionStorage['earth_auth_token'] = token;
  } catch (_) {}
}

Future<String?> getToken() async {
  try {
    final localTok = html.window.localStorage['earth_auth_token'];
    if (localTok != null && localTok.isNotEmpty) return localTok;
    final sessionTok = html.window.sessionStorage['earth_auth_token'];
    if (sessionTok != null && sessionTok.isNotEmpty) return sessionTok;
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> clearToken() async {
  try {
    html.window.localStorage.remove('earth_auth_token');
    html.window.sessionStorage.remove('earth_auth_token');
  } catch (_) {}
}
