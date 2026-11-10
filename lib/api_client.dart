import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Error con un mensaje listo para mostrar.
class ApiException implements Exception {
  const ApiException(this.message, {this.isUnauthorized = false});

  final String message;
  final bool isUnauthorized;

  @override
  String toString() => message;
}

class RealtimeConfig {
  const RealtimeConfig({
    required this.key,
    required this.port,
    required this.scheme,
  });

  final String key;
  final int port;
  final String scheme;
}

class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final AppUser user;
}

class ApiClient {
  ApiClient({required String baseUrl, this.token, http.Client? client})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? token;

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api/mobile$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response response;

    try {
      response = await request().timeout(_timeout);
    } catch (_) {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa la dirección y tu conexión.',
      );
    }

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Respuesta sin JSON: se usa el mensaje genérico de abajo.
    }

    if (response.statusCode == 401) {
      throw const ApiException('Tu sesión venció. Vuelve a entrar.', isUnauthorized: true);
    }

    if (response.statusCode == 403) {
      throw const ApiException('No tienes acceso a este diagrama.');
    }

    if (response.statusCode >= 400) {
      throw ApiException(body['message'] as String? ?? 'El servidor no pudo atender el pedido.');
    }

    return body;
  }

  Future<LoginResult> login(String email, String password, String deviceName) async {
    final body = await _send(
      () => _client.post(
        _uri('/login'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password, 'device_name': deviceName}),
      ),
    );

    return LoginResult(
      token: body['token'] as String,
      user: AppUser.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  Future<void> logout() async {
    await _send(() => _client.post(_uri('/logout'), headers: _headers));
  }

  Future<List<DiagramSummary>> diagrams() async {
    final body = await _send(() => _client.get(_uri('/diagrams'), headers: _headers));

    return (body['diagrams'] as List)
        .map((e) => DiagramSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DiagramDetail> diagram(String id) async {
    final body = await _send(() => _client.get(_uri('/diagrams/$id'), headers: _headers));

    return DiagramDetail.fromJson(body);
  }

  Future<List<ActivityItem>> activity(String id, {DateTime? before}) async {
    final query = before == null ? null : {'before': before.toUtc().toIso8601String()};
    final body = await _send(() => _client.get(_uri('/diagrams/$id/activity', query), headers: _headers));

    return (body['entries'] as List)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> messages(String id) async {
    final body = await _send(() => _client.get(_uri('/diagrams/$id/messages'), headers: _headers));

    return (body['messages'] as List)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> ask(String id, String text) async {
    final body = await _send(
      () => _client.post(_uri('/diagrams/$id/ask'), headers: _headers, body: jsonEncode({'text': text})),
    );

    return ChatMessage.fromJson(body['message'] as Map<String, dynamic>);
  }

  /// ¿Responde el servidor en esta dirección? (ruta pública `/ping`).
  Future<bool> ping() async {
    try {
      final response = await _client.get(Uri.parse('$baseUrl/ping')).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dirección temporal (1 minuto) que abre el lienzo web embebido con la
  /// sesión de este usuario. La vista es la misma "Ver" de la web.
  Future<Uri> viewerUrl(String id) async {
    final body = await _send(() => _client.post(_uri('/diagrams/$id/viewer-link'), headers: _headers));

    return Uri.parse('$baseUrl${body['path']}');
  }

  Future<void> registerDevice(String deviceToken) async {
    await _send(
      () => _client.post(_uri('/devices'), headers: _headers, body: jsonEncode({'token': deviceToken, 'platform': 'android'})),
    );
  }

  Future<void> unregisterDevice(String deviceToken) async {
    await _send(
      () => _client.delete(_uri('/devices'), headers: _headers, body: jsonEncode({'token': deviceToken})),
    );
  }

  /// Bandeja de avisos: los últimos 50 y cuántos faltan leer.
  Future<NoticeInbox> notifications() async {
    final body = await _send(() => _client.get(_uri('/notifications'), headers: _headers));

    return NoticeInbox(
      notices: (body['notifications'] as List)
          .map((e) => AppNotice.fromJson(e as Map<String, dynamic>))
          .toList(),
      unread: body['unread'] as int? ?? 0,
    );
  }

  /// Marca como leído uno ([id]), los de un diagrama ([diagramId]) o todos. Devuelve los no leídos.
  Future<int> markNotificationsRead({String? id, String? diagramId}) async {
    final body = await _send(
      () => _client.post(
        _uri('/notifications/read'),
        headers: _headers,
        body: jsonEncode({if (id != null) 'id': id, if (diagramId != null) 'diagramId': diagramId}),
      ),
    );

    return body['unread'] as int? ?? 0;
  }

  Future<RealtimeConfig> realtimeConfig() async {
    final body = await _send(() => _client.get(_uri('/realtime'), headers: _headers));

    return RealtimeConfig(
      key: body['key'] as String,
      port: body['port'] as int,
      scheme: body['scheme'] as String? ?? 'http',
    );
  }

  /// Firma la suscripción a un canal privado de tiempo real.
  Future<String> authorizeChannel(String socketId, String channel) async {
    final body = await _send(
      () => _client.post(
        _uri('/broadcasting/auth'),
        headers: _headers,
        body: jsonEncode({'socket_id': socketId, 'channel_name': channel}),
      ),
    );

    return body['auth'] as String;
  }
}
