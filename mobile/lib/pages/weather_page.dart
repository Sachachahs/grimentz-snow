import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/weather_icon.dart';
import 'page_frame.dart';

/// Météo : MétéoSuisse uniquement (prévisions locales officielles et mesures).
class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});
  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  int point = 0;
  int range = 48;

  @override
  Widget build(BuildContext context) {
    return PageFrame(builder: (context, data) {
      final w = data['weather'];
      final pts = w['points'].list;
      if (pts.isEmpty) return [const AppCard(title: 'Météo', child: NA())];
      final p = pts[point.clamp(0, pts.length - 1).toInt()];
      final now = zurichNow().subtract(const Duration(hours: 1));
      final hours = HourPoint.fromJson(p['hourly'].list).where((h) => !h.t.isBefore(now)).toList();
      return [
        Seg<int>(
          options: [for (var i = 0; i < pts.length; i++) (i, '${pts[i]['name'].s ?? ''} ${pts[i]['elevation'].i ?? ''} m')],
          value: point,
          onChanged: (v) => setState(() => point = v),
        ),
        _NowCard(p),
        AppCard(title: 'Heure par heure', child: _HourStrip(hours.take(25).toList())),
        AppCard(
          title: 'Prévisions 7 jours',
          child: _Days(p),
        ),
        AppCard(
          title: 'Prévision détaillée',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Seg<int>(
              options: const [(24, '24 h'), (48, '48 h'), (120, '5 jours')],
              value: range,
              onChanged: (v) => setState(() => range = v),
            ),
            gap8,
            const Legend([(C.blue, 'Température'), (C.snow, 'Précipitations'), (Color(0x554D9BFF), 'Fourchette 10–90 %')]),
            gap8,
            ForecastChart(hours: hours.take(range).toList()),
          ]),
        ),
        _Evolene(w['evolene']),
        Text(
          'Source : MétéoSuisse (prévisions locales officielles, run ${w['run'].s == null ? 'inconnu' : hm(parseLocal(w['run'].s)!)}). '
          'La neige prévue est une estimation à partir des précipitations et des températures (1 mm ≈ 1 cm sous 0,5 °C).',
          style: T.small,
        ),
      ];
    });
  }
}

Color? _gustColor(double? g) => g == null ? null : (g >= 60 ? C.bad : (g >= 40 ? C.warn : null));

class _NowCard extends StatelessWidget {
  final J p;
  const _NowCard(this.p);

  @override
  Widget build(BuildContext context) {
    final c = p['current'];
    final t = c['temp'].d;
    final time = parseLocal(c['time'].s);
    return AppCard(
      title: 'Maintenant · ${p['name'].s ?? ''} ${p['elevation'].i ?? ''} m',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          WeatherIcon(c['code'].i, size: 72),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t == null ? '—' : '${fmt(t, digits: 1)}°',
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: tempColor(t), height: 1.05)),
              Text(c['desc'].s ?? '', style: T.body),
              if (time != null) Text('Prévision MétéoSuisse pour ${time.hour}h', style: T.small),
            ]),
          ),
        ]),
        gap12,
        TileGrid(columns: 3, children: [
          Tile(icon: Icons.air_rounded, label: 'Vent moyen', value: fmt(c['wind'].d, unit: 'km/h'), small: c['wind_dir'].s, valueSize: 16),
          Tile(
              icon: Icons.speed_rounded,
              label: 'Rafales',
              value: fmt(c['gust'].d, unit: 'km/h'),
              valueColor: _gustColor(c['gust'].d),
              valueSize: 16),
          Tile(
              icon: Icons.explore_outlined,
              label: 'Direction',
              value: c['wind_dir'].s,
              valueSize: 16),
          Tile(
              icon: Icons.water_drop_outlined,
              iconColor: C.blue,
              label: 'Précip. 1 h',
              value: fmt(c['precip'].d, unit: 'mm', digits: 1),
              sub: (c['snowfall'].d ?? 0) > 0 ? '≈ ${fmt(c['snowfall'].d, unit: 'cm', digits: 1)} de neige' : null,
              valueSize: 16),
          Tile(
              icon: Icons.umbrella_outlined,
              iconColor: C.blue,
              label: 'Prob. précip.',
              value: fmt(c['prob'].d, unit: '%'),
              small: '3 h',
              valueSize: 16),
          Tile(
              icon: Icons.wb_sunny_outlined,
              iconColor: C.sun,
              label: 'Soleil 1 h',
              value: fmt(c['sun_min'].d, unit: 'min'),
              valueSize: 16),
          Tile(
              icon: Icons.thermostat_rounded,
              iconColor: C.snow,
              label: 'Isotherme 0 °C',
              value: fmt(c['freezing'].d, unit: 'm'),
              valueSize: 16),
        ]),
      ]),
    );
  }
}

