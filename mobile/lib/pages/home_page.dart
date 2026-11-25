import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/blocks.dart';
import '../widgets/common.dart';
import '../widgets/weather_icon.dart';
import 'page_frame.dart';

/// Accueil : l'essentiel d'un coup d'œil.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return PageFrame(
      listenCams: true,
      onRefresh: () async {
        await Future.wait([scope.repo.refresh(), scope.cams.refreshAll()]);
      },
      builder: (context, data) => [
        _Hero(data),
        _CurrentConditions(data),
        AppCard(title: 'Enneigement', child: SnowMeasures(data)),
        AppCard(title: 'Neige fraîche', child: FreshSnowBlock(data)),
        AppCard(
          title: "Danger d'avalanche",
          onTap: () => scope.goTab(1),
          child: AvalancheBlock(data, size: 58, showSource: false),
        ),
        AppCard(
          title: 'Domaine skiable',
          trailing: const _More(),
          onTap: () => scope.goTab(4),
          child: DomainSummary(data),
        ),
        AppCard(title: 'Conditions de ski (estimation)', child: ScoreBlock(data)),
      ],
    );
  }
}

class _More extends StatelessWidget {
  const _More();
  @override
  Widget build(BuildContext context) =>
      const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Détails', style: TextStyle(color: C.blue, fontSize: 13, fontWeight: FontWeight.w600)),
        Icon(Icons.chevron_right_rounded, color: C.blue, size: 18),
      ]);
}

/// En-tête : dernière image de la webcam de Bendolla (Grimentz), nom de la station, date.
class _Hero extends StatelessWidget {
  final J data;
  const _Hero(this.data);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    const camIndex = 2; // Bendolla (Grimentz)
    final shot = scope.cams.shots[camIndex];
    return GestureDetector(
      onTap: () => scope.goTab(3),
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (shot != null)
            Image.memory(shot.bytes, fit: BoxFit.cover, gaplessPlayback: true)
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF26364A), C.card]),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xD9101216)],
                stops: [0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(data['station']['name'].s ?? 'Grimentz-Zinal',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(data['station']['region'].s ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFFD0D8E2))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0x99101216), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  shot != null ? 'Bendolla · ${scope.cams.timeText(camIndex).replaceFirst('Image de ', '')}' : longDate(zurichNow()),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Conditions actuelles à Grimentz et à la Corne de Sorebois (prévision MétéoSuisse de l'heure en cours).
class _CurrentConditions extends StatelessWidget {
  final J data;
  const _CurrentConditions(this.data);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final w = data['weather'];
    final pts = w['points'].list;
    if (pts.isEmpty) return const AppCard(title: 'Conditions actuelles', child: NA());
    final village = pts[0]['current'];
    final run = parseLocal(w['run'].s);
    final fetched = fromEpoch(w['fetched_at'].d);
    return AppCard(
      title: 'Conditions actuelles',
      trailing: const _More(),
      onTap: () => scope.goTab(2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var k = 0; k < pts.length && k < 2; k++) ...[
              if (k > 0) const VerticalDivider(width: 20, color: C.border),
              Expanded(child: _PointNow(pts[k])),
            ],
          ]),
        ),
        gap12,
        TileGrid(columns: 3, children: [
          Tile(
              icon: Icons.air_rounded,
              label: 'Vent',
              value: fmt(village['wind'].d, unit: 'km/h'),
              small: village['wind_dir'].s,
              valueSize: 16),
          Tile(
              icon: Icons.speed_rounded,
              label: 'Rafales',
              value: fmt(village['gust'].d, unit: 'km/h'),
              valueColor: _gustColor(village['gust'].d),
              valueSize: 16),
          Tile(
              icon: Icons.water_drop_outlined,
              iconColor: C.blue,
              label: 'Précip. 1 h',
              value: fmt(village['precip'].d, unit: 'mm', digits: 1),
              valueSize: 16),
        ]),
        gap8,
        Text(
          [
            'Vent et précipitations : Grimentz',
            if (village['time'].s != null) 'prévision pour ${parseLocal(village['time'].s)!.hour}h',
            if (run != null) 'run MétéoSuisse ${hm(run)}',
            if (fetched != null) 'mis à jour ${whenText(fetched)}',
          ].join(' · '),
          style: T.small,
        ),
      ]),
    );
  }
}

Color? _gustColor(double? g) {
  if (g == null) return null;
  if (g >= 60) return C.bad;
  if (g >= 40) return C.warn;
  return null;
}

class _PointNow extends StatelessWidget {
  final J p;
  const _PointNow(this.p);

  @override
  Widget build(BuildContext context) {
    final c = p['current'];
    final t = c['temp'].d;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${p['name'].s ?? ''} · ${p['elevation'].i ?? ''} m',
          style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Row(children: [
        WeatherIcon(c['code'].i, size: 40),
        const SizedBox(width: 6),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(t == null ? '—' : '${fmt(t, digits: 1)}°',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: tempColor(t))),
          ),
        ),
      ]),
      const SizedBox(height: 2),
      Text(c['desc'].s ?? '', style: T.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      Text('Rafales ${fmtOr(c['gust'].d, unit: 'km/h')}', style: T.small),
    ]);
  }
}
