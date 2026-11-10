import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../realtime.dart';
import '../theme.dart';
import '../voice.dart';
import '../widgets/common.dart';
import '../widgets/diagram_canvas.dart';
import 'format.dart';

/// Detalle de un diagrama: lienzo en vivo (la vista web embebida), actividad
/// y preguntas a la IA. No permite editar.
class DiagramScreen extends StatefulWidget {
  const DiagramScreen({
    super.key,
    required this.api,
    required this.realtime,
    required this.diagramId,
    required this.initialTitle,
    required this.currentUserId,
    this.initiallyLive = false,
    this.canvasBuilder,
  });

  final ApiClient api;
  final RealtimeHub? realtime;
  final String diagramId;
  final String initialTitle;
  final String currentUserId;
  final bool initiallyLive;

  /// Para pruebas: reemplaza el WebView del lienzo.
  final WidgetBuilder? canvasBuilder;

  @override
  State<DiagramScreen> createState() => _DiagramScreenState();
}

class _DiagramScreenState extends State<DiagramScreen> {
  DiagramDetail? _detail;
  List<ActivityItem> _activity = const [];
  List<ChatMessage> _messages = const [];
  bool _online = true;
  int _tab = 0;
  final _canvas = DiagramCanvasController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();

    final realtime = widget.realtime;
    if (realtime != null) {
      _subscriptions
        ..add(realtime.events.where((e) => e.diagramId == widget.diagramId).listen(_onEvent))
        ..add(realtime.connection.listen(_onConnection));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _onConnection(bool online) {
    if (!mounted) return;
    setState(() => _online = online);

    // Al volver la señal, ponerse al día con lo ocurrido mientras tanto.
    if (online) _loadAll();
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.name) {
      case 'DiagramContentChanged':
        _loadDetail();
      case 'ActivityRecorded':
        final entries = (event.data['entries'] as List? ?? const [])
            .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _activity = [...entries.reversed, ..._activity]);
        if (entries.any((e) => e.action == 'SESSION_JOIN' || e.action == 'SESSION_LEAVE')) _loadDetail();
      case 'AgentMessagePosted':
        final message = ChatMessage.fromJson(event.data['message'] as Map<String, dynamic>);
        setState(() {
          _messages = [..._messages.where((m) => m.id != message.id), message];
        });
    }
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadDetail(), _loadActivity(), _loadMessages()]);
  }

  Future<void> _loadDetail() async {
    try {
      final detail = await widget.api.diagram(widget.diagramId);
      if (mounted) setState(() => _detail = detail);
    } on ApiException {
      // El lienzo muestra su propio error; acá solo faltan los datos de cabecera.
    }
  }

  Future<void> _loadActivity() async {
    try {
      final items = await widget.api.activity(widget.diagramId);
      if (mounted) setState(() => _activity = items);
    } on ApiException {
      // Se conserva lo ya cargado: el aviso de conexión informa del problema.
    }
  }

  Future<void> _loadMessages() async {
    try {
      final items = await widget.api.messages(widget.diagramId);
      if (mounted) setState(() => _messages = items);
    } on ApiException {
      // Se conserva lo ya cargado: el aviso de conexión informa del problema.
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final present = detail?.present ?? const <String>[];
    final live = widget.initiallyLive || present.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail?.title ?? widget.initialTitle,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                LiveDot(size: 6, active: live && _online),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    !_online
                        ? 'Sin conexión'
                        : present.isNotEmpty
                        ? 'Trabajando: ${present.join(', ')}'
                        : live
                        ? 'En vivo'
                        : 'Se actualiza al guardar',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_tab == 0) ...[
            IconButton(tooltip: 'Encuadrar', onPressed: _canvas.fit, icon: const Icon(Icons.fit_screen_outlined)),
            IconButton(tooltip: 'Recargar', onPressed: _canvas.reload, icon: const Icon(Icons.refresh_rounded)),
          ],
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
      ),
      body: Column(
        children: [
          if (!_online)
            Container(
              width: double.infinity,
              color: AppColors.dangerSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Text(
                'Sin conexión. Lo que ves puede no estar al día.',
                style: TextStyle(color: Color(0xFF991B1B), fontSize: 13),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                widget.canvasBuilder?.call(context) ??
                    DiagramCanvas(api: widget.api, diagramId: widget.diagramId, controller: _canvas),
                _ActivityTab(items: _activity, onRefresh: _loadActivity),
                _AskTab(
                  agentName: detail?.agentName ?? 'Asistente',
                  messages: _messages,
                  currentUserId: widget.currentUserId,
                  onAsk: (text) async {
                    final message = await widget.api.ask(widget.diagramId, text);
                    if (mounted) {
                      setState(() {
                        _messages = [..._messages.where((m) => m.id != message.id), message];
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree), label: 'Diagrama'),
          NavigationDestination(icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history_rounded), label: 'Actividad'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Preguntar'),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.items, required this.onRefresh});

  final List<ActivityItem> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Sin actividad todavía',
                  message: 'Cada cambio del equipo aparecerá aquí, con quién lo hizo.',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              itemBuilder: (_, index) => _ActivityRow(item: items[index], last: index == items.length - 1),
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.last});

  final ActivityItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt;
    final origin = item.originLabel;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              InitialsAvatar(name: item.actorName, size: 32),
              if (!last) Expanded(child: Container(width: 1.5, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 4))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: item.actorName, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                        TextSpan(text: ' ${item.summary}'),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.text),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (date != null) Text(formatRelative(date), style: const TextStyle(fontSize: 12, color: AppColors.subtle)),
                      if (origin != null) Pill(label: origin),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AskTab extends StatefulWidget {
  const _AskTab({
    required this.agentName,
    required this.messages,
    required this.currentUserId,
    required this.onAsk,
  });

  final String agentName;
  final List<ChatMessage> messages;
  final String currentUserId;
  final Future<void> Function(String text) onAsk;

  @override
  State<_AskTab> createState() => _AskTabState();
}

class _AskTabState extends State<_AskTab> {
  final _input = TextEditingController();
  final _voice = NovaVoice.instance;
  bool _sending = false;
  String? _error;

  /// Respuestas ya vistas: solo se lee en voz alta lo que llega después de abrir.
  late final Set<String> _heard = widget.messages
      .where((m) => m.role == 'assistant' && m.displayText.isNotEmpty)
      .map((m) => m.id)
      .toSet();

  @override
  void didUpdateWidget(_AskTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    final mine = widget.messages.where((m) => m.authorId == widget.currentUserId).map((m) => m.id).toSet();
    ChatMessage? toSpeak;

    for (final message in widget.messages) {
      if (message.role != 'assistant' || message.displayText.isEmpty || _heard.contains(message.id)) continue;
      _heard.add(message.id);
      // Nova lee lo que te responde a vos, no lo que le contesta a otro del equipo.
      if (mine.contains(message.replyTo)) toSpeak = message;
    }

    if (toSpeak != null && _voice.enabled.value) _voice.speak(toSpeak.id, toSpeak.displayText);
  }

  Future<void> _toggleMic() async {
    if (_voice.listening.value) {
      await _voice.stopListening();
      return;
    }

    setState(() => _error = null);
    final started = await _voice.listen(
      onWords: (words) {
        _input.value = TextEditingValue(text: words, selection: TextSelection.collapsed(offset: words.length));
      },
      onDone: (words) {
        if (words.isNotEmpty) _send(words);
      },
    );

    if (!started && mounted) {
      setState(() => _error = 'No se pudo usar el micrófono. Revisa el permiso en Ajustes.');
    }
  }

  static const _suggestions = [
    '¿Qué avanzaron hoy y qué hizo cada uno?',
    '¿Qué clases tiene el diagrama?',
    '¿Qué cambió en la última hora?',
  ];

  @override
  void dispose() {
    _voice.stopSpeaking();
    _voice.stopListening();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await widget.onAsk(text);
      _input.clear();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool get _awaitingReply {
    final replied = widget.messages.map((m) => m.replyTo).whereType<String>().toSet();

    return widget.messages.any(
      (m) => m.role == 'user' && m.toAgent && m.authorId == widget.currentUserId && !replied.contains(m.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages.reversed.toList();

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Pregúntale a ${widget.agentName}',
                      message: 'Te cuenta qué avanzó el equipo. Desde el celular solo informa, no edita.',
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: messages.length,
                  itemBuilder: (_, index) => _Bubble(
                    message: messages[index],
                    mine: messages[index].authorId == widget.currentUserId,
                    onTap: messages[index].role == 'assistant'
                        ? () => _voice.speaking.value == messages[index].id
                              ? _voice.stopSpeaking()
                              : _voice.speak(messages[index].id, messages[index].displayText)
                        : null,
                  ),
                ),
        ),
        if (_awaitingReply)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8)),
                const SizedBox(width: 8),
                Text('${widget.agentName} está respondiendo…', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _suggestions.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) => index == 0
                ? _VoiceToggle(voice: _voice, agentName: widget.agentName)
                : ActionChip(
                    label: Text(_suggestions[index - 1]),
                    onPressed: _sending ? null : () => _send(_suggestions[index - 1]),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    labelStyle: const TextStyle(fontSize: 13, color: AppColors.text),
                  ),
          ),
        ),
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: _voice.listening.value ? 'Te escucho…' : 'Pregúntale a ${widget.agentName}',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.accent, width: 1.6)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<bool>(
                valueListenable: _voice.listening,
                builder: (_, listening, _) => _MicButton(listening: listening, onPressed: _sending ? null : _toggleMic),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.ink, minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Parlante: si Nova lee sus respuestas en voz alta. Apagarlo corta lo que esté diciendo.
class _VoiceToggle extends StatelessWidget {
  const _VoiceToggle({required this.voice, required this.agentName});

  final NovaVoice voice;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: voice.enabled,
      builder: (_, on, _) => FilterChip(
        selected: on,
        showCheckmark: false,
        avatar: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 18, color: on ? Colors.white : AppColors.muted),
        label: Text(on ? 'Voz' : 'Sin voz'),
        tooltip: on ? 'Silenciar a $agentName' : '$agentName lee sus respuestas',
        onSelected: (value) {
          voice.enabled.value = value;
          if (!value) voice.stopSpeaking();
        },
        selectedColor: AppColors.accent,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: on ? AppColors.accent : AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : AppColors.text),
      ),
    );
  }
}

