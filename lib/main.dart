import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';
import 'notifications.dart';
import 'realtime.dart';
import 'screens/diagrams_screen.dart';
import 'screens/login_screen.dart';
import 'session_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotifications.initialize();

  final store = SessionStore();

  runApp(
    UmlVisorApp(
      store: store,
      session: await store.load(),
      lastServer: await store.lastServer(),
    ),
  );
}

class UmlVisorApp extends StatefulWidget {
  const UmlVisorApp({super.key, required this.store, this.session, this.lastServer});

  final SessionStore store;
  final StoredSession? session;
  final String? lastServer;

  @override
  State<UmlVisorApp> createState() => _UmlVisorAppState();
}

class _UmlVisorAppState extends State<UmlVisorApp> {
  ApiClient? _api;
  RealtimeHub? _realtime;
  AppUser? _user;
  String? _lastServer;

  @override
  void initState() {
    super.initState();
    _lastServer = widget.lastServer;

    final session = widget.session;
    if (session != null) _start(session.baseUrl, session.token, session.user);
  }

  @override
  void dispose() {
    _realtime?.close();
    super.dispose();
  }

  void _start(String baseUrl, String token, AppUser user) {
    final api = ApiClient(baseUrl: baseUrl, token: token);

    _api = api;
    _user = user;
    _realtime = RealtimeHub(api);

    AppNotifications.registerDevice(api);
  }

  void _onLoggedIn(String baseUrl, String token, AppUser user) {
    widget.store.save(StoredSession(baseUrl: baseUrl, token: token, user: user));
    setState(() {
      _lastServer = baseUrl;
      _start(baseUrl, token, user);
    });
  }

  Future<void> _end({required bool revokeToken}) async {
    final api = _api;

    if (revokeToken && api != null) {
      // Este celular deja de recibir los avisos de esta cuenta.
      await AppNotifications.unregisterDevice(api);
      try {
        await api.logout();
      } on ApiException {
        // Sin conexión: igual se sale en este celular.
      }
    }

    await widget.store.clear();
    await _realtime?.close();

    setState(() {
      _api = null;
      _realtime = null;
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    final user = _user;

    return MaterialApp(
      title: 'UML Live',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: api != null && user != null
          ? DiagramsScreen(
              key: ValueKey(user.id),
              api: api,
              realtime: _realtime,
              user: user,
              onLogout: () => _end(revokeToken: true),
              onSessionExpired: () => _end(revokeToken: false),
            )
          : LoginScreen(
              initialServer: _lastServer,
              clientFor: (baseUrl) => ApiClient(baseUrl: baseUrl),
              onLoggedIn: _onLoggedIn,
            ),
    );
  }
}
