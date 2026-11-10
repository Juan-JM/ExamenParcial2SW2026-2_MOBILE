import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Evento de tiempo real de un diagrama.
class RealtimeEvent {
  const RealtimeEvent({required this.diagramId, required this.name, required this.data});

  final String diagramId;
  final String name;
  final Map<String, dynamic> data;
}

/// Convierte una trama del protocolo de Reverb (el de Pusher) en un evento. Los
/// demás tipos de trama, como las de control, devuelven null.
RealtimeEvent? parseChannelEvent(Map<String, dynamic> frame) {
  final channel = frame['channel'];
  final event = frame['event'];

  if (channel is! String || event is! String || event.startsWith('pusher')) return null;
  if (!channel.startsWith(RealtimeHub.channelPrefix)) return null;

  final raw = frame['data'];
  final Object? data = raw is String ? jsonDecode(raw) : raw;

  return RealtimeEvent(
    diagramId: channel.substring(RealtimeHub.channelPrefix.length),
    name: event,
    data: data is Map<String, dynamic> ? data : const {},
  );
}

/// Conexión con Reverb: suscribe los diagramas y se reconecta sola si se corta,
/// algo habitual en un celular en movimiento.
class RealtimeHub {
  RealtimeHub(this._api);

  static const channelPrefix = 'private-diagram-agent.';
  static const _maxBackoffSeconds = 30;

  final ApiClient _api;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final Set<String> _diagramIds = {};

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String? _socketId;
  int _attempts = 0;
  bool _closed = false;

  Stream<RealtimeEvent> get events => _events.stream;

  /// Cambios de conexión, para avisar cuando el contenido puede no estar al día.
  Stream<bool> get connection => _connection.stream;

  Future<void> watch(Iterable<String> diagramIds) async {
    final added = diagramIds.where(_diagramIds.add).toList();

    if (_socket == null) {
      await _connect();
    } else if (_socketId != null) {
      added.forEach(_subscribeTo);
    }
  }

  Future<void> _connect() async {
    if (_closed) return;

    try {
      final config = await _api.realtimeConfig();
      final base = Uri.parse(_api.baseUrl);
      final uri = Uri(
        scheme: config.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: config.port,
        path: '/app/${config.key}',
        queryParameters: const {'protocol': '7', 'client': 'flutter', 'version': '1.0'},
      );

      final socket = WebSocketChannel.connect(uri);
      await socket.ready;
      _socket = socket;
      _subscription = socket.stream.listen(
        _onFrame,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic message) {
    final frame = jsonDecode(message as String) as Map<String, dynamic>;

    switch (frame['event']) {
      case 'pusher:connection_established':
        final data = jsonDecode(frame['data'] as String) as Map<String, dynamic>;
        _socketId = data['socket_id'] as String;
        _attempts = 0;
        _connection.add(true);
        _diagramIds.forEach(_subscribeTo);
      case 'pusher:ping':
        _socket?.sink.add(jsonEncode({'event': 'pusher:pong', 'data': {}}));
      default:
        final event = parseChannelEvent(frame);
        if (event != null) _events.add(event);
    }
  }

  Future<void> _subscribeTo(String diagramId) async {
    final socketId = _socketId;
    if (socketId == null) return;

    final channel = '$channelPrefix$diagramId';

    try {
      final auth = await _api.authorizeChannel(socketId, channel);
      _socket?.sink.add(jsonEncode({
        'event': 'pusher:subscribe',
        'data': {'auth': auth, 'channel': channel},
      }));
    } on ApiException {
      // Sin acceso a ese diagrama: los demás siguen funcionando.
    }
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _socketId = null;

    if (_closed) return;

    _connection.add(false);
    _attempts++;

    final seconds = (1 << _attempts.clamp(0, 5)).clamp(1, _maxBackoffSeconds);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: seconds), _connect);
  }

  Future<void> close() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _socket?.sink.close();
    await _events.close();
    await _connection.close();
  }
}
