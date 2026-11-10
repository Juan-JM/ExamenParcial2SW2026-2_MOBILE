import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uml_visor/api_client.dart';
import 'package:uml_visor/models.dart';
import 'package:uml_visor/realtime.dart';
import 'package:uml_visor/screens/diagram_screen.dart';
import 'package:uml_visor/screens/diagrams_screen.dart';
import 'package:uml_visor/screens/format.dart';
import 'package:uml_visor/screens/login_screen.dart';
import 'package:uml_visor/screens/notifications_screen.dart';

const _user = AppUser(id: 'u1', name: 'Ana', email: 'ana@test.dev');

Map<String, dynamic> _diagramJson() => {
  'id': 'd1',
  'title': 'Ventas',
  'version': 3,
  'lastSavedAt': '2026-11-07T10:00:00Z',
  'present': ['Juan'],
  'agentName': 'Nova',
  'classes': [
    {'id': 'a', 'name': 'Cliente', 'kind': 'class', 'attributes': ['+ id: int'], 'methods': [], 'x': 0, 'y': 0, 'width': 180, 'height': 90},
    {'id': 'b', 'name': 'Pedido', 'kind': 'class', 'attributes': [], 'methods': [], 'x': 300, 'y': 0, 'width': 180, 'height': 90},
  ],
  'relations': [
    {'id': 'r', 'source': 'a', 'target': 'b', 'type': 'composition', 'name': 'tiene', 'sourceMultiplicity': '1', 'targetMultiplicity': '*'},
  ],
};

