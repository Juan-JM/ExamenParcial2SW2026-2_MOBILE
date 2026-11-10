import 'package:flutter/material.dart';

import '../theme.dart';

/// Logo de la app: dos clases UML unidas por una relación, sobre una
/// baldosa índigo. Es el mismo motivo del logo de la web.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.28),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: CustomPaint(painter: LogoMarkPainter(color: Colors.white)),
    );
  }
}

/// Solo el trazo del logo (sin baldosa), para fondos propios.
class LogoMarkPainter extends CustomPainter {
  const LogoMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final o = Offset((size.width - s) / 2, (size.height - s) / 2);
    Offset p(double x, double y) => o + Offset(x * s, y * s);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: 0.95);
    final soft = Paint()..color = color.withValues(alpha: 0.35);

    // Clase de arriba a la izquierda: cabecera llena + cuerpo.
    final a = RRect.fromRectAndRadius(Rect.fromPoints(p(0.2, 0.2), p(0.5, 0.48)), Radius.circular(s * 0.05));
    canvas.drawRRect(a, soft);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromPoints(p(0.2, 0.2), p(0.5, 0.29)),
        topLeft: Radius.circular(s * 0.05),
        topRight: Radius.circular(s * 0.05),
      ),
      fill,
    );

    // Clase de abajo a la derecha.
    final b = RRect.fromRectAndRadius(Rect.fromPoints(p(0.5, 0.52), p(0.8, 0.8)), Radius.circular(s * 0.05));
    canvas.drawRRect(b, soft);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromPoints(p(0.5, 0.52), p(0.8, 0.61)),
        topLeft: Radius.circular(s * 0.05),
        topRight: Radius.circular(s * 0.05),
      ),
      fill,
    );

    // Relación ortogonal entre ambas, como en el editor.
    final path = Path()
      ..moveTo(p(0.35, 0.48).dx, p(0.35, 0.48).dy)
      ..lineTo(p(0.35, 0.66).dx, p(0.35, 0.66).dy)
      ..lineTo(p(0.5, 0.66).dx, p(0.5, 0.66).dy);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(LogoMarkPainter oldDelegate) => oldDelegate.color != color;
}