/// Micrófono: mientras escucha se pone rojo y late; tocarlo de nuevo deja de escuchar.
class _MicButton extends StatefulWidget {
  const _MicButton({required this.listening, required this.onPressed});

  final bool listening;
  final VoidCallback? onPressed;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didUpdateWidget(_MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.listening) _pulse.reset();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => Container(
                width: 48 + 16 * _pulse.value,
                height: 48 + 16 * _pulse.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: red.withValues(alpha: 0.3 * (1 - _pulse.value))),
              ),
            ),
          IconButton.filled(
            tooltip: widget.listening ? 'Dejar de escuchar' : 'Hablar',
            onPressed: widget.onPressed,
            style: IconButton.styleFrom(
              backgroundColor: widget.listening ? red : AppColors.accentSoft,
              minimumSize: const Size(48, 48),
            ),
            icon: Icon(
              widget.listening ? Icons.stop_rounded : Icons.mic_none_rounded,
              color: widget.listening ? Colors.white : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, this.onTap});

  final ChatMessage message;
  final bool mine;

  /// En las respuestas de la IA: leer en voz alta o callar.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = message.createdAt;
    final assistant = message.role == 'assistant';
    final system = message.role == 'system';

    final background = system
        ? AppColors.dangerSoft
        : mine
        ? AppColors.ink
        : AppColors.surface;
    final foreground = mine ? Colors.white : AppColors.text;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: background,
          border: mine ? null : Border.all(color: assistant ? AppColors.accent.withValues(alpha: 0.25) : AppColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (assistant) ...[
                  const Icon(Icons.auto_awesome, size: 13, color: AppColors.accent),
                  const SizedBox(width: 4),
                ],
                if (assistant)
                  ValueListenableBuilder<String?>(
                    valueListenable: NovaVoice.instance.speaking,
                    builder: (_, id, _) => id == message.id
                        ? const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.graphic_eq_rounded, size: 14, color: AppColors.accent),
                          )
                        : const SizedBox.shrink(),
                  ),
                Text(
                  [message.authorName, if (date != null) formatTime(date)].join(' · '),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: mine ? Colors.white70 : (assistant ? AppColors.accent : AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(message.displayText, style: TextStyle(color: foreground, height: 1.4)),
          ],
        ),
      ),
      ),
    );
  }
}
