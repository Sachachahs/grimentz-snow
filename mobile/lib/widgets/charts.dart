import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';

/// Graphiques tactiles : toucher ou glisser le doigt sur le graphique affiche la valeur du jour / de l'heure.

class TipLine {
  final Color? color;
  final String label;
  final String value;
  const TipLine(this.label, this.value, [this.color]);
}

class TipData {
  final String title;
  final List<TipLine> lines;
  const TipData(this.title, this.lines);
}

(double, double) niceScale(double maxV, {double minTop = 5}) {
  final m = math.max(minTop, maxV);
  final raw = m / 5;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  var step = 10 * mag;
  for (final k in [1, 2, 5, 10]) {
    if (raw <= k * mag + 1e-9) {
      step = k * mag;
      break;
    }
  }
  var top = (m / step).ceil() * step;
  if (top - maxV < step * 0.3) top += step;
  return (top, step);
}

void paintText(Canvas canvas, String text, Offset at,
    {double size = 11, Color color = C.muted, FontWeight weight = FontWeight.w400, TextAlign align = TextAlign.center}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = at.dx;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (align == TextAlign.right) dx -= tp.width;
  tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
}

/// Cadre commun : gestes, surlignage du créneau touché, infobulle.
class ChartShell extends StatefulWidget {
  final double height;
  final double padLeft;
  final double padRight;
  final int slots;
  final CustomPainter Function(int? selected) painter;
  final TipData? Function(int index) tip;

  const ChartShell({
    super.key,
    required this.height,
    required this.slots,
    required this.painter,
    required this.tip,
    this.padLeft = 34,
    this.padRight = 8,
  });

  @override
  State<ChartShell> createState() => _ChartShellState();
}

class _ChartShellState extends State<ChartShell> {
  int? sel;

  void _at(double x, double width, {bool toggle = false}) {
    final pw = width - widget.padLeft - widget.padRight;
    if (pw <= 0 || widget.slots <= 0) return;
    final i = ((x - widget.padLeft) / (pw / widget.slots)).floor();
    if (i < 0 || i >= widget.slots) {
      setState(() => sel = null);
      return;
    }
    setState(() => sel = (toggle && sel == i) ? null : i);
  }

  @override
  void didUpdateWidget(covariant ChartShell old) {
    super.didUpdateWidget(old);
    if (sel != null && sel! >= widget.slots) sel = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final tip = sel == null ? null : widget.tip(sel!);
      final pw = w - widget.padLeft - widget.padRight;
      final cx = sel == null ? 0.0 : widget.padLeft + (sel! + 0.5) * pw / math.max(1, widget.slots);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _at(d.localPosition.dx, w, toggle: true),
        onHorizontalDragStart: (d) => _at(d.localPosition.dx, w),
        onHorizontalDragUpdate: (d) => _at(d.localPosition.dx, w),
        onLongPressMoveUpdate: (d) => _at(d.localPosition.dx, w),
        child: SizedBox(
          height: widget.height,
          width: w,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: widget.painter(sel))),
            if (tip != null) _Tip(tip: tip, anchorX: cx, width: w),
          ]),
        ),
      );
    });
  }
}

class _Tip extends StatelessWidget {
  final TipData tip;
  final double anchorX;
  final double width;
  const _Tip({required this.tip, required this.anchorX, required this.width});

