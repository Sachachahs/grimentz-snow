import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/blocks.dart';
import '../widgets/common.dart';
import 'page_frame.dart';

/// Domaine skiable : ouverture, horaires officiels, remontées et pistes par station.
class DomainPage extends StatefulWidget {
  const DomainPage({super.key});
  @override
  State<DomainPage> createState() => _DomainPageState();
}

class _DomainPageState extends State<DomainPage> {
  String station = 'Grimentz';
  int kind = 0; // 0 remontées, 1 pistes

  @override
  Widget build(BuildContext context) {
    return PageFrame(builder: (context, data) {
      final d = data['domain'];
      if (d.isNull) return [const AppCard(title: 'Domaine skiable', child: NA())];
      final stations = d['stations'].map;
      final keys = stations.keys.toList();
      if (keys.isNotEmpty && !keys.contains(station)) station = keys.first;
      final st = stations[station] ?? J.empty;
      final fetched = fromEpoch(d['fetched_at'].d);
      return [
        OpenStatus(data),
        AppCard(
          title: 'Ouverture du domaine',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TileGrid(columns: 2, children: [
              _countTile(Icons.cable_rounded, 'Remontées ouvertes', d['lifts'], 'fermée'),
              _countTile(Icons.downhill_skiing_rounded, 'Pistes ouvertes', d['slopes'], 'fermée'),
              Tile(
                icon: Icons.straighten_rounded,
                iconColor: C.blue,
                label: 'Km de pistes',
                value: d['km_total'].d == null
                    ? null
                    : '${fmt(d['km_open'].d ?? 0, digits: 1)} / ${fmt(d['km_total'].d, unit: 'km')}',
                valueColor: (d['km_open'].d ?? 0) > 0 ? C.good : ((d['km_prep'].d ?? 0) > 0 ? C.warn : null),
                sub: d['km_prep'].d == null ? null : '${fmt(d['km_prep'].d, unit: 'km', digits: 1)} en préparation',
              ),
              Tile(
                icon: Icons.map_outlined,
                iconColor: C.blue,
                label: 'Domaine ouvert',
                value: d['pct_open'].d == null ? null : '${fmt(d['pct_open'].d)} %',
                valueColor: (d['pct_open'].d ?? 0) > 0 ? C.good : ((d['pct_prep'].d ?? 0) > 0 ? C.warn : null),
                sub: d['pct_prep'].d == null ? null : '${fmt(d['pct_prep'].d)} % en préparation',
              ),
            ]),
            if (fetched != null) ...[gap8, Text('Données officielles de la station · relevées ${whenText(fetched)}', style: T.small)],
          ]),
        ),
        AppCard(title: 'Horaires de la semaine', child: _Week(d)),
        if (keys.isNotEmpty)
          AppCard(
            title: 'Installations',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Seg<String>(
                options: [for (final k in keys) (k, k == 'Domaine' ? 'Autres' : k)],
                value: station,
                onChanged: (v) => setState(() => station = v),
              ),
              gap8,
              Seg<int>(
                options: [
                  (0, 'Remontées ${_count(st['lifts_count'])}'),
                  (1, 'Pistes ${_count(st['slopes_count'])}'),
                ],
                value: kind,
                onChanged: (v) => setState(() => kind = v),
              ),
              gap12,
              _FacilityList(kind == 0 ? st['lifts'].list : st['slopes'].list, slope: kind == 1),
            ]),
          ),
        AppCard(title: 'Fermetures liées à la météo', child: _Closures(d)),
        AppCard(title: 'Informations officielles', child: _Links(data)),
      ];
    });
  }

  String _count(J o) => o.isNull ? '' : '${o['open'].i ?? 0}/${o['total'].i ?? 0}';

  Widget _countTile(IconData icon, String label, J o, String closedWord) {
    if (o.isNull) return Tile(icon: icon, iconColor: C.blue, label: label, value: null);
    final open = o['open'].i ?? 0, prep = o['prep'].i ?? 0, closed = o['closed'].i ?? 0;
    return Tile(
      icon: icon,
      iconColor: C.blue,
      label: label,
      value: '$open / ${o['total'].i ?? 0}',
      valueColor: open > 0 ? C.good : (prep > 0 ? C.warn : C.bad),
      sub: '$closed $closedWord${closed > 1 ? 's' : ''} · ${prep > 0 ? '$prep en préparation' : 'aucune en préparation'}',
    );
  }
}

class _Week extends StatelessWidget {
  final J d;
  const _Week(this.d);

