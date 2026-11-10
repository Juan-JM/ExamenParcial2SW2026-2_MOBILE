import 'dart:async';
import 'dart:ui' show Color;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// Lo que llegó en un aviso: para refrescar la bandeja o abrir el diagrama.
class NoticeEvent {
  const NoticeEvent({this.diagramId, this.notificationId, this.type});

  factory NoticeEvent.fromData(Map<String, dynamic> data) => NoticeEvent(
    diagramId: _nonEmpty(data['diagramId']),
    notificationId: _nonEmpty(data['notificationId']),
    type: _nonEmpty(data['type']),
  );

  final String? diagramId;
  final String? notificationId;
  final String? type;

  static String? _nonEmpty(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// Notificaciones del celular. Con Firebase (google-services.json) llegan
/// aunque la app esté cerrada; sin él, solo mientras está abierta.
///
/// - [received]: llegó un aviso con la app abierta (la campana se actualiza).
/// - [opened]: el usuario tocó un aviso (se abre el diagrama).
class AppNotifications {
  AppNotifications._();

  static final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'diagram_updates';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Cambios en los diagramas',
      channelDescription: 'Avisos de lo que hace tu equipo y la IA',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_notify',
      color: Color(0xFF4F46E5),
    ),
  );

  static bool _firebaseReady = false;
  static int _nextId = 0;
  static String? _deviceToken;
  static StreamSubscription<String>? _tokenRefresh;

  static final _received = StreamController<NoticeEvent>.broadcast();
  static final _opened = StreamController<NoticeEvent>.broadcast();

  static Stream<NoticeEvent> get received => _received.stream;
  static Stream<NoticeEvent> get opened => _opened.stream;

  /// El aviso con el que se abrió la app (si se abrió tocando uno). Se consume una vez.
  static NoticeEvent? _launch;
  static NoticeEvent? takeLaunchNotice() {
    final notice = _launch;
    _launch = null;
    return notice;
  }

  /// Si Firebase está activo, el servidor ya envía los avisos importantes.
  static bool get hasPush => _firebaseReady;

  static Future<void> initialize() async {
    await _local.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
      onDidReceiveNotificationResponse: (response) => _opened.add(_fromPayload(response.payload)),
    );

    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // El canal se crea antes de que llegue el primer push con la app cerrada.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Cambios en los diagramas',
        description: 'Avisos de lo que hace tu equipo y la IA',
        importance: Importance.high,
      ),
    );
    await android?.requestNotificationsPermission();

    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) _launch = _fromPayload(launch!.notificationResponse?.payload);

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;

      // Con la app abierta Android no muestra el push: se muestra a mano.
      FirebaseMessaging.onMessage.listen((message) {
        final notice = NoticeEvent.fromData(message.data);
        final notification = message.notification;
        if (notification != null) {
          show(notification.title ?? 'Diagrama', notification.body ?? '', diagramId: notice.diagramId, notificationId: notice.notificationId);
        }
        _received.add(notice);
      });

      // Tocó el push con la app en segundo plano o cerrada.
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _opened.add(NoticeEvent.fromData(message.data)));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _launch = NoticeEvent.fromData(initial.data);
    } catch (error) {
      // Sin google-services.json: la app funciona igual, sin push con la app cerrada.
      debugPrint('Firebase no está configurado: $error');
    }
  }

  static Future<void> registerDevice(ApiClient api) async {
    if (!_firebaseReady) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      _deviceToken = token;
      if (token != null) await api.registerDevice(token);

      await _tokenRefresh?.cancel();
      _tokenRefresh = messaging.onTokenRefresh.listen((newToken) {
        _deviceToken = newToken;
        api.registerDevice(newToken);
      });
    } catch (error) {
      debugPrint('No se pudo registrar el dispositivo: $error');
    }
  }

  /// Al cerrar sesión: este celular deja de recibir los avisos de esa cuenta.
  static Future<void> unregisterDevice(ApiClient api) async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;

    final token = _deviceToken;
    if (token == null) return;

    try {
      await api.unregisterDevice(token);
    } catch (_) {
      // Sin conexión: el servidor lo borra cuando FCM diga que no sirve.
    }
  }

  static Future<void> show(String title, String body, {String? diagramId, String? notificationId}) async {
    await _local.show(
      _nextId++,
      title,
      body,
      _details,
      payload: '${diagramId ?? ''}|${notificationId ?? ''}',
    );
  }

  static NoticeEvent _fromPayload(String? payload) {
    final parts = (payload ?? '').split('|');
    return NoticeEvent.fromData({
      'diagramId': parts.isNotEmpty ? parts[0] : null,
      'notificationId': parts.length > 1 ? parts[1] : null,
    });
  }
}