  @override
  Widget build(BuildContext context) {
    const tw = 210.0;
    var left = anchorX + 12;
    if (left + tw > width) left = math.max(0.0, anchorX - tw - 12);
    return Positioned(
      left: left,
      top: 4,
      width: tw,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xF70E1116),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.border),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tip.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.text)),
            const SizedBox(height: 4),
            for (final l in tip.lines)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (l.color != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(width: 8, height: 8, decoration: BoxDecoration(color: l.color, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(child: Text(l.label, style: const TextStyle(fontSize: 11.5, color: C.muted))),
                  const SizedBox(width: 6),
                  Text(l.value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: C.text)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Neige fraîche quotidienne : barres mesurées (bleu) et prévues (gris bleuté hachuré)
// ---------------------------------------------------------------------------------------------

class FreshDay {
  final DateTime day;
  final double? measured;
  final double? precip;
  final double? forecast;
  final double? forecastPrecip;
  final bool future;
  FreshDay(this.day, this.measured, this.precip, this.forecast, this.forecastPrecip, this.future);

  static List<FreshDay> fromJson(List<J> list, {bool allFuture = false}) {
    final out = <FreshDay>[];
    for (final x in list) {
      final d = parseLocal(x['d'].s);
      if (d == null) continue;
      out.add(FreshDay(d, x['m'].d, x['p'].d, x['f'].d, x['fp'].d, allFuture || x['fut'].b));
    }
    return out;
  }
}

class FreshChart extends StatelessWidget {
  final List<FreshDay> all;
  final int pastDays;
  final bool measured; // graphique avec mesures (Grimentz) ou prévision seule (Sorebois)
  final String forecastLabel;
  final double height;

  const FreshChart({
    super.key,
    required this.all,
    required this.pastDays,
    required this.measured,
    required this.forecastLabel,
    this.height = 230,
  });

  @override
  Widget build(BuildContext context) {
    final today = zurichToday();
    final start = today.subtract(Duration(days: pastDays - 1));
    final days = all.where((x) => !x.day.isBefore(start)).toList();
    if (days.isEmpty) return const SizedBox(height: 60, child: Center(child: Text(kNA, style: T.na)));
    return ChartShell(
      height: height,
      slots: days.length,
      painter: (sel) => _FreshPainter(days, today, measured, sel),
      tip: (i) {
        final x = days[i];
        final lines = <TipLine>[];
        if (measured && (!x.future || x.measured != null)) {
          lines.add(TipLine('Mesurée · Grimentz 1512 m', x.measured == null ? 'pas de mesure' : fmtCm(x.measured)!, C.measured));
          if (x.precip != null) lines.add(TipLine('Précipitations', fmt(x.precip, unit: 'mm', digits: 1)!));
        }
        if (x.future) {
          lines.add(TipLine(forecastLabel, x.forecast == null ? 'indisponible' : fmtCm(x.forecast)!, C.forecast));
          if (x.forecastPrecip != null) lines.add(TipLine('Précip. prévues', fmt(x.forecastPrecip, unit: 'mm', digits: 1)!));
        }
        return TipData(longDate(x.day), lines);
      },
    );
  }
}

class _FreshPainter extends CustomPainter {
  final List<FreshDay> days;
  final DateTime today;
  final bool measured;
  final int? sel;
  _FreshPainter(this.days, this.today, this.measured, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 8.0, t = 18.0, b = 26.0;
    final n = days.length;
    final pw = size.width - l - r, ph = size.height - t - b, dx = pw / n;
    final vals = <double>[
      for (final x in days) ...[if (x.measured != null) x.measured!, if (x.forecast != null) x.forecast!]
    ];
    final (top, step) = niceScale(vals.isEmpty ? 0.0 : vals.reduce(math.max));
    double y(double v) => t + ph - (v / top) * ph;
    double xc(int i) => l + (i + 0.5) * dx;
    final iT = days.indexWhere((x) => sameDay(x.day, today));

    if (iT >= 0 && measured) {
      canvas.drawRect(Rect.fromLTWH(l + iT * dx, t - 4, size.width - r - l - iT * dx, ph + 4),
          Paint()..color = C.forecast.withValues(alpha: 0.08));
    }
    for (var v = 0.0; v <= top + 1e-9; v += step) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)),
          Paint()..color = v == 0 ? const Color(0x5991A0B4) : const Color(0x0FFFFFFF));
      paintText(canvas, fmt(v)!, Offset(l - 6, y(v)), align: TextAlign.right);
    }
    if (sel != null) {
      canvas.drawRect(Rect.fromLTWH(l + sel! * dx, t - 4, dx, ph + 4), Paint()..color = const Color(0x12FFFFFF));
    }
    final bw = math.max(2.0, math.min(dx * 0.66, 24.0));
    final showVals = dx >= 14;
    final hatch = Paint()..color = C.forecast.withValues(alpha: 0.55);
    final hatchLine = Paint()
      ..color = const Color(0x8CC3CEDB)
      ..strokeWidth = 1.2;
    final outline = Paint()
      ..color = const Color(0xFF9AA9BB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final x = days[i];
      final both = x.measured != null && x.forecast != null && x.future;
      final w = both ? bw * 0.55 : bw;
      final cm = xc(i) - (both ? w / 2 + 1 : 0), cf = xc(i) + (both ? w / 2 + 1 : 0);
      if (!x.future || x.measured != null) {
        final m = x.measured;
        if (m == null) {
          if (!x.future && measured) canvas.drawCircle(Offset(xc(i), t + ph + 5), 1.4, Paint()..color = C.subtle);
        } else if (m <= 0) {
          canvas.drawRect(Rect.fromLTWH(cm - w / 2, y(0) - 2, w, 2), Paint()..color = C.measured.withValues(alpha: 0.5));
        } else {
          canvas.drawRRect(
              RRect.fromRectAndCorners(Rect.fromLTRB(cm - w / 2, y(m), cm + w / 2, y(0)),
                  topLeft: Radius.circular(math.min(4.0, w / 3)), topRight: Radius.circular(math.min(4.0, w / 3))),
              Paint()..color = C.measured);
          if (showVals) {
            paintText(canvas, fmt(m, digits: m < 1 ? 1 : 0)!, Offset(cm, y(m) - 8),
                color: const Color(0xFF9CC8FF), weight: FontWeight.w700);
          }
        }
      }
      if (x.future && x.forecast != null) {
        final f = x.forecast!;
        if (f <= 0) {
          canvas.drawRect(Rect.fromLTWH(cf - w / 2, y(0) - 2, w, 2), Paint()..color = C.forecast);
        } else {
          final rect = Rect.fromLTRB(cf - w / 2, y(f), cf + w / 2, y(0));
          final rr = RRect.fromRectAndCorners(rect,
              topLeft: Radius.circular(math.min(4.0, w / 3)), topRight: Radius.circular(math.min(4.0, w / 3)));
          canvas.drawRRect(rr, hatch);
          canvas.save();
          canvas.clipRRect(rr);
          for (var k = rect.left - rect.height; k < rect.right; k += 5) {
            canvas.drawLine(Offset(k, rect.bottom), Offset(k + rect.height, rect.top), hatchLine);
          }
          canvas.restore();
          canvas.drawRRect(rr, outline);
          if (showVals || !measured) {
            paintText(canvas, fmt(f, digits: f < 1 ? 1 : 0)!, Offset(cf, y(f) - 8),
                color: const Color(0xFFD5DEE8), weight: FontWeight.w700);
          }
        }
      }
    }
    if (iT > 0 && measured) {
      final xs = l + iT * dx;
      final p = Paint()
        ..color = const Color(0x80F1F3F5)
        ..strokeWidth = 1;
      for (var yy = t - 6; yy < t + ph; yy += 8) {
        canvas.drawLine(Offset(xs, yy), Offset(xs, math.min(yy + 4, t + ph)), p);
      }
    }
    final minPx = 52.0;
    const steps = [1, 2, 3, 5, 7, 14, 30, 61, 91];
    final stepD = steps.firstWhere((s) => s * dx >= minPx, orElse: () => 91);
    final ref = iT >= 0 ? iT : n - 1;
    for (var i = 0; i < n; i++) {
      if ((i - ref) % stepD != 0) continue;
      final isT = i == iT;
      paintText(canvas, isT ? 'Auj.' : dayShort(days[i].day), Offset(xc(i), size.height - 9),
          color: isT ? C.text : C.muted, weight: isT ? FontWeight.w700 : FontWeight.w400);
    }
  }

  @override
  bool shouldRepaint(covariant _FreshPainter old) => true;
}

