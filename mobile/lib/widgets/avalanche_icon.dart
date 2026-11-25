import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Couleurs officielles de l'échelle européenne du danger d'avalanche (même rendu que l'application PC).
const Map<int, Color> kAvalancheColors = {
  1: Color(0xFF76C82B),
  2: Color(0xFFFFD60A),
  3: Color(0xFFFF9F0A),
  4: Color(0xFFFF6A1A),
  5: Color(0xFFC8141E),
};

const Map<int, Color> kAvalancheTextColors = {
  1: Color(0xFF8BD645),
  2: Color(0xFFFFD60A),
  3: Color(0xFFFF9F0A),
  4: Color(0xFFFF7A33),
  5: Color(0xFFF04B53),
};

/// Losange arrondi coloré avec symbole centré (✓, !, !!, ✗) ; sans degré : losange blanc à moitié rempli.
class AvalancheIcon extends StatelessWidget {
  final int? level;
  final double size;
  const AvalancheIcon(this.level, {super.key, this.size = 64});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _AvPainter(level)));
}

class _AvPainter extends CustomPainter {
  final int? level;
  _AvPainter(this.level);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const rect = Rect.fromLTWH(26, 26, 48, 48);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    void drawDiamond(Paint paint) {
      canvas.save();
      canvas.translate(50, 50);
      canvas.rotate(math.pi / 4);
      canvas.translate(-50, -50);
      canvas.drawRRect(rrect, paint);
      canvas.restore();
    }

    final lvl = level;
    if (lvl == null || !kAvalancheColors.containsKey(lvl)) {
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(0, 50, 100, 50));
      drawDiamond(Paint()..color = const Color(0xFFF4F6F8));
      canvas.restore();
      drawDiamond(Paint()
        ..color = const Color(0xFFF4F6F8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5);
      canvas.restore();
      return;
    }
    drawDiamond(Paint()..color = kAvalancheColors[lvl]!);
    final ink = lvl == 5 ? Colors.white : const Color(0xFF111111);
    final stroke = Paint()
      ..color = ink
      ..strokeWidth = 8.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = ink;
    switch (lvl) {
      case 1:
        canvas.drawPath(
            Path()
              ..moveTo(37, 50.5)
              ..lineTo(46, 59)
              ..lineTo(63, 40),
            stroke);
        break;
      case 2:
        canvas.drawLine(const Offset(50, 37), const Offset(50, 56), stroke);
        canvas.drawCircle(const Offset(50, 67), 5.3, fill);
        break;
      case 3:
        for (final x in [43.5, 56.5]) {
          canvas.drawLine(Offset(x, 37), Offset(x, 56), stroke);
          canvas.drawCircle(Offset(x, 67), 5.3, fill);
        }
        break;
      default:
        canvas.drawLine(const Offset(40, 40), const Offset(60, 60), stroke);
        canvas.drawLine(const Offset(60, 40), const Offset(40, 60), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AvPainter old) => old.level != level;
}
