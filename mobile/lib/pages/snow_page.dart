import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/blocks.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'page_frame.dart';

const _periods = <(int, String)>[(7, '7 jours'), (30, '30 jours'), (90, '3 mois'), (365, '1 an')];

/// Neige : enneigement, neige fraîche, conditions, avalanche et graphiques.
class SnowPage extends StatefulWidget {
  const SnowPage({super.key});
  @override
  State<SnowPage> createState() => _SnowPageState();
}

class _SnowPageState extends State<SnowPage> {
  int freshPeriod = 30;
  int histPeriod = 30;
  final Set<String> hidden = {};

  @override
  Widget build(BuildContext context) {
    return PageFrame(builder: (context, data) {
      final sn = data['snow'];
      final fd = sn['fresh_days'];
      final village = FreshDay.fromJson(fd['village'].list);
      final summit = FreshDay.fromJson(fd['summit'].list, allFuture: true);
      final series = HistSeries.fromJson(sn['history'].list);
      return [
        if (sn['note'].s != null) Banner2(icon: Icons.info_outline_rounded, color: C.sun, text: sn['note'].s!),
        AppCard(title: 'Enneigement actuel', child: SnowMeasures(data)),
        AppCard(title: 'Neige fraîche', child: FreshSnowBlock(data)),
        AppCard(title: 'Conditions de neige', child: ConditionsBlock(data)),
        AppCard(title: "Danger d'avalanche", child: AvalancheBlock(data, size: 72)),
        AppCard(
          title: 'Neige fraîche quotidienne · Grimentz',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Seg<int>(options: _periods, value: freshPeriod, onChanged: (v) => setState(() => freshPeriod = v)),
            gap12,
            _Cumuls(fd['cumul_village'], '1577 m'),
            gap12,
            const Legend([(C.measured, 'Mesurée – MétéoSuisse Grimentz 1512 m'), (C.forecast, 'Prévue – Grimentz 1577 m')]),
            gap8,
            FreshChart(all: village, pastDays: freshPeriod, measured: true, forecastLabel: 'Prévue · Grimentz 1577 m'),
            const Text('Touchez ou glissez sur le graphique pour voir les valeurs.', style: T.small),
          ]),
        ),
        AppCard(
          title: 'Neige fraîche prévue · Corne de Sorebois 2895 m',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Cumuls(fd['cumul_summit'], '2895 m'),
            gap8,
            FreshChart(all: summit, pastDays: 1, measured: false, forecastLabel: 'Prévue · 2895 m', height: 190),
            const Text('Aucune station ne mesure la neige fraîche à cette altitude : prévision seulement.', style: T.small),
          ]),
        ),
        AppCard(
          title: "Historique de l'enneigement",
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Seg<int>(options: _periods, value: histPeriod, onChanged: (v) => setState(() => histPeriod = v)),
            gap8,
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in series)
                ToggleChip(
                  text: s.name,
                  color: s.color,
                  on: !hidden.contains(s.key),
                  onTap: () => setState(() => hidden.contains(s.key) ? hidden.remove(s.key) : hidden.add(s.key)),
                ),
            ]),
            gap12,
            HistoryChart(series: series, hidden: hidden, days: histPeriod),
            const Text(
              "Relevés officiels de la station (un par jour, conservés par le serveur de données) et hauteur de neige "
              "mesurée chaque jour par MétéoSuisse à Grimentz (1512 m). Une courbe s'interrompt quand aucun relevé n'existe ; "
              "le dernier relevé est prolongé jusqu'à aujourd'hui (14 jours au plus).",
              style: T.small,
            ),
          ]),
        ),
      ];
    });
  }
}

class _Cumuls extends StatelessWidget {
  final J c;
  final String alt;
  const _Cumuls(this.c, this.alt);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TileGrid(columns: 3, children: [
        for (final k in const [('24', '24 h'), ('48', '48 h'), ('168', '7 jours')])
          Tile(
            label: '${k.$2} à venir',
            value: c[k.$1].d == null ? null : '≈ ${fmt(c[k.$1].d, unit: 'cm')}',
            valueColor: C.snow,
            valueSize: 16,
          ),
      ]),
      const SizedBox(height: 4),
      Text('Neige prévue à $alt (estimation à partir des précipitations et températures MétéoSuisse)', style: T.small),
    ]);
  }
}
