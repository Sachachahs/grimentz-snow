import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pictogramme météo dessiné, d'après le code officiel MétéoSuisse (1–42 jour, 101–142 nuit).
///
/// Le code détermine : soleil/lune, couverture nuageuse, type de précipitations, orage.
class WeatherIcon extends StatelessWidget {
  final int? code;
  final double size;
  const WeatherIcon(this.code, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    if (code == null) return SizedBox(width: size, height: size);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WxPainter(code!)),
    );
  }
}

enum _Sky { clear, mostly, partly, cloudy, overcast, high, stratus, fog }

enum _Precip { none, rain, sleet, snow }

class _Wx {
  final _Sky sky;
  final _Precip precip;
  final int amount; // 1 faible, 2 modéré, 3 fort
  final bool thunder;
  final bool night;
  const _Wx(this.sky, this.precip, this.amount, this.thunder, this.night);

  factory _Wx.of(int code) {
    final night = code > 100;
    final c = night ? code - 100 : code;
    _Sky sky;
    if (c == 1) {
      sky = _Sky.clear;
    } else if ([2, 29, 30, 31].contains(c)) {
      sky = _Sky.mostly;
    } else if ([3, 6, 7, 8, 12, 13, 32, 36, 37].contains(c)) {
      sky = _Sky.partly;
    } else if ([4, 9, 10, 11, 38, 39, 41].contains(c)) {
      sky = _Sky.cloudy;
    } else if (c == 26) {
      sky = _Sky.high;
    } else if (c == 27) {
      sky = _Sky.stratus;
    } else if (c == 28) {
      sky = _Sky.fog;
    } else {
      sky = _Sky.overcast;
    }
    var precip = _Precip.none;
    if ([6, 9, 14, 17, 20, 29, 32, 33, 38].contains(c)) precip = _Precip.rain;
    if ([7, 10, 15, 18, 21, 31].contains(c)) precip = _Precip.sleet;
    if ([8, 11, 16, 19, 22, 30, 34, 37, 39, 42].contains(c)) precip = _Precip.snow;
    final thunder = [12, 13, 23, 24, 25, 36, 37, 38, 39, 40, 41, 42].contains(c);
    var amount = 2;
    if ([6, 7, 8, 14, 15, 16, 29, 30, 31].contains(c)) amount = 1;
    if ([20, 21, 22, 33, 34].contains(c)) amount = 3;
    return _Wx(sky, precip, amount, thunder, night);
  }
}

class _WxPainter extends CustomPainter {
  final int code;
  _WxPainter(this.code);

  static const sunColor = Color(0xFFFFC83D);
  static const moonColor = Color(0xFFE3E9F2);
  static const cloudLight = Color(0xFFDCE2EA);
  static const cloudDark = Color(0xFF9DA9B8);
  static const rainColor = Color(0xFF4D9BFF);
  static const snowColor = Color(0xFFEAF6FF);
  static const boltColor = Color(0xFFFFD43B);

  @override
  void paint(Canvas canvas, Size size) {
    final w = _Wx.of(code);
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);

    final hasPrecip = w.precip != _Precip.none || w.thunder;
    final cloudTop = hasPrecip ? 8.0 : 12.0;

