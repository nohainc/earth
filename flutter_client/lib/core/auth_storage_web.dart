// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveToken(String token) async {
  try {
    html.window.localStorage['earth_auth_token'] = token;
  } catch (_) {}
}

Future<String?> getToken() async {
  try {
    return html.window.localStorage['earth_auth_token'];
  } catch (_) {
    return null;
  }
}

Future<void> clearToken() async {
  try {
    html.window.localStorage.remove('earth_auth_token');
  } catch (_) {}
}
