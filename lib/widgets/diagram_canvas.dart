import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api_client.dart';
import '../theme.dart';
import 'common.dart';

/// Controla el lienzo desde la barra de la app (encuadrar, recargar).
class DiagramCanvasController {
  _DiagramCanvasState? _state;

  void fit() => _state?._fit();
  void reload() => _state?._open();
}

/// El lienzo es la vista "Ver" de la web embebida (solo el lienzo, con
/// `?embed=1`): el mismo motor del editor, con las mismas relaciones,
/// clases asociativas y tiempo real. La app no dibuja nada por su cuenta.
class DiagramCanvas extends StatefulWidget {
  const DiagramCanvas({super.key, required this.api, required this.diagramId, this.controller, this.onUpdated});

  final ApiClient api;
  final String diagramId;
  final DiagramCanvasController? controller;
  final VoidCallback? onUpdated;

  @override
  State<DiagramCanvas> createState() => _DiagramCanvasState();
}

class _DiagramCanvasState extends State<DiagramCanvas> {
  late final WebViewController _web;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..addJavaScriptChannel('UmlApp', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Por si la página no avisa "ready" (p. ej. un error del servidor).
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted && _loading) setState(() => _loading = false);
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = 'No se pudo abrir el lienzo. Revisa tu conexión.';
                });
              }
            }
          },
        ),
      );

    _open();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = await widget.api.viewerUrl(widget.diagramId);
      await _web.loadRequest(url);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  void _fit() => _web.runJavaScript('window.umlViewerFit && window.umlViewerFit()');

  void _onMessage(JavaScriptMessage message) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (data['type']) {
      case 'ready':
        if (mounted) setState(() => _loading = false);
      case 'updated':
        widget.onUpdated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _web)),
        if (error != null)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.background,
              child: Center(
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Lienzo no disponible',
                  message: error,
                  action: OutlinedButton(onPressed: _open, child: const Text('Reintentar')),
                ),
              ),
            ),
          ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _loading && error == null ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: const ColoredBox(
              color: AppColors.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    SizedBox(height: 14),
                    Text('Abriendo lienzo…', style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