// ---------------------------------------------------------------------------------------------
// Historique de l'enneigement : courbes coupées sur les trous, prolongées jusqu'à aujourd'hui
// ---------------------------------------------------------------------------------------------

class HistSeries {
  final String key;
  final String name;
  final Color color;
  final double gap;
  final List<(DateTime, double)> points;
  HistSeries(this.key, this.name, this.color, this.gap, this.points);

  static List<HistSeries> fromJson(List<J> list) => [
        for (final s in list)
          HistSeries(
            s['key'].s ?? '',
            s['name'].s ?? '',
            hexColor(s['color'].s),
            s['gap'].d ?? 1.5,
            [
              for (final p in s['points'].list)
                if (parseLocal(p[0].s) != null && p[1].d != null) (parseLocal(p[0].s)!, p[1].d!)
            ],
          )
      ];
}

class _HistView {
  final HistSeries s;
  final List<(int, double, DateTime)> pts; // index de jour, valeur, date
  final (int, double, DateTime)? held; // dernier relevé prolongé jusqu'à aujourd'hui
  _HistView(this.s, this.pts, this.held);
}

class HistoryChart extends StatelessWidget {
  final List<HistSeries> series;
  final Set<String> hidden;
  final int days;
  final double height;
  const HistoryChart({super.key, required this.series, required this.hidden, required this.days, this.height = 240});

