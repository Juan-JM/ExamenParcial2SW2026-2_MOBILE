import 'package:flutter/material.dart';

import '../theme.dart';

/// Punto verde que late: "en vivo".
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8, this.active = true});

  final double size;
  final bool active;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) _controller.repeat();
    if (!widget.active) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.live : AppColors.subtle;

    return SizedBox(
      width: widget.size * 2.2,
      height: widget.size * 2.2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.active)
              Container(
                width: widget.size * (1 + _controller.value * 1.2),
                height: widget.size * (1 + _controller.value * 1.2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.35 * (1 - _controller.value)),
                ),
              ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta pequeña redondeada.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.leading, this.background = AppColors.soft, this.foreground = AppColors.muted});

  final String label;
  final Widget? leading;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(leading == null ? 10 : 6, 4, 10, 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 2)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
        ],
      ),
    );
  }
}

/// Avatar con iniciales y color estable por nombre.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 36});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    final color = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }
}

/// Estado vacío o de error, centrado y sobrio.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