ApiClient _apiWith(Map<String, Object> routes, {List<http.Request>? log}) {
  return ApiClient(
    baseUrl: 'http://server.test/',
    token: 'tok',
    client: MockClient((request) async {
      log?.add(request);
      final body = routes[request.url.path];
      if (body == null) return http.Response('{"message":"no route"}', 404);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  group('datos', () {
    test('tolera campos ausentes', () {
      final c = UmlClass.fromJson({'id': 1});
      expect(c.id, '1');
      expect(c.name, 'SinNombre');
      expect(c.width, 180);
      expect(c.attributes, isEmpty);
    });

    test('el origen de un cambio se expresa en palabras', () {
      ActivityItem origin(String value) => ActivityItem.fromJson({'id': 'x', 'origin': value, 'requestedByName': 'Ana'});
      expect(origin('manual').originLabel, 'a mano');
      expect(origin('agent').originLabel, 'a pedido de Ana');
      expect(origin('import').originLabel, 'por importación');
      expect(origin('system').originLabel, isNull);
    });

    test('el mensaje de la IA incluye lo que dibujó', () {
      final m = ChatMessage.fromJson({'id': 'm', 'text': 'Va.', 'opsSummary': 'Creé Pago.'});
      expect(m.displayText, 'Va.\nCreé Pago.');
    });

    test('fechas relativas', () {
      final now = DateTime(2026, 11, 7, 12, 0);
      expect(formatRelative(now, now: now), 'ahora');
      expect(formatRelative(DateTime(2026, 11, 7, 11, 55), now: now), 'hace 5 min');
      expect(formatRelative(DateTime(2026, 11, 7, 8, 5), now: now), 'hoy 08:05');
      expect(formatRelative(DateTime(2026, 11, 6, 23, 30), now: now), 'ayer 23:30');
      expect(formatRelative(DateTime(2026, 10, 1, 9, 0), now: now), '01/10 09:00');
    });
  });

  group('tiempo real', () {
    test('interpreta un evento de canal', () {
      final event = parseChannelEvent({
        'event': 'ActivityRecorded',
        'channel': 'private-diagram-agent.abc',
        'data': jsonEncode({'entries': []}),
      });
      expect(event?.diagramId, 'abc');
      expect(event?.name, 'ActivityRecorded');
      expect(event?.data['entries'], isEmpty);
    });

    test('ignora tramas de control y canales ajenos', () {
      expect(parseChannelEvent({'event': 'pusher_internal:subscription_succeeded', 'channel': 'private-diagram-agent.a', 'data': '{}'}), isNull);
      expect(parseChannelEvent({'event': 'X', 'channel': 'otro.canal', 'data': '{}'}), isNull);
      expect(parseChannelEvent({'event': 'pusher:pong'}), isNull);
    });
  });

  group('cliente de la API', () {
    test('envía el token y normaliza la dirección', () async {
      final log = <http.Request>[];
      final api = _apiWith({'/api/mobile/diagrams': {'diagrams': []}}, log: log);

      await api.diagrams();

      expect(log.single.url.toString(), 'http://server.test/api/mobile/diagrams');
      expect(log.single.headers['Authorization'], 'Bearer tok');
    });

    test('un 401 se distingue para volver al login', () async {
      final api = ApiClient(baseUrl: 'http://s', client: MockClient((_) async => http.Response('{}', 401)));
      await expectLater(api.diagrams(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)));
    });

    test('sin red da un mensaje comprensible', () async {
      final api = ApiClient(baseUrl: 'http://s', client: MockClient((_) async => throw Exception('red')));
      await expectLater(api.diagrams(), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('No se pudo conectar'))));
    });

    test('el error del servidor llega al usuario', () async {
      final api = ApiClient(baseUrl: 'http://s', client: MockClient((_) async => http.Response('{"message":"Correo incorrecto"}', 422)));
      await expectLater(api.login('a@b.c', 'x', 'tel'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Correo incorrecto')));
    });
  });

  group('pantallas', () {
    testWidgets('el login valida antes de enviar y muestra el error', (tester) async {
      String? usedUrl;
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          initialServer: 'http://server.test',
          clientFor: (url) {
            usedUrl = url;
            return ApiClient(
              baseUrl: url,
              client: MockClient((_) async => http.Response('{"message":"Correo o contraseña incorrectos."}', 422)),
            );
          },
          onLoggedIn: (_, _, _) => fail('no debía entrar'),
        ),
      ));

      // La dirección del servidor no está en el formulario: va en Ajustes.
      expect(find.textContaining('server.test'), findsNothing);

      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(find.text('Escribe tu correo'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'ana@test.dev');
      await tester.enterText(find.byType(TextFormField).at(1), 'mala');
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
      expect(usedUrl, 'http://server.test');
    });

    testWidgets('los ajustes validan y prueban la dirección del servidor', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ServerSettingsSheet(
              initial: 'http://server.test',
              clientFor: (url) => ApiClient(
                baseUrl: url,
                client: MockClient((r) async => http.Response(r.url.path == '/ping' ? '{"ok":true}' : '{}', 200)),
              ),
            ),
          ),
        ),
        onGenerateRoute: (_) => null,
      ));

      await tester.tap(find.text('Probar'));
      await tester.pumpAndSettle();
      expect(find.text('Conectado'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'no es una url');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(find.textContaining('dirección completa'), findsOneWidget);
    });

    testWidgets('la lista muestra los diagramas y cuáles están en vivo', (tester) async {
      final api = _apiWith({
        '/api/mobile/diagrams': {
          'diagrams': [
            {'id': 'd1', 'title': 'Ventas', 'isOwner': true, 'classesCount': 4, 'relationshipsCount': 2, 'isLive': true},
            {'id': 'd2', 'title': 'Clínica', 'isOwner': false, 'classesCount': 1, 'relationshipsCount': 0, 'isLive': false},
          ],
        },
        '/api/mobile/notifications': {'notifications': [], 'unread': 3},
      });

      await tester.pumpWidget(MaterialApp(
        home: DiagramsScreen(api: api, realtime: null, user: _user, onLogout: () {}, onSessionExpired: () {}),
      ));
      // El punto "en vivo" late sin fin: se avanza el reloj en vez de esperar a que se asiente.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ventas'), findsOneWidget);
      expect(find.text('Clínica'), findsOneWidget);
      // Una tarjeta de resumen y la etiqueta del diagrama en vivo.
      expect(find.text('En vivo'), findsNWidgets(2));
      // La campana muestra los avisos sin leer.
      expect(find.byTooltip('Notificaciones'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('Compartidos').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ventas'), findsNothing);
      expect(find.text('Clínica'), findsOneWidget);
    });

    testWidgets('la bandeja agrupa, marca leídas y abre el diagrama', (tester) async {
      final log = <http.Request>[];
      final now = DateTime.now().toUtc();
      final api = _apiWith({
        '/api/mobile/notifications': {
          'unread': 2,
          'notifications': [
            {'id': 'n1', 'type': 'agent', 'title': 'Ventas', 'body': 'Nova: listo', 'diagramId': 'd1', 'diagramTitle': 'Ventas', 'read': false, 'createdAt': now.toIso8601String()},
            {'id': 'n2', 'type': 'invitation', 'title': 'Nueva invitación', 'body': 'Juan te invitó a «Clínica»', 'diagramId': 'd2', 'diagramTitle': 'Clínica', 'read': false, 'createdAt': now.toIso8601String()},
            {'id': 'n3', 'type': 'activity', 'title': 'Ventas', 'body': 'Juan creó Pago', 'diagramId': 'd1', 'diagramTitle': 'Ventas', 'read': true, 'createdAt': now.subtract(const Duration(days: 10)).toIso8601String()},
          ],
        },
        '/api/mobile/notifications/read': {'unread': 0},
      }, log: log);
      String? opened;
      int? unread;

      await tester.pumpWidget(MaterialApp(
        home: NotificationsScreen(api: api, onOpenDiagram: (id, _) => opened = id, onUnreadChanged: (n) => unread = n),
      ));
      await tester.pumpAndSettle();

      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('ANTES'), findsOneWidget);
      expect(find.text('Nova: listo'), findsOneWidget);
      expect(unread, 2);

      await tester.tap(find.byTooltip('Marcar leídas'));
      await tester.pumpAndSettle();
      expect(unread, 0);
      expect(find.byTooltip('Marcar leídas'), findsNothing);
      expect(log.where((r) => r.url.path == '/api/mobile/notifications/read'), isNotEmpty);

      // Una invitación no abre el diagrama: todavía no hay acceso.
      await tester.tap(find.text('Juan te invitó a «Clínica»'));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      expect(find.textContaining('desde la web'), findsOneWidget);

      await tester.tap(find.text('Juan creó Pago'));
      await tester.pumpAndSettle();
      expect(opened, 'd1');

    });

    testWidgets('una sesión vencida vuelve al login', (tester) async {
      var expired = false;
      final api = ApiClient(baseUrl: 'http://s', client: MockClient((_) async => http.Response('{}', 401)));

      await tester.pumpWidget(MaterialApp(
        home: DiagramsScreen(api: api, realtime: null, user: _user, onLogout: () {}, onSessionExpired: () => expired = true),
      ));
      // Sin pumpAndSettle: el indicador de carga sigue girando hasta que la app cambia de pantalla.
      await tester.pump();
      await tester.pump();

      expect(expired, isTrue);
    });

    testWidgets('el detalle muestra diagrama, actividad y preguntas', (tester) async {
      final log = <http.Request>[];
      final api = _apiWith({
        '/api/mobile/diagrams/d1': _diagramJson(),
        '/api/mobile/diagrams/d1/activity': {
          'entries': [
            {'id': 'e1', 'actorName': 'Nova', 'summary': 'creó la clase Pago', 'origin': 'agent', 'requestedByName': 'Juan', 'createdAt': '2026-11-07T10:00:00Z'},
          ],
        },
        '/api/mobile/diagrams/d1/messages': {
          'messages': [
            {'id': 'm1', 'role': 'user', 'authorId': 'u2', 'authorName': 'Juan', 'text': 'Hola equipo', 'createdAt': '2026-11-07T10:00:00Z'},
          ],
        },
        '/api/mobile/diagrams/d1/ask': {
          'message': {'id': 'm2', 'role': 'user', 'authorId': 'u1', 'authorName': 'Ana', 'text': 'pregunta', 'toAgent': true},
        },
      }, log: log);

      await tester.pumpWidget(MaterialApp(
        home: DiagramScreen(
          api: api,
          realtime: null,
          diagramId: 'd1',
          initialTitle: 'Ventas',
          currentUserId: 'u1',
          canvasBuilder: (_) => const Text('lienzo web'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('lienzo web'), findsOneWidget);
      expect(find.text('Trabajando: Juan'), findsOneWidget);

      await tester.tap(find.text('Actividad'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nova creó la clase Pago'), findsOneWidget);
      expect(find.textContaining('a pedido de Juan'), findsOneWidget);

      await tester.tap(find.text('Preguntar'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hola equipo'), findsOneWidget);
      expect(find.textContaining('Juan ·'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pregunta');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(log.where((r) => r.url.path.endsWith('/ask')), hasLength(1));
      expect(find.text('Nova está respondiendo…'), findsOneWidget);
      expect(log.where((r) => r.method != 'GET' && !r.url.path.endsWith('/ask')), isEmpty);
    });

    test('pide el enlace temporal del lienzo web', () async {
      final log = <http.Request>[];
      final api = _apiWith({'/api/mobile/diagrams/d1/viewer-link': {'path': '/mobile/viewer/abc'}}, log: log);

      final url = await api.viewerUrl('d1');

      expect(url.toString(), 'http://server.test/mobile/viewer/abc');
      expect(log.single.method, 'POST');
      expect(log.single.headers['Authorization'], 'Bearer tok');
    });
  });

  test('el realtime hub expone el prefijo del canal de la web', () {
    expect(RealtimeHub.channelPrefix, 'private-diagram-agent.');
  });
}