  @override
  Widget build(BuildContext context) {
    final today = zurichToday();
    final t0 = today.subtract(Duration(days: days - 1));
    final views = <_HistView>[];
    for (final s in series.where((s) => !hidden.contains(s.key))) {
      final all = [for (final p in s.points) (daysBetween(t0, p.$1), p.$2, p.$1)];
      final last = all.isEmpty ? null : all.last;
      final held = (last != null && last.$1 < days - 1 && days - 1 - last.$1 <= 14) ? last : null;
      views.add(_HistView(s, all.where((p) => p.$1 >= 0 && p.$1 < days).toList(), held));
    }
    final hasVals = views.any((v) => v.pts.isNotEmpty || v.held != null);
    if (!hasVals) {
      return SizedBox(height: 90, child: Center(child: Text('Aucun relevé sur cette période', style: T.na)));
    }
    return ChartShell(
      height: height,
      slots: days,
      painter: (sel) => _HistPainter(views, days, sel),
      tip: (i) {
        final d = t0.add(Duration(days: i));
        final lines = <TipLine>[];
        for (final v in views) {
          final p = v.pts.where((q) => q.$1 == i).toList();
          if (p.isNotEmpty) {
            lines.add(TipLine(v.s.name, fmt(p.first.$2, unit: 'cm')!, v.s.color));
          } else if (v.held != null && i > v.held!.$1) {
            lines.add(TipLine('${v.s.name} (relevé du ${ddmm(v.held!.$3)})', fmt(v.held!.$2, unit: 'cm')!, v.s.color));
          } else {
            lines.add(TipLine(v.s.name, 'pas de relevé', v.s.color));
          }
        }
        return TipData(longDate(d), lines);
      },
    );
  }
}

