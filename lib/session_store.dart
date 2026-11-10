import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StoredSession {
  const StoredSession({required this.baseUrl, required this.token, required this.user});

  final String baseUrl;
  final String token;
  final AppUser user;
}

/// Recuerda el servidor y la sesión entre aperturas de la app.
class SessionStore {
  static const _serverKey = 'server_url';
  static const _tokenKey = 'token';
  static const _userKey = 'user';

  Future<String?> lastServer() async =>
      (await SharedPreferences.getInstance()).getString(_serverKey);

  Future<StoredSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString(_serverKey);
    final token = prefs.getString(_tokenKey);
    final user = prefs.getString(_userKey);

    if (server == null || token == null || user == null) return null;

    return StoredSession(
      baseUrl: server,
      token: token,
      user: AppUser.fromJson(jsonDecode(user) as Map<String, dynamic>),
    );
  }

  Future<void> save(StoredSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, session.baseUrl);
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
  }

  /// Sale de la cuenta, pero conserva la dirección del servidor.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