  @override
  Widget build(BuildContext context) {
    final week = d['week'].list;
    if (week.isEmpty) return const NA();
    Color col(String? k) => k == 'open' ? C.good : (k == 'cond' ? C.warn : C.bad);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var k = 0; k < week.length; k++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: k == 0 ? null : const Border(top: BorderSide(color: C.border, width: 0.6)),
          ),
          child: Row(children: [
            SizedBox(
              width: 120,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: week[k]['label'].s ?? '',
                    style: TextStyle(fontWeight: k == 0 ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                TextSpan(
                    text: parseLocal(week[k]['date'].s) == null ? '' : '  ${ddmm(parseLocal(week[k]['date'].s)!)}',
                    style: T.small),
              ])),
            ),
            Expanded(
              child: Text(
                week[k]['state'].s ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(color: col(week[k]['kind'].s), fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
            if ((week[k]['hours'].s ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(week[k]['hours'].s!, style: T.sub),
            ],
          ]),
        ),
      gap8,
      Text(
        [
          d['season'].s == null ? 'Calendrier officiel indisponible' : 'Calendrier officiel ${d['season'].s}',
          if (d['last_up'].s != null) 'dernière montée ${d['last_up'].s}',
          '* sous réserve d\'enneigement',
        ].join(' · '),
        style: T.small,
      ),
    ]);
  }
}

class _FacilityList extends StatelessWidget {
  final List<J> items;
  final bool slope;
  const _FacilityList(this.items, {required this.slope});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const NA(text: 'Aucune installation de ce type');
    return Column(children: [
      for (var k = 0; k < items.length; k++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            border: k == 0 ? null : const Border(top: BorderSide(color: C.border, width: 0.6)),
          ),
          child: _Facility(items[k], slope: slope),
        ),
    ]);
  }
}

class _Facility extends StatelessWidget {
  final J f;
  final bool slope;
  const _Facility(this.f, {required this.slope});

  @override
  Widget build(BuildContext context) {
    final state = f['state'].i;
    final col = state == 1 ? C.good : (state == 2 ? C.warn : C.bad);
    final details = <String>[
      if (slope) (f['type'].s ?? '').replaceFirst('Piste ', 'piste ') else (f['type'].s ?? ''),
      if (!slope && f['alt'].s != null) f['alt'].s!,
      if (slope && f['length_km'].d != null) fmt(f['length_km'].d, unit: 'km', digits: 1)!,
      if (f['remark'].s != null && f['remark'].s != f['state_label'].s) f['remark'].s!,
    ].where((e) => e.isNotEmpty).toList();
    final slopeColor = f['color'].s == null ? null : hexColor(f['color'].s);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: slope && slopeColor != null
            ? Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: slopeColor,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0x66FFFFFF), width: 0.8),
                ),
              )
            : Dot(col, size: 10),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            if (f['number'].s != null) TextSpan(text: '${f['number'].s}  ', style: T.small),
            TextSpan(text: f['name'].s ?? '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          ])),
          if (details.isNotEmpty) Text(details.join(' · '), style: T.small),
        ]),
      ),
      const SizedBox(width: 8),
      Text(f['state_label'].s ?? '', style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13)),
    ]);
  }
}

class _Closures extends StatelessWidget {
  final J d;
  const _Closures(this.d);
  @override
  Widget build(BuildContext context) {
    final c = d['closures'].list.map((e) => e.s).whereType<String>().toList();
    if (c.isEmpty) return const Text('Aucune fermeture liée à la météo signalée par la station.', style: T.sub);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final x in c)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 6), child: Dot(C.warn, size: 7)),
            const SizedBox(width: 8),
            Expanded(child: Text(x, style: T.body)),
          ]),
        ),
    ]);
  }
}

class _Links extends StatelessWidget {
  final J data;
  const _Links(this.data);

  @override
  Widget build(BuildContext context) {
    final l = data['links'];
    Widget link(IconData icon, String text, String? url) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(icon, color: C.blue),
          title: Text(text, style: T.body),
          trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: C.muted),
          enabled: url != null,
          onTap: () => openLink(context, url),
        );
    return Column(children: [
      link(Icons.map_outlined, 'Carte interactive officielle', l['map'].s),
      link(Icons.picture_as_pdf_outlined, 'Plan des pistes (PDF)', l['piste_map_pdf'].s),
      link(Icons.info_outline_rounded, 'Info live officielle', l['infolive'].s),
      link(Icons.schedule_rounded, 'Horaires et calendrier officiels', l['hours'].s),
    ]);
  }
}
