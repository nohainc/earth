import 'auth_storage_stub.dart'
    if (dart.library.html) 'auth_storage_web.dart' as platform;

class AuthStorage {
  static Future<void> saveToken(String token) async {
    await platform.saveToken(token);
  }

  static Future<String?> getToken() async {
    return platform.getToken();
  }

  static Future<void> clearToken() async {
    await platform.clearToken();
  }
}