class _HourStrip extends StatelessWidget {
  final List<HourPoint> hours;
  const _HourStrip(this.hours);

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) return const NA();
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final h = hours[i];
          final first = i == 0;
          return Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: first ? C.blue.withValues(alpha: 0.12) : C.tile,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: first ? C.blue.withValues(alpha: 0.5) : C.border.withValues(alpha: 0.6)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(h.t.hour == 0 ? weekdayShort(h.t) : '${h.t.hour}h',
                  style: TextStyle(fontSize: 12, color: h.t.hour == 0 ? C.text : C.muted, fontWeight: FontWeight.w600)),
              WeatherIcon(h.code, size: 32),
              Text(h.temp == null ? '—' : '${fmt(h.temp)}°',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tempColor(h.temp))),
              Text(
                (h.snow ?? 0) > 0
                    ? '${fmt(h.snow, digits: 1)} cm'
                    : ((h.precip ?? 0) > 0 ? '${fmt(h.precip, digits: 1)} mm' : ' '),
                style: TextStyle(fontSize: 10.5, color: (h.snow ?? 0) > 0 ? C.snow : C.blue),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Days extends StatelessWidget {
  final J p;
  const _Days(this.p);

  @override
  Widget build(BuildContext context) {
    final days = p['days'].list;
    if (days.isEmpty) return const NA();
    final tmins = [for (final d in days) if (d['tmin'].d != null) d['tmin'].d!];
    final tmaxs = [for (final d in days) if (d['tmax'].d != null) d['tmax'].d!];
    final lo = tmins.isEmpty ? 0.0 : tmins.reduce((a, b) => a < b ? a : b);
    final hi = tmaxs.isEmpty ? 1.0 : tmaxs.reduce((a, b) => a > b ? a : b);
    return Column(children: [
      for (var k = 0; k < days.length; k++)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showDayDetail(context, p, k),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              SizedBox(
                width: 84,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_dayName(days[k]), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(parseLocal(days[k]['date'].s) == null ? '' : dayShort(parseLocal(days[k]['date'].s)!), style: T.small),
                ]),
              ),
              WeatherIcon(days[k]['code'].i, size: 34),
              const SizedBox(width: 8),
              SizedBox(
                width: 58,
                child: Text(
                  '❄ ${fmtCm(days[k]['snow'].d) ?? '—'}',
                  style: TextStyle(fontSize: 12.5, color: (days[k]['snow'].d ?? 0) > 0 ? C.snow : C.subtle),
                ),
              ),
              Text(days[k]['tmin'].d == null ? '—' : '${fmt(days[k]['tmin'].d)}°', style: T.sub),
              const SizedBox(width: 6),
              Expanded(child: _TempBar(days[k]['tmin'].d, days[k]['tmax'].d, lo, hi)),
              const SizedBox(width: 6),
              SizedBox(
                width: 34,
                child: Text(days[k]['tmax'].d == null ? '—' : '${fmt(days[k]['tmax'].d)}°',
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: C.subtle),
            ]),
          ),
        ),
      const SizedBox(height: 4),
      const Text('Touchez un jour pour le détail.', style: T.small),
    ]);
  }
}

String _dayName(J d) {
  final dt = parseLocal(d['date'].s);
  if (dt == null) return '';
  return sameDay(dt, zurichToday()) ? "Aujourd'hui" : weekday(dt);
}

class _TempBar extends StatelessWidget {
  final double? tmin, tmax;
  final double lo, hi;
  const _TempBar(this.tmin, this.tmax, this.lo, this.hi);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final span = (hi - lo).abs() < 0.1 ? 1.0 : hi - lo;
      final a = tmin == null ? 0.0 : ((tmin! - lo) / span).clamp(0.0, 1.0).toDouble();
      final b = tmax == null ? 1.0 : ((tmax! - lo) / span).clamp(0.0, 1.0).toDouble();
      return SizedBox(
        height: 6,
        child: Stack(children: [
          Container(decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(3))),
          Positioned(
            left: (w * a).clamp(0.0, w - 6 < 0 ? 0.0 : w - 6).toDouble(),
            width: (w * (b - a) < 6 ? 6.0 : w * (b - a)).clamp(0.0, w).toDouble(),
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(colors: [tempColor(tmin), tempColor(tmax)]),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Détail d'un jour : feuille glissante, on passe d'un jour à l'autre en balayant.
void showDayDetail(BuildContext context, J p, int index) {
  final days = p['days'].list;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.card,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => _DaySheet(p: p, days: days, initial: index),
  );
}

class _DaySheet extends StatefulWidget {
  final J p;
  final List<J> days;
  final int initial;
  const _DaySheet({required this.p, required this.days, required this.initial});
  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late final PageController ctrl = PageController(initialPage: widget.initial);
  late int page = widget.initial;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SizedBox(
      height: (h * 0.72).clamp(420.0, 640.0).toDouble(),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
              onPressed: page > 0 ? () => ctrl.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text('Prévision MétéoSuisse · ${widget.p['name'].s ?? ''} ${widget.p['elevation'].i ?? ''} m',
                  textAlign: TextAlign.center, style: T.sub),
            ),
            IconButton(
              onPressed: page < widget.days.length - 1
                  ? () => ctrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Expanded(
          child: PageView.builder(
            controller: ctrl,
            itemCount: widget.days.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (context, i) => _DayDetail(widget.days[i]),
          ),
        ),
      ]),
    );
  }
}

