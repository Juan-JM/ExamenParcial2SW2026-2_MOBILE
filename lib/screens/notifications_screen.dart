import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../notifications.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'format.dart';

/// Bandeja de avisos: cambios del equipo, respuestas de la IA e invitaciones.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.api,
    required this.onOpenDiagram,
    this.onUnreadChanged,
    this.onSessionExpired,
  });

  final ApiClient api;
  final void Function(String diagramId, String title) onOpenDiagram;
  final ValueChanged<int>? onUnreadChanged;
  final VoidCallback? onSessionExpired;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotice>? _notices;
  int _unread = 0;
  String? _error;
  StreamSubscription<NoticeEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = AppNotifications.received.listen((_) => _load());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final inbox = await widget.api.notifications();
      if (!mounted) return;
      setState(() {
        _notices = inbox.notices;
        _unread = inbox.unread;
        _error = null;
      });
      widget.onUnreadChanged?.call(inbox.unread);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        widget.onSessionExpired?.call();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    }
  }

  void _setUnread(int unread) {
    _unread = unread;
    widget.onUnreadChanged?.call(unread);
  }

  Future<void> _markAllRead() async {
    final notices = _notices;
    if (notices == null || _unread == 0) return;

    setState(() {
      _notices = notices.map((n) => n.markedRead()).toList();
      _setUnread(0);
    });

    try {
      _setUnread(await widget.api.markNotificationsRead());
    } on ApiException {
      _load();
    }
  }

  Future<void> _open(AppNotice notice) async {
    if (!notice.read) {
      setState(() {
        _notices = _notices?.map((n) => n.id == notice.id ? n.markedRead() : n).toList();
        _setUnread((_unread - 1).clamp(0, 1 << 30));
      });
      widget.api.markNotificationsRead(id: notice.id).then(_setUnread, onError: (_) {});
    }

    final diagramId = notice.diagramId;
    if (notice.type == 'invitation' || diagramId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Acepta la invitación desde la web para ver el diagrama aquí.')));
      return;
    }

    widget.onOpenDiagram(diagramId, notice.diagramTitle ?? notice.title);
  }

  @override
  Widget build(BuildContext context) {
    final notices = _notices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (_unread > 0)
            IconButton(
              tooltip: 'Marcar leídas',
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all_rounded, color: AppColors.accent),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: notices == null
            ? _buildPlaceholder()
            : notices.isEmpty
            ? _buildFill(
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Todo al día',
                  message: 'Cuando tu equipo o la IA cambien algo en tus diagramas, lo verás aquí.',
                ),
              )
            : _buildList(notices),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final error = _error;
    if (error == null) return _buildFill(const CircularProgressIndicator());

    return _buildFill(
      EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No pudimos cargar tus notificaciones',
        message: error,
        action: OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
      ),
    );
  }

  /// Contenido centrado que igual permite "tirar para actualizar".
  Widget _buildFill(Widget child) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [SliverFillRemaining(hasScrollBody: false, child: Center(child: child))],
  );

  Widget _buildList(List<AppNotice> notices) {
    final groups = <String, List<AppNotice>>{};
    for (final notice in notices) {
      groups.putIfAbsent(_groupOf(notice.createdAt), () => []).add(notice);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Text(
              entry.key.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.subtle),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68, color: AppColors.line),
                  NoticeTile(notice: entry.value[i], onTap: () => _open(entry.value[i])),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _groupOf(DateTime? date, {DateTime? now}) {
    if (date == null) return 'Antes';
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final days = today.difference(DateTime(date.year, date.month, date.day)).inDays;

    if (days <= 0) return 'Hoy';
    if (days == 1) return 'Ayer';
    if (days < 7) return 'Esta semana';
    return 'Antes';
  }
}

class NoticeTile extends StatelessWidget {
  const NoticeTile({super.key, required this.notice, required this.onTap});

  final AppNotice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, foreground, background) = switch (notice.type) {
      'agent' => (Icons.auto_awesome_rounded, const Color(0xFF7C3AED), const Color(0xFFF3EEFF)),
      'invitation' => (Icons.person_add_alt_1_rounded, const Color(0xFF047857), AppColors.liveSoft),
      _ => (Icons.edit_note_rounded, AppColors.accent, AppColors.accentSoft),
    };
    final date = notice.createdAt;
    final heading = notice.type == 'invitation' ? notice.title : (notice.diagramTitle ?? notice.title);

    return Material(
      color: notice.read ? AppColors.surface : const Color(0xFFFAFAFF),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: foreground),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: notice.read ? FontWeight.w600 : FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (date != null) ...[
                          const SizedBox(width: 8),
                          Text(formatRelative(date), style: const TextStyle(fontSize: 12, color: AppColors.subtle)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notice.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, height: 1.35, color: notice.read ? AppColors.muted : AppColors.text),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: notice.read ? 0 : 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
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