class _HistPainter extends CustomPainter {
  final List<_HistView> views;
  final int span;
  final int? sel;
  _HistPainter(this.views, this.span, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 8.0, t = 14.0, b = 26.0;
    final pw = size.width - l - r, ph = size.height - t - b, dx = pw / span;
    double xOf(int i) => l + (i + 0.5) * dx;
    final vals = <double>[
      for (final v in views) ...[for (final p in v.pts) p.$2, if (v.held != null) v.held!.$2]
    ];
    final (top, step) = niceScale(vals.reduce(math.max), minTop: 10);
    double y(double v) => t + ph - (v / top) * ph;
    for (var v = 0.0; v <= top + 1e-9; v += step) {
      canvas.drawLine(Offset(l, y(v)), Offset(size.width - r, y(v)),
          Paint()..color = v == 0 ? const Color(0x5991A0B4) : const Color(0x0FFFFFFF));
      paintText(canvas, fmt(v)!, Offset(l - 6, y(v)), align: TextAlign.right);
    }
    if (sel != null) {
      canvas.drawRect(Rect.fromLTWH(l + sel! * dx, t, dx, ph), Paint()..color = const Color(0x12FFFFFF));
    }
    final radius = dx < 5 ? 2.0 : 3.2;
    for (final v in views) {
      final line = Paint()
        ..color = v.s.color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      var seg = <(int, double, DateTime)>[];
      void flush() {
        if (seg.length > 1) {
          final path = Path()..moveTo(xOf(seg.first.$1), y(seg.first.$2));
          for (final p in seg.skip(1)) {
            path.lineTo(xOf(p.$1), y(p.$2));
          }
          canvas.drawPath(path, line);
        }
        seg = [];
      }

      for (var k = 0; k < v.pts.length; k++) {
        if (k > 0 && v.pts[k].$1 - v.pts[k - 1].$1 > v.s.gap) flush();
        seg.add(v.pts[k]);
      }
      flush();
      final h = v.held;
      if (h != null) {
        final x0 = h.$1 >= 0 ? xOf(h.$1) : l;
        canvas.drawLine(Offset(x0, y(h.$2)), Offset(xOf(span - 1), y(h.$2)), line);
      }
      for (final p in v.pts) {
        canvas.drawCircle(Offset(xOf(p.$1), y(p.$2)), radius, Paint()..color = v.s.color);
        canvas.drawCircle(
            Offset(xOf(p.$1), y(p.$2)),
            radius,
            Paint()
              ..color = C.card
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
      }
    }
    const steps = [1, 2, 3, 5, 7, 14, 30, 61, 91];
    final stepD = steps.firstWhere((s) => s * dx >= 58, orElse: () => 91);
    final t0 = zurichToday().subtract(Duration(days: span - 1));
    for (var i = span - 1; i >= 0; i -= stepD) {
      final isT = i == span - 1;
      canvas.drawLine(Offset(xOf(i), t + ph), Offset(xOf(i), t + ph + 4), Paint()..color = const Color(0x6691A0B4));
      paintText(canvas, isT ? 'Auj.' : dayShort(t0.add(Duration(days: i))), Offset(xOf(i), size.height - 9),
          color: isT ? C.text : C.muted, align: isT ? TextAlign.right : TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(covariant _HistPainter old) => true;
}

// ---------------------------------------------------------------------------------------------
// Prévision détaillée : température (courbe) et précipitations (barres)
// ---------------------------------------------------------------------------------------------

class HourPoint {
  final DateTime t;
  final double? temp, precip, snow, q10, q90;
  final int? code;
  HourPoint(this.t, this.temp, this.precip, this.snow, this.q10, this.q90, this.code);

  static List<HourPoint> fromJson(List<J> list) => [
        for (final h in list)
          if (parseLocal(h['t'].s) != null)
            HourPoint(parseLocal(h['t'].s)!, h['temp'].d, h['precip'].d, h['snow'].d, h['q10'].d, h['q90'].d, h['code'].i)
      ];
}

class ForecastChart extends StatelessWidget {
  final List<HourPoint> hours;
  final double height;
  const ForecastChart({super.key, required this.hours, this.height = 240});

  @override
  Widget build(BuildContext context) {
    if (hours.where((h) => h.temp != null).isEmpty) {
      return const SizedBox(height: 60, child: Center(child: Text(kNA, style: T.na)));
    }
    return ChartShell(
      height: height,
      slots: hours.length,
      padRight: 36,
      painter: (sel) => _FcPainter(hours, sel),
      tip: (i) {
        final h = hours[i];
        return TipData('${weekday(h.t)} ${ddmm(h.t)} · ${two(h.t.hour)}h', [
          TipLine('Température', fmtOr(h.temp, unit: '°C', digits: 1), C.blue),
          if (h.q10 != null && h.q90 != null)
            TipLine('Fourchette', '${fmt(h.q10, digits: 1)} à ${fmt(h.q90, unit: '°C', digits: 1)}'),
          TipLine('Précipitations', fmtOr(h.precip, unit: 'mm', digits: 1), C.snow),
          if ((h.snow ?? 0) > 0) TipLine('Neige (estimation)', '≈ ${fmt(h.snow, unit: 'cm', digits: 1)}'),
        ]);
      },
    );
  }
}

class _FcPainter extends CustomPainter {
  final List<HourPoint> hs;
  final int? sel;
  _FcPainter(this.hs, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    const l = 34.0, r = 36.0, t = 14.0, b = 26.0;
    final n = hs.length;
    final pw = size.width - l - r, ph = size.height - t - b, dx = pw / n;
    final temps = [for (final h in hs) if (h.temp != null) h.temp!];
    var tmin = (temps.reduce(math.min) - 1).floorToDouble();
    var tmax = (temps.reduce(math.max) + 1).ceilToDouble();
    if (tmax - tmin < 6) {
      tmax += 3;
      tmin -= 3;
    }
    double yt(double v) => t + ph - ((v - tmin) / (tmax - tmin)) * ph;
    final pmax = math.max(2.0, hs.map((h) => h.precip ?? 0.0).reduce(math.max));
    double yp(double v) => t + ph - (v / pmax) * ph * 0.45;
    double xc(int i) => l + (i + 0.5) * dx;
    final tstep = (tmax - tmin) > 16 ? 5 : 2;
    for (var v = (tmin / tstep).ceil() * tstep; v <= tmax; v += tstep) {
      final yy = yt(v.toDouble());
      canvas.drawLine(Offset(l, yy), Offset(size.width - r, yy),
          Paint()..color = v == 0 ? const Color(0x59A9D1FF) : const Color(0x0FFFFFFF));
      paintText(canvas, '$v°', Offset(l - 6, yy), align: TextAlign.right);
    }
    paintText(canvas, fmt(pmax, unit: 'mm', digits: 1)!, Offset(size.width - r + 4, t + ph - ph * 0.45),
        color: C.snow, size: 10, align: TextAlign.left);
    if (sel != null) {
      canvas.drawRect(Rect.fromLTWH(l + sel! * dx, t, dx, ph), Paint()..color = const Color(0x12FFFFFF));
    }
    final bar = Paint()..color = C.snow.withValues(alpha: 0.55);
    for (var i = 0; i < n; i++) {
      final p = hs[i].precip ?? 0.0;
      if (p > 0) canvas.drawRect(Rect.fromLTRB(xc(i) - dx * 0.35, yp(p), xc(i) + dx * 0.35, yp(0)), bar);
      if (hs[i].t.hour == 0 && i > 0) {
        final xs = l + i * dx;
        final dp = Paint()..color = const Color(0x1FFFFFFF);
        for (var yy = t; yy < t + ph; yy += 7) {
          canvas.drawLine(Offset(xs, yy), Offset(xs, math.min(yy + 3, t + ph)), dp);
        }
      }
    }
    // bande d'incertitude (scénarios 10–90 %)
    final band = Path();
    var started = false;
    final upper = <Offset>[];
    for (var i = 0; i < n; i++) {
      final h = hs[i];
      if (h.q10 == null || h.q90 == null) continue;
      final p = Offset(xc(i), yt(h.q10!));
      if (!started) {
        band.moveTo(p.dx, p.dy);
        started = true;
      } else {
        band.lineTo(p.dx, p.dy);
      }
      upper.add(Offset(xc(i), yt(h.q90!)));
    }
    if (started && upper.length > 1) {
      for (final p in upper.reversed) {
        band.lineTo(p.dx, p.dy);
      }
      band.close();
      canvas.drawPath(band, Paint()..color = C.blue.withValues(alpha: 0.12));
    }
    final path = Path();
    var first = true;
    for (var i = 0; i < n; i++) {
      final v = hs[i].temp;
      if (v == null) continue;
      if (first) {
        path.moveTo(xc(i), yt(v));
        first = false;
      } else {
        path.lineTo(xc(i), yt(v));
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = C.blue
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    if (sel != null && hs[sel!].temp != null) {
      canvas.drawCircle(Offset(xc(sel!), yt(hs[sel!].temp!)), 4.5, Paint()..color = C.blue);
      canvas.drawCircle(
          Offset(xc(sel!), yt(hs[sel!].temp!)),
          4.5,
          Paint()
            ..color = C.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    final every = n <= 24 ? 4 : (n <= 48 ? 8 : 24);
    for (var i = 0; i < n; i++) {
      final h = hs[i].t;
      final show = n > 48 ? h.hour == 12 : h.hour % every == 0;
      if (!show) continue;
      final lab = n > 48 || h.hour == 0 ? '${weekdayShort(h)} ${h.day}' : '${h.hour}h';
      paintText(canvas, lab, Offset(xc(i), size.height - 9));
    }
  }

  @override
  bool shouldRepaint(covariant _FcPainter old) => true;
}