class _DayDetail extends StatelessWidget {
  final J d;
  const _DayDetail(this.d);

  @override
  Widget build(BuildContext context) {
    final dt = parseLocal(d['date'].s);
    final snow = d['snow'].d;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      Text(
        dt == null ? '' : '${sameDay(dt, zurichToday()) ? "Aujourd'hui · " : ''}${longDate(dt)}',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      gap12,
      Row(children: [
        WeatherIcon(d['code'].i, size: 84),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(capitalize(d['desc'].s ?? 'Description indisponible'), style: T.mid),
            const SizedBox(height: 6),
            Row(children: [
              Text(d['tmax'].d == null ? '—' : '${fmt(d['tmax'].d)}°',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: tempColor(d['tmax'].d))),
              const Text('  max   ', style: T.small),
              Text(d['tmin'].d == null ? '—' : '${fmt(d['tmin'].d)}°',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: tempColor(d['tmin'].d))),
              const Text('  min', style: T.small),
            ]),
          ]),
        ),
      ]),
      gap12,
      TileGrid(columns: 2, children: [
        Tile(
            icon: Icons.ac_unit_rounded,
            iconColor: C.snow,
            label: 'Neige fraîche',
            value: fmtCm(snow),
            valueColor: (snow ?? 0) > 0 ? C.snow : null,
            sub: 'estimation'),
        Tile(icon: Icons.umbrella_outlined, iconColor: C.snow, label: 'Risque de neige', value: d['risk'].s),
        Tile(
            icon: Icons.water_drop_outlined,
            iconColor: C.blue,
            label: 'Précipitations',
            value: fmt(d['precip'].d, unit: 'mm', digits: 1)),
        Tile(
            icon: Icons.height_rounded,
            iconColor: C.blue,
            label: 'Fourchette',
            value: d['q10'].d == null || d['q90'].d == null
                ? null
                : '${fmt(d['q10'].d, digits: 1)}–${fmt(d['q90'].d, unit: 'mm', digits: 1)}',
            sub: 'scénarios 10–90 %'),
        Tile(
            icon: Icons.speed_rounded,
            label: 'Rafales max',
            value: fmt(d['gust'].d, unit: 'km/h'),
            valueColor: _gustColor(d['gust'].d)),
        Tile(
            icon: Icons.explore_outlined,
            label: 'Direction du vent',
            value: d['gust_dir_txt'].s,
            sub: d['gust_dir'].d == null ? null : '${fmt(d['gust_dir'].d)}°'),
        Tile(icon: Icons.wb_sunny_outlined, iconColor: C.sun, label: 'Ensoleillement', value: fmt(d['sun_h'].d, unit: 'h', digits: 1)),
      ]),
      gap12,
      const Text('Source : prévision locale MétéoSuisse. Balayez pour changer de jour.', style: T.small),
    ]);
  }
}

class _Evolene extends StatelessWidget {
  final J e;
  const _Evolene(this.e);

  @override
  Widget build(BuildContext context) {
    if (e.isNull) return const AppCard(title: 'Mesures · Evolène / Villa 1825 m', child: NA());
    final t = parseLocal(e['time'].s);
    return AppCard(
      title: 'Mesures · Evolène / Villa 1825 m',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TileGrid(columns: 2, children: [
          Tile(icon: Icons.thermostat_rounded, iconColor: C.blue, label: 'Température', value: fmt(e['temp'].d, unit: '°C', digits: 1)),
          Tile(icon: Icons.thermostat_rounded, iconColor: C.snow, label: 'Ressenti', value: fmt(e['chill'].d, unit: '°C', digits: 1)),
          Tile(icon: Icons.water_drop_outlined, iconColor: C.blue, label: 'Humidité', value: fmt(e['hum'].d, unit: '%')),
          Tile(
            icon: Icons.air_rounded,
            label: 'Vent / rafales',
            value: e['wind'].d == null && e['gust'].d == null ? null : '${fmtOr(e['wind'].d)} / ${fmtOr(e['gust'].d, unit: 'km/h')}',
            small: e['dir'].s,
          ),
        ]),
        gap8,
        Text(
          'Station automatique MétéoSuisse (vallée voisine)${t == null ? '' : ' · mesure ${whenText(t)}'}',
          style: T.small,
        ),
      ]),
    );
  }
}
