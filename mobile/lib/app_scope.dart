import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/repository.dart';
import 'data/webcams.dart';

/// Accès aux données et à la navigation depuis n'importe quel écran.
class AppScope extends InheritedWidget {
  final DataRepository repo;
  final WebcamStore cams;
  final ValueChanged<int> goTab;

  const AppScope({super.key, required this.repo, required this.cams, required this.goTab, required super.child});

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => repo != oldWidget.repo || cams != oldWidget.cams;
}

Future<void> openLink(BuildContext context, String? url) async {
  if (url == null) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le lien")));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir le lien")));
  }
}
