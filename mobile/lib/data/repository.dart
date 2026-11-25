import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../util/format.dart';
import '../util/json.dart';
import 'config.dart';
import 'http.dart';

/// Source unique des données de l'application.
///
/// - Télécharge l'instantané publié par le backend en ligne (indépendant du PC).
/// - Le conserve sur le téléphone : hors connexion, les dernières données restent consultables,
///   avec leur date clairement indiquée (jamais présentées comme actuelles).
class DataRepository extends ChangeNotifier {
  J? data;
  List<J> events = <J>[];
  DateTime? downloadedAt; // heure suisse du dernier téléchargement réussi
  bool loading = false;
  String? error; // dernière erreur de téléchargement (null si le dernier essai a réussi)
  bool initialized = false;
  String dataUrl = kDefaultDataUrl;

  Directory? _dir;
  Timer? _timer;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final d = await getApplicationSupportDirectory();
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<File> _file(String name) async => File('${(await dir).path}/$name');

  Future<void> init() async {
    try {
      final s = await _file('settings.json');
      if (await s.exists()) {
        final m = J(jsonDecode(await s.readAsString()));
        final url = m['data_url'].s;
        if (url != null) dataUrl = url;
      }
    } catch (_) {}
    try {
      final f = await _file('data.json');
      if (await f.exists()) {
        data = J(jsonDecode(await f.readAsString()));
        final m = await _file('meta.json');
        if (await m.exists()) {
          downloadedAt = fromEpoch(J(jsonDecode(await m.readAsString()))['downloaded'].d);
        }
      }
      final e = await _file('events.json');
      if (await e.exists()) events = J(jsonDecode(await e.readAsString())).list;
    } catch (_) {
      data = null;
    }
    initialized = true;
    notifyListeners();
    await refresh();
    _timer?.cancel();
    _timer = Timer.periodic(kAutoRefresh, (_) => refresh());
  }

  /// Date de génération des données par le backend (heure suisse).
  DateTime? get generatedAt => fromEpoch(data?['generated_ts'].d) ?? parseLocal(data?['generated_at'].s);

  /// Vrai si les données affichées sont trop anciennes pour être considérées comme actuelles.
  bool get isStale {
    final g = generatedAt;
    return g == null || zurichNow().difference(g) > kStaleAfter;
  }

  bool get offline => error != null;

  Future<void> setDataUrl(String url) async {
    dataUrl = url.trim();
    try {
      final s = await _file('settings.json');
      await s.writeAsString(jsonEncode({'data_url': dataUrl}));
    } catch (_) {}
    notifyListeners();
    await refresh();
  }

  String? _eventsUrl() {
    if (!dataUrl.endsWith('data.json')) return null;
    return '${dataUrl.substring(0, dataUrl.length - 'data.json'.length)}events.json';
  }

  Future<void> refresh() async {
    if (loading) return;
    if (dataUrl.isEmpty) {
      error = "Adresse des données non configurée (Plus → Source des données)";
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final sep = dataUrl.contains('?') ? '&' : '?';
      final res = await fetchBytes('$dataUrl${sep}t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      final text = utf8.decode(res.bytes);
      final parsed = J(jsonDecode(text));
      if (parsed['generated_at'].isNull) throw FetchException('Données reçues illisibles');
      // On ne remplace jamais des données plus récentes par une version plus ancienne (cache du serveur).
      final newTs = parsed['generated_ts'].d ?? 0;
      final oldTs = data?['generated_ts'].d ?? 0;
      if (data == null || newTs >= oldTs) {
        data = parsed;
        await (await _file('data.json')).writeAsString(text);
      }
      downloadedAt = zurichNow();
      await (await _file('meta.json'))
          .writeAsString(jsonEncode({'downloaded': DateTime.now().millisecondsSinceEpoch / 1000}));
      error = null;
      final eu = _eventsUrl();
      if (eu != null) {
        try {
          final ev = await fetchBytes(eu, retries: 0);
          final evText = utf8.decode(ev.bytes);
          events = J(jsonDecode(evText)).list;
          await (await _file('events.json')).writeAsString(evText);
        } catch (_) {}
      }
    } on FetchException catch (e) {
      error = e.message;
    } on FormatException {
      error = 'Données reçues illisibles';
    } catch (e) {
      error = 'Actualisation impossible';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
