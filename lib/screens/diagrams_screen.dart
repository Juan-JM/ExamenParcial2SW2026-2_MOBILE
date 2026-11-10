import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/common.dart';
import 'diagram_screen.dart';
import 'format.dart';
import 'notifications_screen.dart';

enum _Filter { all, mine, shared }

class DiagramsScreen extends StatefulWidget {
  const DiagramsScreen({
    super.key,
    required this.api,
    required this.realtime,
    required this.user,
    required this.onLogout,
    required this.onSessionExpired,
  });

  final ApiClient api;
  final RealtimeHub? realtime;
  final AppUser user;
  final VoidCallback onLogout;
  final VoidCallback onSessionExpired;

  @override
  State<DiagramsScreen> createState() => _DiagramsScreenState();
}

class _DiagramsScreenState extends State<DiagramsScreen> {
  List<DiagramSummary>? _diagrams;
  String? _error;
  _Filter _filter = _Filter.all;
  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<NoticeEvent>? _received;
  StreamSubscription<NoticeEvent>? _opened;
  int _unread = 0;

  /// Acciones que merecen un aviso cuando no hay push de Firebase.
  static const _noticeActions = {'CREATE_CLASS', 'DELETE_CLASS', 'CREATE_RELATION', 'DELETE_RELATION', 'IMPORT', 'CLEAR_DIAGRAM'};

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = widget.realtime?.events.listen(_onEvent);
    _loadUnread();
    _received = AppNotifications.received.listen((_) => _loadUnread());
    _opened = AppNotifications.opened.listen(_onNoticeOpened);

    // La app se abrió tocando una notificación.
    final launch = AppNotifications.takeLaunchNotice();
    if (launch != null) WidgetsBinding.instance.addPostFrameCallback((_) => _onNoticeOpened(launch));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _received?.cancel();
    _opened?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final diagrams = await widget.api.diagrams();
      if (!mounted) return;

      setState(() {
        _diagrams = diagrams;
        _error = null;
      });

