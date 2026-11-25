import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../util/format.dart';
import '../util/json.dart';
import '../widgets/common.dart';

/// Cadre commun des écrans : tirer pour actualiser, état de chargement, bandeaux hors connexion / données anciennes.
class PageFrame extends StatelessWidget {
  final List<Widget> Function(BuildContext context, J data) builder;
  final bool listenCams;
  final Future<void> Function()? onRefresh;

  const PageFrame({super.key, required this.builder, this.listenCams = false, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final repo = scope.repo;
    return ListenableBuilder(
      listenable: listenCams ? Listenable.merge([repo, scope.cams]) : repo,
      builder: (context, _) {
        final data = repo.data;
        if (data == null) {
          if (repo.loading || repo.error == null) return const SkeletonPage();
          return _ErrorView(message: repo.error!, onRetry: repo.refresh);
        }
        final banners = <Widget>[];
        final g = repo.generatedAt;
        if (repo.offline) {
          banners.add(Banner2(
            icon: Icons.cloud_off_rounded,
            color: C.warn,
            text: '${repo.error}. Dernières données enregistrées : ${g == null ? 'date inconnue' : whenText(g)}.',
          ));
        } else if (repo.isStale && g != null) {
          banners.add(Banner2(
            icon: Icons.history_rounded,
            color: C.warn,
            text: 'Données du ${ddmm(g)} à ${hm(g)} : pas de mise à jour récente du serveur de données.',
          ));
        }
        final children = [...banners, ...builder(context, data)];
        return RefreshIndicator(
          color: C.blue,
          backgroundColor: C.card,
          onRefresh: onRefresh ?? repo.refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            itemCount: children.length,
            separatorBuilder: (_, __) => gap12,
            itemBuilder: (_, i) => children[i],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: C.muted),
          gap12,
          const Text('Aucune donnée disponible', style: T.mid),
          gap8,
          Text(message, style: T.sub, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')),
        ]),
      ),
    );
  }
}

/// Lignes de « valeur indisponible » cohérentes : texte ou widget NA.
Widget valueOrNA(String? v, {TextStyle style = T.value}) => v == null ? const NA() : Text(v, style: style);