    switch (w.sky) {
      case _Sky.clear:
        _body(canvas, const Offset(24, 24), 10, w.night, rays: !w.night);
        break;
      case _Sky.mostly:
        _body(canvas, const Offset(19, 18), 9, w.night, rays: !w.night);
        _cloud(canvas, Rect.fromLTWH(18, cloudTop + 14, 26, 14), cloudLight);
        break;
      case _Sky.partly:
        _body(canvas, const Offset(17, 16), 9, w.night, rays: !w.night);
        _cloud(canvas, Rect.fromLTWH(9, cloudTop + 9, 34, 18), cloudLight);
        break;
      case _Sky.cloudy:
        _cloud(canvas, Rect.fromLTWH(6, cloudTop + 6, 36, 19), cloudLight);
        break;
      case _Sky.overcast:
        _cloud(canvas, Rect.fromLTWH(14, cloudTop + 1, 28, 15), cloudDark);
        _cloud(canvas, Rect.fromLTWH(5, cloudTop + 7, 36, 19), cloudLight);
        break;
      case _Sky.high:
        _body(canvas, const Offset(18, 18), 9, w.night, rays: !w.night);
        final p = Paint()
          ..color = cloudLight
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(14, 30), const Offset(40, 30), p);
        canvas.drawLine(const Offset(20, 36), const Offset(44, 36), p);
        break;
      case _Sky.stratus:
        _cloud(canvas, Rect.fromLTWH(5, 14, 38, 16), cloudDark);
        final p = Paint()
          ..color = cloudLight
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(8, 35), const Offset(40, 35), p);
        break;
      case _Sky.fog:
        final p = Paint()
          ..color = cloudLight
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;
        for (var k = 0; k < 4; k++) {
          final y = 14.0 + k * 7;
          canvas.drawLine(Offset(k.isEven ? 7 : 11, y), Offset(k.isEven ? 37 : 41, y), p);
        }
        break;
    }

    final baseY = cloudTop + 29;
    if (w.thunder) _bolt(canvas, Offset(w.precip == _Precip.none ? 24 : 27, baseY - 1));
    final xs = w.amount == 1 ? [18.0, 30.0] : (w.amount == 2 ? [14.0, 24.0, 34.0] : [12.0, 20.0, 28.0, 36.0]);
    final shown = w.thunder ? xs.where((x) => (x - 27).abs() > 5).toList() : xs;
    for (var k = 0; k < shown.length; k++) {
      final x = shown[k];
      final y = baseY + (k.isOdd ? 4 : 0);
      switch (w.precip) {
        case _Precip.rain:
          _drop(canvas, Offset(x, y));
          break;
        case _Precip.snow:
          _flake(canvas, Offset(x, y + 2));
          break;
        case _Precip.sleet:
          if (k.isEven) {
            _drop(canvas, Offset(x, y));
          } else {
            _flake(canvas, Offset(x, y + 2));
          }
          break;
        case _Precip.none:
          break;
      }
    }
    canvas.restore();
  }

  void _body(Canvas canvas, Offset c, double r, bool night, {bool rays = true}) {
    if (night) {
      final outer = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      final inner = Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.55, -r * 0.35), radius: r * 0.85));
      canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), Paint()..color = moonColor);
      return;
    }
    canvas.drawCircle(c, r * 0.72, Paint()..color = sunColor);
    if (!rays) return;
    final p = Paint()
      ..color = sunColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.98), c + d * (r * 1.35), p);
    }
  }

  void _cloud(Canvas canvas, Rect r, Color color) {
    final p = Paint()..color = color;
    final h = r.height;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top + h * 0.42, r.width, h * 0.58), Radius.circular(h * 0.29)))
      ..addOval(Rect.fromCircle(center: Offset(r.left + r.width * 0.34, r.top + h * 0.52), radius: h * 0.38))
      ..addOval(Rect.fromCircle(center: Offset(r.left + r.width * 0.6, r.top + h * 0.42), radius: h * 0.48));
    // léger contour pour détacher le nuage du soleil
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF191D24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    canvas.drawPath(path, p);
  }

  void _drop(Canvas canvas, Offset o) {
    final p = Paint()
      ..color = rainColor
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(o, o + const Offset(-2.2, 5.5), p);
  }

  void _flake(Canvas canvas, Offset o) {
    final p = Paint()
      ..color = snowColor
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 3; k++) {
      final a = k * math.pi / 3 + math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a)) * 3.4;
      canvas.drawLine(o - d, o + d, p);
    }
  }

  void _bolt(Canvas canvas, Offset top) {
    final path = Path()
      ..moveTo(top.dx + 1, top.dy - 3)
      ..lineTo(top.dx - 5, top.dy + 6)
      ..lineTo(top.dx - 0.5, top.dy + 6)
      ..lineTo(top.dx - 3, top.dy + 13)
      ..lineTo(top.dx + 5, top.dy + 3)
      ..lineTo(top.dx + 0.5, top.dy + 3)
      ..lineTo(top.dx + 3, top.dy - 3)
      ..close();
    canvas.drawPath(path, Paint()..color = boltColor);
  }

  @override
  bool shouldRepaint(covariant _WxPainter old) => old.code != code;
}
