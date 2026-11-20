import 'package:flutter/material.dart';

class PlayerLyricsIcon extends StatelessWidget {
  const PlayerLyricsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return CustomPaint(
      key: const ValueKey('player-lyrics-icon'),
      size: Size.square(size),
      painter: _LyricsBubblePainter(theme.color ?? Colors.white),
    );
  }
}

class _LyricsBubblePainter extends CustomPainter {
  const _LyricsBubblePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.width / 24, size.height / 24);
    final bubble = Path()
      ..moveTo(6, 3)
      ..lineTo(18, 3)
      ..quadraticBezierTo(22, 3, 22, 7)
      ..lineTo(22, 14)
      ..quadraticBezierTo(22, 18, 18, 18)
      ..lineTo(11, 18)
      ..lineTo(7, 21)
      ..lineTo(7, 18)
      ..lineTo(6, 18)
      ..quadraticBezierTo(2, 18, 2, 14)
      ..lineTo(2, 7)
      ..quadraticBezierTo(2, 3, 6, 3)
      ..close();
    canvas.drawPath(bubble, Paint()..color = color);
    final cutout = Paint()..blendMode = BlendMode.clear;
    for (final x in [8.0, 14.5]) {
      final quote = Path()
        ..moveTo(x, 6.5)
        ..cubicTo(x - 1.5, 6.5, x - 2.2, 7.4, x - 2.2, 8.7)
        ..cubicTo(x - 2.2, 10, x - 1.3, 10.8, x, 10.8)
        ..lineTo(x + 0.5, 10.8)
        ..cubicTo(x + 0.3, 12, x - 0.5, 12.8, x - 1.6, 13.2)
        ..lineTo(x - 0.9, 14.4)
        ..cubicTo(x + 1.4, 13.7, x + 2.5, 11.8, x + 2.5, 9.1)
        ..cubicTo(x + 2.5, 7.4, x + 1.5, 6.5, x, 6.5)
        ..close();
      canvas.drawPath(quote, cutout);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LyricsBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}