      await widget.realtime?.watch(diagrams.map((d) => d.id));
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        widget.onSessionExpired();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    }
  }

  Future<void> _loadUnread() async {
    try {
      final inbox = await widget.api.notifications();
      if (mounted) setState(() => _unread = inbox.unread);
    } on ApiException {
      // La campana se queda como estaba; no vale la pena molestar.
    }
  }

  void _onNoticeOpened(NoticeEvent notice) {
    final id = notice.diagramId;
    final notificationId = notice.notificationId;

    if (notificationId != null) {
      widget.api.markNotificationsRead(id: notificationId).then((unread) {
        if (mounted) setState(() => _unread = unread);
      }, onError: (_) {});
    }

    if (id == null || notice.type == 'invitation') {
      _openNotifications();
      return;
    }

    final title = _diagrams?.where((d) => d.id == id).firstOrNull?.title ?? 'Diagrama';
    _openById(id, title);
  }

  void _openNotifications() {
    // Si ya está abierta (por ejemplo, tocó otro aviso), no se apila otra.
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'notifications'),
        builder: (_) => NotificationsScreen(
          api: widget.api,
          onSessionExpired: widget.onSessionExpired,
          onUnreadChanged: (unread) {
            if (mounted) setState(() => _unread = unread);
          },
          onOpenDiagram: (id, title) => _openById(id, title, fromInbox: true),
        ),
      ),
    ).then((_) => _loadUnread());
  }

  void _onEvent(RealtimeEvent event) {
    if (event.name == 'DiagramContentChanged') _load();

    if (event.name == 'ActivityRecorded' && !AppNotifications.hasPush) {
      _notifyActivity(event);
    }
  }

  void _notifyActivity(RealtimeEvent event) {
    final entries = (event.data['entries'] as List? ?? const [])
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .where((e) => e.actorId != widget.user.id && _noticeActions.contains(e.action));

    if (entries.isEmpty) return;

    final title = _diagrams?.where((d) => d.id == event.diagramId).firstOrNull?.title ?? 'Diagrama';
    AppNotifications.show(title, '${entries.first.actorName} ${entries.first.summary}');
  }

  void _open(DiagramSummary diagram) => _openById(diagram.id, diagram.title, live: diagram.isLive);

  void _openById(String id, String title, {bool? live, bool fromInbox = false}) {
    final navigator = Navigator.of(context);
    // Desde un aviso del sistema se parte del panel; desde la bandeja, se vuelve a ella.
    if (!fromInbox) navigator.popUntil((route) => route.isFirst);

    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => DiagramScreen(
          api: widget.api,
          realtime: widget.realtime,
          diagramId: id,
          initialTitle: title,
          currentUserId: widget.user.id,
          initiallyLive: live ?? _diagrams?.where((d) => d.id == id).firstOrNull?.isLive ?? false,
        ),
      ),
    ).then((_) {
      _load();
      _loadUnread();
    });
  }

  void _openAccount() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _AccountSheet(user: widget.user, server: widget.api.baseUrl, onLogout: widget.onLogout),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final diagrams = _diagrams;
    final error = _error;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              if (diagrams == null && error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'No pudimos cargar tus diagramas',
                      message: error,
                      action: OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                    ),
                  ),
                )
              else if (diagrams == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                SliverToBoxAdapter(child: _buildStats(diagrams)),
                SliverToBoxAdapter(child: _buildFilters(diagrams)),
                ..._buildList(diagrams),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = widget.user.name.split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(
        children: [
          const AppLogo(size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
                Text(firstName, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _BellButton(unread: _unread, onTap: _openNotifications),
          const SizedBox(width: 4),
          InkWell(
            onTap: _openAccount,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: InitialsAvatar(name: widget.user.name, size: 38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<DiagramSummary> diagrams) {
    final live = diagrams.where((d) => d.isLive).length;
    final shared = diagrams.where((d) => !d.isOwner).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'En vivo',
              value: '$live',
              icon: Icons.sensors_rounded,
              highlight: live > 0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: 'Diagramas', value: '${diagrams.length}', icon: Icons.account_tree_outlined)),
          const SizedBox(width: 10),
          Expanded(child: _StatCard(label: shared == 1 ? 'Compartido' : 'Compartidos', value: '$shared', icon: Icons.group_outlined)),
        ],
      ),
    );
  }

  Widget _buildFilters(List<DiagramSummary> diagrams) {
    Widget chip(_Filter filter, String label) {
      final selected = _filter == filter;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = filter),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.text,
          ),
          selectedColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tus diagramas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                chip(_Filter.all, 'Todos'),
                chip(_Filter.mine, 'Míos'),
                chip(_Filter.shared, 'Compartidos'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildList(List<DiagramSummary> diagrams) {
    final visible = switch (_filter) {
      _Filter.all => diagrams,
      _Filter.mine => diagrams.where((d) => d.isOwner).toList(),
      _Filter.shared => diagrams.where((d) => !d.isOwner).toList(),
    };

    // Los que están en vivo, primero.
    final sorted = [...visible.where((d) => d.isLive), ...visible.where((d) => !d.isLive)];

    if (sorted.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyState(
              icon: Icons.draw_outlined,
              title: diagrams.isEmpty ? 'Todavía no tienes diagramas' : 'Nada por aquí',
              message: diagrams.isEmpty
                  ? 'Créalos desde la web y aparecerán aquí al instante.'
                  : 'No hay diagramas en esta sección.',
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        sliver: SliverList.separated(
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) => DiagramCard(diagram: sorted[index], onTap: () => _open(sorted[index])),
        ),
      ),
    ];
  }
}

/// Campana del panel con el número de avisos sin leer.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Notificaciones',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line),
                ),
                child: Icon(
                  unread > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                  size: 21,
                  color: unread > 0 ? AppColors.ink : AppColors.muted,
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: 2,
                  right: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 19),
                    height: 19,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, this.highlight = false});

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.ink : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? AppColors.ink : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: highlight ? AppColors.live : AppColors.subtle),
              const Spacer(),
              if (highlight) const LiveDot(size: 6),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: highlight ? Colors.white : AppColors.ink,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: highlight ? Colors.white70 : AppColors.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class DiagramCard extends StatelessWidget {
  const DiagramCard({super.key, required this.diagram, required this.onTap});

  final DiagramSummary diagram;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = diagram.lastSavedAt;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: diagram.isLive ? AppColors.live.withValues(alpha: 0.45) : AppColors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: diagram.isLive ? AppColors.liveSoft : AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: CustomPaint(
                    painter: LogoMarkPainter(color: diagram.isLive ? const Color(0xFF059669) : AppColors.accent),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              diagram.title,
                              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!diagram.isOwner) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.group_outlined, size: 15, color: AppColors.subtle),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${diagram.classesCount} clases · ${diagram.relationshipsCount} relaciones',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                      ),
                      if (saved != null) ...[
                        const SizedBox(height: 2),
                        Text('Editado ${formatRelative(saved)}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.subtle)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (diagram.isLive)
                  const Pill(
                    label: 'En vivo',
                    leading: LiveDot(size: 6),
                    background: AppColors.liveSoft,
                    foreground: Color(0xFF047857),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.user, required this.server, required this.onLogout});

  final AppUser user;
  final String server;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InitialsAvatar(name: user.name, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.titleMedium),
                      Text(user.email, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Servidor', style: theme.textTheme.bodySmall),
                        Text(server, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onLogout();
              },
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
