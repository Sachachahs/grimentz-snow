import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../util/format.dart';
import '../util/json.dart';
import 'http.dart';
import 'repository.dart';

/// Dernière image connue d'une webcam.
class CamShot {
  final Uint8List bytes;
  final DateTime? captured; // heure suisse de l'image (en-tête du serveur), si connue
  final DateTime fetched; // heure suisse du téléchargement
  final bool fromCache; // image reprise du téléphone (pas re-téléchargée)
  CamShot(this.bytes, this.captured, this.fetched, this.fromCache);
}

enum CamState { ok, old, oldDay, unknown, none }

/// Images des webcams, téléchargées directement chez le fournisseur officiel (trinum)
/// et gardées sur le téléphone pour la consultation hors connexion.
class WebcamStore extends ChangeNotifier {
  final DataRepository repo;
  final Map<int, CamShot> shots = {};
  final Set<int> _loading = {};
  final Map<int, String> errors = {};
  bool _restored = false;

  WebcamStore(this.repo);

  bool isLoading(int i) => _loading.contains(i);
  bool get anyLoading => _loading.isNotEmpty;

  List<J> get cams => repo.data?['webcams'].list ?? <J>[];

  Future<File> _file(int i, String ext) async => File('${(await repo.dir).path}/cam_$i.$ext');

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    for (var i = 0; i < 10; i++) {
      try {
        final f = await _file(i, 'jpg');
        if (!await f.exists()) continue;
        final m = J(jsonDecode(await (await _file(i, 'json')).readAsString()));
        shots[i] = CamShot(await f.readAsBytes(), fromEpoch(m['captured'].d), fromEpoch(m['fetched'].d) ?? zurichNow(), true);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Télécharge les images si elles ont plus de [maxAge] (ou toutes si [force]).
  Future<void> refreshAll({bool force = false, Duration maxAge = const Duration(minutes: 3)}) async {
    await restore();
    final list = cams;
    await Future.wait([
      for (var i = 0; i < list.length; i++)
        if (force || shots[i] == null || shots[i]!.fromCache || zurichNow().difference(shots[i]!.fetched) > maxAge)
          refresh(i)
    ]);
  }

  Future<void> refresh(int i) async {
    final list = cams;
    if (i >= list.length || _loading.contains(i)) return;
    final url = list[i]['url'].s;
    if (url == null) return;
    _loading.add(i);
    notifyListeners();
    try {
      final res = await fetchBytes(url);
      final captured = res.lastModified == null ? null : toZurich(res.lastModified!);
      shots[i] = CamShot(res.bytes, captured, zurichNow(), false);
      errors.remove(i);
      await (await _file(i, 'jpg')).writeAsBytes(res.bytes);
      await (await _file(i, 'json')).writeAsString(jsonEncode({
        'captured': res.lastModified == null ? null : res.lastModified!.millisecondsSinceEpoch / 1000,
        'fetched': DateTime.now().millisecondsSinceEpoch / 1000,
      }));
    } catch (e) {
      errors[i] = e.toString();
    } finally {
      _loading.remove(i);
      notifyListeners();
    }
  }

  /// Heure de l'image : celle du téléchargement sur le téléphone, sinon celle relevée par le backend.
  DateTime? capturedAt(int i) {
    final s = shots[i];
    if (s?.captured != null) return s!.captured;
    final list = cams;
    return i < list.length ? fromEpoch(list[i]['ts'].d) : null;
  }

  /// Même règle que l'application PC : vert ≤ 30 min, orange plus ancien, rouge si pas du jour.
  CamState state(int i) {
    final t = capturedAt(i);
    if (t == null) return shots[i] == null ? CamState.none : CamState.unknown;
    if (!sameDay(t, zurichNow())) return CamState.oldDay;
    return zurichNow().difference(t).inMinutes <= 30 ? CamState.ok : CamState.old;
  }

  String timeText(int i) {
    final t = capturedAt(i);
    if (t == null) return shots[i] == null ? 'Image indisponible' : 'Heure inconnue';
    return 'Image de ${hm(t)}${sameDay(t, zurichNow()) ? '' : ' le ${ddmm(t)}'}';
  }
}
