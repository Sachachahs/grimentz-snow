import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/webcams.dart';
import '../theme.dart';
import '../util/json.dart';
import '../widgets/common.dart';
import 'page_frame.dart';

Color camColor(CamState s) => switch (s) {
      CamState.ok => C.good,
      CamState.old => C.warn,
      CamState.oldDay => C.bad,
      CamState.unknown => C.warn,
      CamState.none => C.subtle,
    };

/// Webcams officielles : liste, puis visionneuse plein écran (glisser pour changer, pincer pour zoomer).
class WebcamsPage extends StatelessWidget {
  const WebcamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return PageFrame(
      listenCams: true,
      onRefresh: () async {
        await Future.wait([scope.repo.refresh(), scope.cams.refreshAll(force: true)]);
      },
      builder: (context, data) {
        final cams = data['webcams'].list;
        if (cams.isEmpty) return [const AppCard(title: 'Webcams', child: NA())];
        return [
          for (var i = 0; i < cams.length; i++) _CamCard(index: i, cam: cams[i]),
          const Text(
            'Webcams officielles de la station (fournisseur trinum). Pastille : vert = image de moins de 30 min, '
            'orange = plus ancienne, rouge = image qui ne date pas du jour. Tirez vers le bas pour actualiser.',
            style: T.small,
          ),
        ];
      },
    );
  }
}

class _CamCard extends StatelessWidget {
  final int index;
  final J cam;
  const _CamCard({required this.index, required this.cam});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).cams;
    final shot = store.shots[index];
    final state = store.state(index);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => openViewer(context, index),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 190,
          child: Stack(fit: StackFit.expand, children: [
            if (shot != null)
              Hero(
                tag: 'cam$index',
                child: Image.memory(shot.bytes, fit: BoxFit.cover, gaplessPlayback: true),
              )
            else
              Container(
                color: C.tile,
                alignment: Alignment.center,
                child: store.isLoading(index)
                    ? const CircularProgressIndicator(strokeWidth: 2.4)
                    : Text(store.errors[index] ?? 'Image indisponible', style: T.na),
              ),
            if (store.isLoading(index) && shot != null)
              const Positioned(
                right: 10,
                top: 10,
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cam['name'].s ?? ''} · ${cam['altitude'].i ?? ''} m', style: T.mid),
                const SizedBox(height: 2),
                Row(children: [
                  Dot(camColor(state)),
                  const SizedBox(width: 6),
                  Text(store.timeText(index), style: T.sub),
                  if (shot != null && shot.fromCache) const Text(' · enregistrée', style: T.small),
                ]),
              ]),
            ),
            Text(cam['sector'].s ?? '', style: T.small),
          ]),
        ),
      ]),
    );
  }
}

void openViewer(BuildContext context, int index) {
  final scope = AppScope.of(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    pageBuilder: (_, __, ___) => AppScope(repo: scope.repo, cams: scope.cams, goTab: scope.goTab, child: _Viewer(initial: index)),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _Viewer extends StatefulWidget {
  final int initial;
  const _Viewer({required this.initial});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final PageController ctrl = PageController(initialPage: widget.initial);
  late int page = widget.initial;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.cams,
      builder: (context, _) {
        final cams = scope.cams.cams;
        final cam = page < cams.length ? cams[page] : J.empty;
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${cam['name'].s ?? ''} · ${cam['altitude'].i ?? ''} m',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Row(children: [
                Dot(camColor(scope.cams.state(page)), size: 8),
                const SizedBox(width: 6),
                Text(scope.cams.timeText(page), style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ]),
            actions: [
              IconButton(
                tooltip: 'Actualiser',
                onPressed: scope.cams.isLoading(page) ? null : () => scope.cams.refresh(page),
                icon: scope.cams.isLoading(page)
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: PageView.builder(
                controller: ctrl,
                physics: zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                itemCount: cams.length,
                onPageChanged: (i) => setState(() {
                  page = i;
                  zoomed = false;
                }),
                itemBuilder: (context, i) => _ZoomImage(
                  index: i,
                  cam: cams[i],
                  onZoom: (z) {
                    if (z != zoomed) setState(() => zoomed = z);
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(children: [
                  Text('${page + 1} / ${cams.length}', style: const TextStyle(color: C.muted)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Pincez pour zoomer · double-touchez pour agrandir · tournez le téléphone pour le panorama',
                        style: TextStyle(fontSize: 11.5, color: C.subtle)),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Image zoomable : image en cache affichée tout de suite, puis la version haute définition si le réseau le permet.
class _ZoomImage extends StatefulWidget {
  final int index;
  final J cam;
  final ValueChanged<bool> onZoom;
  const _ZoomImage({required this.index, required this.cam, required this.onZoom});
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final TransformationController tc = TransformationController();
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    tc.addListener(() => widget.onZoom(tc.value.getMaxScaleOnAxis() > 1.05));
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (tc.value.getMaxScaleOnAxis() > 1.05) {
      tc.value = Matrix4.identity();
    } else {
      final p = _doubleTap?.localPosition ?? Offset.zero;
      const s = 2.5;
      tc.value = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setEntry(0, 3, -p.dx * (s - 1))
        ..setEntry(1, 3, -p.dy * (s - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).cams;
    final shot = store.shots[widget.index];
    final hd = widget.cam['hd_url'].s;
    final low = shot == null ? null : Image.memory(shot.bytes, fit: BoxFit.contain, gaplessPlayback: true);
    Widget img;
    if (hd == null) {
      img = low ?? const Center(child: Text('Image indisponible', style: T.na));
    } else {
      img = Image.network(
        hd,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) =>
            frame == null && low != null ? low : child,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Stack(fit: StackFit.expand, children: [
            if (low != null) low else const SizedBox(),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ]);
        },
        errorBuilder: (context, _, __) => low ?? const Center(child: Text('Image indisponible', style: T.na)),
      );
    }
    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: tc,
        minScale: 1,
        maxScale: 8,
        child: Center(child: Hero(tag: 'cam${widget.index}', child: img)),
      ),
    );
  }
}
