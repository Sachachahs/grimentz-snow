import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/config.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/common.dart';

/// Plus : cartes et liens officiels, activité récente, état des sources, note détaillée, réglages, à propos.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final repo = scope.repo;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Plus', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final data = repo.data ?? J.empty;
          final l = data['links'];
          Widget link(IconData icon, String text, String? url) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: C.blue),
                title: Text(text, style: T.body),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: C.muted),
                enabled: url != null,
                onTap: () => openLink(context, url),
              );
          return ListView(padding: const EdgeInsets.all(14), children: [
            AppCard(
              title: 'Cartes et informations officielles',
              child: Column(children: [
                link(Icons.map_outlined, 'Carte interactive du domaine', l['map'].s),
                link(Icons.picture_as_pdf_outlined, 'Plan des pistes 2025-26 (PDF)', l['piste_map_pdf'].s),
                link(Icons.info_outline_rounded, 'Info live (remontées, pistes)', l['infolive'].s),
                link(Icons.schedule_rounded, 'Horaires des remontées', l['hours'].s),
                link(Icons.photo_camera_outlined, 'Page des webcams officielles', l['webcams'].s),
                link(Icons.public_rounded, 'Site officiel Grimentz-Zinal', l['site'].s),
                link(Icons.cloud_outlined, 'MétéoSuisse', l['meteoswiss'].s),
              ]),
            ),
            gap12,
            AppCard(title: 'Activité récente', child: _Events(repo.events)),
            gap12,
            AppCard(title: 'Conditions de ski · détail de la note', child: _ScoreDetail(data)),
            gap12,
            AppCard(title: 'État des données', child: _Status(data)),
            gap12,
            AppCard(
              title: 'Notifications',
              child: const Text(
                'Les alertes (forte chute de neige, changement du danger d\'avalanche, ouverture de la station, '
                'forte chute de neige prévue) sont déjà détectées par le serveur de données et listées ci-dessus '
                'dans « Activité récente ». Les notifications push sur le téléphone pourront être activées dans une '
                'prochaine version.',
                style: T.sub,
              ),
            ),
            gap12,
            AppCard(
              title: 'Source des données',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(repo.dataUrl.isEmpty ? 'Non configurée' : repo.dataUrl, style: T.small),
                gap8,
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _editUrl(context),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                ),
              ]),
            ),
            gap12,
            const AppCard(
              title: 'À propos',
              child: Text(
                '$kAppName $kAppVersion\n\n'
                'Météo : exclusivement MétéoSuisse (Open Government Data). Enneigement, remontées, pistes et danger '
                "d'avalanche : données officielles de la station (Info live, valdanniviers.ch). Webcams : images "
                'officielles (trinum).\n\n'
                "Aucune donnée n'est inventée : une valeur absente est affichée « Donnée indisponible ». Hors connexion, "
                "les dernières données enregistrées restent consultables avec leur date. La note « Conditions de ski » "
                "est un indicateur estimatif, non officiel. Heures affichées : heure suisse.",
                style: T.sub,
              ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _editUrl(BuildContext context) async {
    final repo = AppScope.of(context).repo;
    final ctrl = TextEditingController(text: repo.dataUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.card,
        title: const Text('Adresse des données'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://raw.githubusercontent.com/…/data/data.json'),
          maxLines: 3,
          minLines: 1,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (url != null) await repo.setDataUrl(url);
  }
}

class _Events extends StatelessWidget {
  final List<J> events;
  const _Events(this.events);

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Text('Aucun événement récent.', style: T.sub);
    final recent = events.reversed.take(12).toList();
    return Column(children: [
      for (final e in recent)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(_icon(e['type'].s), color: C.sun),
          title: Text(e['title'].s ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [e['body'].s ?? '', if (parseLocal(e['at'].s) != null) whenText(parseLocal(e['at'].s)!)].join(' · '),
            style: T.small,
          ),
        ),
    ]);
  }

  IconData _icon(String? t) => switch (t) {
        'avalanche' => Icons.warning_amber_rounded,
        'opening' => Icons.downhill_skiing_rounded,
        'fresh_snow' => Icons.ac_unit_rounded,
        'heavy_forecast' => Icons.ac_unit_outlined,
        _ => Icons.notifications_none_rounded,
      };
}

class _ScoreDetail extends StatelessWidget {
  final J data;
  const _ScoreDetail(this.data);

  @override
  Widget build(BuildContext context) {
    final s = data['score'];
    if (s['score'].isNull) return const NA();
    final factors = s['factors'].list;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${s['score'].i} / 100 · ${s['label'].s ?? ''}',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: hexColor(s['color'].s))),
      gap8,
      for (final f in factors)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(f['name'].s ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${fmtOr(f['points'].d)} / ${fmtOr(f['max'].d)}', style: T.sub),
            ]),
            const SizedBox(height: 4),
            Bar((f['max'].d ?? 0) > 0 ? (f['points'].d ?? 0.0) / f['max'].d! : 0.0, color: C.blue),
            if (f['detail'].s != null) ...[const SizedBox(height: 2), Text(f['detail'].s!, style: T.small)],
          ]),
        ),
      const Text('Indicateur estimatif calculé à partir des données officielles, non officiel.', style: T.small),
    ]);
  }
}

class _Status extends StatelessWidget {
  final J data;
  const _Status(this.data);

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final st = data['sources_status'];
    final g = repo.generatedAt;
    Widget row(String name, bool? ok, String detail) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Dot(ok == null ? C.subtle : (ok ? C.good : C.bad), size: 8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$name  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: detail, style: T.small),
              ])),
            ),
          ]),
        );
    final ms = st['meteoswiss'];
    final sta = st['station'];
    final cams = st['webcams'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row('Serveur de données', g != null, g == null ? 'aucune donnée' : 'publication ${whenText(g)}'),
      row('MétéoSuisse', ms.isNull ? null : ms['ok'].b,
          ms['ok'].b ? 'run ${parseLocal(ms['run'].s) == null ? '' : hm(parseLocal(ms['run'].s)!)}' : (ms['error'].s ?? 'indisponible')),
      if (repo.stationDirect && repo.station != null)
        row('Station (Info live)', repo.stationError == null,
            'lue directement par le téléphone ${whenText(fromEpoch(repo.station!.fetchedAt)!)}${repo.stationError == null ? '' : ' (${repo.stationError})'}')
      else
        row('Station (Info live)', sta.isNull ? null : sta['ok'].b,
            sta['ok'].b ? 'à jour' : (repo.stationError ?? sta['error'].s ?? 'indisponible')),
      row('Webcams', cams.isNull ? null : (cams['ok'].i ?? 0) > 0, '${cams['ok'].i ?? 0} / ${cams['total'].i ?? 0} disponibles'),
      row('Téléphone', repo.error == null, repo.error ?? (repo.downloadedAt == null ? '' : 'téléchargé ${whenText(repo.downloadedAt!)}')),
    ]);
  }
}
