import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'data/config.dart';
import 'data/repository.dart';
import 'data/webcams.dart';
import 'pages/domain_page.dart';
import 'pages/home_page.dart';
import 'pages/more_page.dart';
import 'pages/snow_page.dart';
import 'pages/weather_page.dart';
import 'pages/webcams_page.dart';
import 'theme.dart';
import 'util/format.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final repo = DataRepository();
  final cams = WebcamStore(repo);
  runApp(GrimentzSnowApp(repo: repo, cams: cams));
  repo.init();
  cams.restore();
}

class GrimentzSnowApp extends StatelessWidget {
  final DataRepository repo;
  final WebcamStore cams;
  const GrimentzSnowApp({super.key, required this.repo, required this.cams});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(repo: repo, cams: cams),
    );
  }
}

class Shell extends StatefulWidget {
  final DataRepository repo;
  final WebcamStore cams;
  const Shell({super.key, required this.repo, required this.cams});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;

  static const _titles = ['Grimentz-Zinal', 'Neige', 'Météo', 'Webcams', 'Domaine skiable'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'application : actualisation si les données ont plus de 2 minutes.
    if (state == AppLifecycleState.resumed) {
      final d = widget.repo.downloadedAt;
      if (d == null || zurichNow().difference(d).inMinutes >= 2) widget.repo.refresh();
      if (tab == 3 || tab == 0) widget.cams.refreshAll();
    }
  }

  void goTab(int i) {
    setState(() => tab = i);
    if (i == 3 || i == 0) widget.cams.refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([widget.repo.refresh(), widget.cams.refreshAll(force: tab == 3)]);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repo: widget.repo,
      cams: widget.cams,
      goTab: goTab,
      child: ListenableBuilder(
        listenable: widget.repo,
        builder: (context, _) {
          final repo = widget.repo;
          return Scaffold(
            appBar: AppBar(
              backgroundColor: C.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 16,
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titles[tab], style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: C.text)),
                Text(_subtitle(repo), style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: repo.loading ? null : _refreshAll,
                  icon: repo.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Plus',
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AppScope(repo: widget.repo, cams: widget.cams, goTab: goTab, child: const MorePage()),
                  )),
                ),
                const SizedBox(width: 4),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: C.border),
              ),
            ),
            body: !repo.initialized
                ? const SkeletonOrEmpty()
                : IndexedStack(index: tab, children: const [
                    HomePage(),
                    SnowPage(),
                    WeatherPage(),
                    WebcamsPage(),
                    DomainPage(),
                  ]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: goTab,
              backgroundColor: C.surface,
              indicatorColor: C.blue.withValues(alpha: 0.18),
              height: 68,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
                NavigationDestination(icon: Icon(Icons.ac_unit_outlined), selectedIcon: Icon(Icons.ac_unit_rounded), label: 'Neige'),
                NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud_rounded), label: 'Météo'),
                NavigationDestination(
                    icon: Icon(Icons.photo_camera_outlined), selectedIcon: Icon(Icons.photo_camera_rounded), label: 'Webcams'),
                NavigationDestination(
                    icon: Icon(Icons.downhill_skiing_outlined), selectedIcon: Icon(Icons.downhill_skiing_rounded), label: 'Domaine'),
              ],
            ),
          );
        },
      ),
    );
  }

  String _subtitle(DataRepository repo) {
    final g = repo.generatedAt;
    if (g == null) return repo.loading ? 'Chargement…' : 'Aucune donnée';
    final prefix = repo.offline ? 'Hors ligne · ' : '';
    return '${prefix}Données ${whenText(g)} (heure suisse)';
  }
}

/// Premier lancement : squelette de chargement.
class SkeletonOrEmpty extends StatelessWidget {
  const SkeletonOrEmpty({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}
