import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import 'avalanche_icon.dart';
import 'common.dart';

/// Blocs partagés entre l'accueil et les pages détaillées.

/// Enneigement actuel : Grimentz (MétéoSuisse), bas et haut du domaine (station).
class SnowMeasures extends StatelessWidget {
  final J data;
  const SnowMeasures(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final ms = data['snow']['measures'].list;
    if (ms.isEmpty) return const NA();
    final mx = ms.map((m) => m['cm'].d ?? 0.0).fold<double>(0, math.max);
    return Column(children: [
      for (var k = 0; k < ms.length; k++) ...[
        if (k > 0) const Divider(height: 18, color: C.border),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ms[k]['name'].s ?? '', style: T.mid.copyWith(fontSize: 15)),
              Text(ms[k]['altitude'].s ?? 'altitude non publiée par la station', style: T.small),
              if (ms[k]['when'].s != null) Text(ms[k]['when'].s!, style: T.small),
            ]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              ms[k]['cm'].d == null
                  ? const NA(text: 'Indisponible')
                  : Text(fmt(ms[k]['cm'].d, unit: 'cm')!,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.snow)),
              const SizedBox(height: 6),
              Bar(ms[k]['cm'].d == null || mx <= 0 ? 0.0 : math.max(0.04, ms[k]['cm'].d! / mx)),
            ]),
          ),
        ]),
      ],
    ]);
  }
}

/// Neige fraîche 24 / 48 / 72 h et dernière chute de neige.
class FreshSnowBlock extends StatelessWidget {
  final J data;
  final bool showLast;
  const FreshSnowBlock(this.data, {super.key, this.showLast = true});

  @override
  Widget build(BuildContext context) {
    final f = data['snow']['fresh'].list;
    final last = data['snow']['last'];
    final srcs = {for (final x in f) if (x['src'].s != null) x['src'].s!}.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TileGrid(columns: 3, children: [
        for (final x in f)
          Tile(
            label: '${x['h'].i ?? ''} h',
            value: fmt(x['cm'].d, unit: 'cm'),
            valueColor: (x['cm'].d ?? 0) > 0 ? C.snow : C.text,
            sub: srcs.length > 1 ? x['src'].s : null,
          ),
      ]),
      if (srcs.length == 1) ...[gap8, Text('Source : ${srcs.first}', style: T.small)],
      if (showLast) ...[
        const Divider(height: 22, color: C.border),
        Row(children: [
          const Icon(Icons.ac_unit_rounded, size: 18, color: C.snow),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Dernière chute de neige', style: T.sub),
              last.isNull ? const NA() : Text(last['label'].s ?? '', style: T.mid),
            ]),
          ),
          if ((last['cm'].d ?? 0) > 0)
            Text(fmt(last['cm'].d, unit: 'cm')!, style: T.mid.copyWith(color: C.snow)),
        ]),
        const SizedBox(height: 4),
        const Text('Mesure MétéoSuisse · Grimentz 1512 m', style: T.small),
      ],
    ]);
  }
}

/// Danger d'avalanche : pictogramme, niveau, nom, date.
class AvalancheBlock extends StatelessWidget {
  final J data;
  final double size;
  final bool showSource;
  const AvalancheBlock(this.data, {super.key, this.size = 64, this.showSource = true});

  @override
  Widget build(BuildContext context) {
    final a = data['snow']['avalanche'];
    final lvl = a['level'].i;
    if (lvl == null) {
      return Row(children: [
        AvalancheIcon(null, size: size),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Aucun degré publié', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.muted)),
            if (showSource && a['source'].s != null) Text(a['source'].s!, style: T.small),
          ]),
        ),
      ]);
    }
    final col = kAvalancheTextColors[lvl] ?? C.text;
    return Row(children: [
      AvalancheIcon(lvl, size: size),
      const SizedBox(width: 10),
      Text('$lvl', style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w800, color: col, height: 1)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['name'].s ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: col)),
          Text(a['updated'].s != null ? 'Mise à jour : ${a['updated'].s}' : 'Date non publiée', style: T.sub),
          if (showSource && a['source'].s != null) Text('Source : ${a['source'].s}', style: T.small),
        ]),
      ),
    ]);
  }
}

/// Qualité de la neige et enneigement technique.
class ConditionsBlock extends StatelessWidget {
  final J data;
  const ConditionsBlock(this.data, {super.key});
  @override
  Widget build(BuildContext context) => TileGrid(columns: 2, children: [
        Tile(icon: Icons.grain_rounded, iconColor: C.snow, label: 'Qualité de la neige', value: data['snow']['quality'].s),
        Tile(icon: Icons.ac_unit_rounded, iconColor: C.snow, label: 'Enneigement technique', value: data['snow']['making'].s),
      ]);
}

/// Note « Conditions de ski » (indicateur estimatif, non officiel).
class ScoreBlock extends StatelessWidget {
  final J data;
  const ScoreBlock(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = data['score'];
    final score = s['score'].i;
    if (score == null) return const NA();
    final col = hexColor(s['color'].s);
    final reason = (s['reasons'][0].s ?? '').replaceFirst(RegExp(r'^[✓✗]\s*'), '');
    return Row(children: [
      SizedBox(
        width: 64,
        height: 64,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: score.clamp(0, 100) / 100,
              strokeWidth: 6,
              backgroundColor: C.border,
              color: col,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text('$score', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: col.withValues(alpha: 0.35)),
            ),
            child: Text(s['label'].s ?? '', style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(height: 6),
          Text(reason, style: T.sub, maxLines: 3, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
  }
}

/// Résumé d'ouverture du domaine.
class DomainSummary extends StatelessWidget {
  final J data;
  const DomainSummary(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = data['domain'];
    if (d.isNull) return const NA();
    final lifts = d['lifts'], slopes = d['slopes'];
    final open = (lifts['open'].i ?? 0) > 0;
    String? count(J o) => o.isNull ? null : '${o['open'].i ?? 0} / ${o['total'].i ?? 0}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OpenStatus(data),
      gap8,
      TileGrid(columns: 2, children: [
        Tile(
            icon: Icons.cable_rounded,
            iconColor: C.blue,
            label: 'Remontées ouvertes',
            value: count(lifts),
            valueColor: open ? C.good : null),
        Tile(
            icon: Icons.downhill_skiing_rounded,
            iconColor: C.blue,
            label: 'Pistes ouvertes',
            value: count(slopes),
            valueColor: (slopes['open'].i ?? 0) > 0 ? C.good : null),
      ]),
    ]);
  }
}

/// Bandeau « Ouvert / Fermé » avec prochaine ouverture officielle.
class OpenStatus extends StatelessWidget {
  final J data;
  const OpenStatus(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = data['domain'];
    final open = (d['lifts']['open'].i ?? 0) > 0;
    final nx = d['next_opening'];
    final hours = d['week'][0]['hours'].s;
    final col = open ? C.good : C.bad;
    String detail;
    if (open) {
      detail = hours != null ? 'Horaires du jour : $hours' : 'Remontées en service';
    } else if (nx.exists) {
      final sectors = nx['sectors'].list.map((e) => e.s ?? '').where((e) => e.isNotEmpty).join(' + ');
      detail = 'Prochaine ouverture : ${nx['label'].s ?? ''}${nx['cond'].b ? '*' : ''}${sectors.isEmpty ? '' : ' · $sectors'}';
    } else {
      detail = 'Prochaine ouverture non publiée';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Dot(col, size: 11),
        const SizedBox(width: 10),
        Text(open ? 'Station ouverte' : 'Station fermée',
            style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(width: 10),
        Expanded(child: Text(detail, style: T.sub, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
