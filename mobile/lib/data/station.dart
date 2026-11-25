import 'dart:convert';

import '../util/format.dart';
import 'http.dart';

/// Données officielles de la station lues directement par le téléphone.
///
/// Le site valdanniviers.ch refuse les requêtes venant des serveurs de GitHub (erreur 403) : quand le backend
/// n'a pas pu lire la station, l'application interroge elle-même la même source que l'application PC
/// (endpoint infosnow de la page « Info live » et page officielle des horaires) et applique les mêmes règles
/// (portage en Dart de services/infosnow.py, services/schedule.py et web/snapshot.py).

const _infosnowUrl = 'https://www.valdanniviers.ch/mycity/ajax/infosnow/objects/56'
    '?facilities=lifts%2Cslopes%2Ctoboganning%2Ctouring%2Chiking%2Cfunparks%2Ccross-country%2Crestaurants%2Cdivers'
    '&reports=snow%2Cdangers';
const _infoliveUrl = 'https://www.valdanniviers.ch/fr/Z15114/infolive';
const _hoursUrl = 'https://www.valdanniviers.ch/fr/Z15372/horaires-rmgz';

const int kOpen = 1, kPreparing = 2, kClosed = 3;
const _stateLabels = {kOpen: 'Ouvert', kPreparing: 'En préparation', kClosed: 'Fermé'};
const _typeNames = {
  1: 'Téléski', 2: 'Téléski', 3: 'Télésiège', 4: 'Télésiège', 5: 'Télésiège', 6: 'Télésiège', 7: 'Télésiège',
  8: 'Funiculaire', 9: 'Télécabine', 10: 'Téléphérique', 13: 'Piste bleue', 14: 'Piste rouge', 15: 'Piste noire',
  16: 'Piste jaune', 17: 'Piste bleu / rouge', 18: 'Piste rouge / noire', 58: 'Tapis',
};
const _slopeColors = {13: '#2F7BFF', 14: '#E5383B', 15: '#101010', 16: '#E0A800', 17: '#E5383B', 18: '#101010'};
const _avalancheNames = {1: 'Faible', 2: 'Limité', 3: 'Marqué', 4: 'Fort', 5: 'Très fort'};
const _avalancheColors = {1: '#76C82B', 2: '#FFD60A', 3: '#FF9F0A', 4: '#FF6A1A', 5: '#C8141E'};
const _closureWords = [
  'vent', 'météo', 'meteo', 'tempête', 'tempete', 'visibilit', 'avalanche', 'intempérie', 'intemperie', 'brouillard',
  'orage', 'conditions'
];
const int _pointBottom = 509, _pointTop = 510;

/// Résultat brut téléchargé (conservé tel quel dans le cache du téléphone).
class StationRaw {
  final Map<String, dynamic> infosnow;
  final String? hoursPage;
  final double fetchedAt; // secondes depuis 1970
  StationRaw(this.infosnow, this.hoursPage, this.fetchedAt);

  Map<String, dynamic> toJson() => {'infosnow': infosnow, 'hours': hoursPage, 'fetched_at': fetchedAt};

  static StationRaw? fromJson(dynamic j) {
    if (j is! Map || j['infosnow'] is! Map) return null;
    return StationRaw(Map<String, dynamic>.from(j['infosnow'] as Map), j['hours'] as String?,
        (j['fetched_at'] as num?)?.toDouble() ?? 0);
  }
}

Future<StationRaw> fetchStation() async {
  const headers = {
    'Content-Type': 'application/json',
    'Referer': _infoliveUrl,
    'X-Requested-With': 'XMLHttpRequest',
    'Accept-Language': 'fr-CH,fr;q=0.9',
  };
  HttpResult res;
  try {
    res = await fetchBytes(_infosnowUrl, method: 'POST', headers: headers);
  } catch (_) {
    // Le site peut exiger un cookie de session : visite de la page officielle puis nouvel essai.
    final page = await fetchBytes(_infoliveUrl, retries: 0);
    res = await fetchBytes(_infosnowUrl,
        method: 'POST', headers: {...headers, if (page.cookies.isNotEmpty) 'Cookie': page.cookies});
  }
  final data = jsonDecode(utf8.decode(res.bytes));
  if (data is! Map) throw FetchException('Données de la station illisibles');
  String? hours;
  try {
    hours = utf8.decode((await fetchBytes(_hoursUrl, retries: 0)).bytes, allowMalformed: true);
  } catch (_) {
    hours = null;
  }
  return StationRaw(Map<String, dynamic>.from(data), hours, DateTime.now().millisecondsSinceEpoch / 1000);
}

// ------------------------------------------------------------------------------------------ outils

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : const [];

const _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'eacute': 'é', 'egrave': 'è',
  'ecirc': 'ê', 'agrave': 'à', 'acirc': 'â', 'ccedil': 'ç', 'ocirc': 'ô', 'ucirc': 'û', 'ugrave': 'ù',
  'icirc': 'î', 'iuml': 'ï', 'euml': 'ë', 'Eacute': 'É', 'laquo': '«', 'raquo': '»', 'rsquo': '’', 'ndash': '–',
  'mdash': '—', 'hellip': '…', 'deg': '°',
};

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final c = int.tryParse(e.substring(2), radix: 16);
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      if (e.startsWith('#')) {
        final c = int.tryParse(e.substring(1));
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      return _entities[e] ?? m.group(0)!;
    });

String _cleanHtml(String text) =>
    _unescape(text.replaceAll(RegExp(r'<[^>]+>'), ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();

DateTime? _parseDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso.replaceFirst(' ', 'T'));
}

String _formatDate(String? iso, {bool withTime = false}) {
  final d = _parseDate(iso);
  if (d == null) return iso ?? kNA;
  return withTime ? '${ddmmyyyy(d)} ${hm(d)}' : ddmmyyyy(d);
}

bool _isRecent(String? iso, int days) {
  final d = _parseDate(iso);
  if (d == null) return false;
  return zurichNow().difference(d) < Duration(days: days);
}

// ------------------------------------------------------------------------------------------ installations

class _Facility {
  final String name;
  final int typeId;
  final int state;
  final String condition;
  final String remarks;
  final double? lengthM;
  final int? hValley, hMountain;
  final String number;
  final String hours;
  final String? modifiedAt;
  late final String sector;
  final (double, double)? valley;

  _Facility(Map<String, dynamic> item)
      : name = (item['name'] ?? '?').toString(),
        typeId = (item['type'] as num?)?.toInt() ?? 0,
        state = switch (item['state']) { 1 => kOpen, 2 => kPreparing, _ => kClosed },
        condition = (_map(_map(item['condition'])['translation'])['fr'] ?? '').toString(),
        remarks = _cleanHtml((_map(item['stateRemarks'])['fr'] ?? '').toString()),
        lengthM = _num(item['length']),
        hValley = (item['heightValley'] as num?)?.toInt(),
        hMountain = (item['heightMountain'] as num?)?.toInt(),
        number = (item['initial'] ?? '').toString(),
        hours = _hoursOf(item),
        modifiedAt = item['modifiedAt']?.toString(),
        valley = _coords(item) {
    sector = _sectorOf();
  }

  static (double, double)? _coords(Map<String, dynamic> item) {
    final desc = _map(item['description']).values.map((v) => v.toString()).join(' ');
    final m = RegExp(r'Talstation\s+([\d.]+)\s*N\s*/\s*([\d.]+)\s*E', dotAll: true).firstMatch(desc);
    if (m != null) {
      final a = double.tryParse(m.group(1)!), b = double.tryParse(m.group(2)!);
      if (a != null && b != null) return (a, b);
    }
    final c = _map(item['coords']);
    final lat = _num(c['latitude']), lon = _num(c['longitude']);
    if (lat != null && lon != null && lat != 0) return (lat, lon);
    return null;
  }

  static String _hoursOf(Map<String, dynamic> item) {
    for (final e in item.entries) {
      final k = e.key.toLowerCase();
      if ((k.contains('opening') || k.contains('operating') || k.contains('hours')) && e.value != null && e.value != '') {
        var v = e.value;
        if (v is Map) v = v['fr'] ?? v.values.join(' ');
        return _cleanHtml(v.toString());
      }
    }
    return '';
  }

  String _sectorOf() {
    final n = name.toLowerCase();
    if (n.contains('bendolla') || n.startsWith('grimentz') || n.contains('orzival')) return 'Grimentz';
    if (n.contains('sorebois') || n.contains('zinal')) return 'Zinal';
    if (valley != null) return valley!.$1 >= 46.16 ? 'Grimentz' : 'Zinal';
    final m = RegExp(r'^\s*(\d+)').firstMatch(number);
    if (m != null) return int.parse(m.group(1)!) < 30 ? 'Grimentz' : 'Zinal';
    return 'Domaine';
  }

  String get typeLabel => _typeNames[typeId] ?? 'Installation';

  Map<String, dynamic> toJson() {
    String? alt;
    if (hValley != null && hMountain != null) {
      alt = '$hValley → $hMountain m';
    } else if (hValley != null) {
      alt = '$hValley m';
    }
    return {
      'name': name,
      'number': number.isEmpty ? null : number,
      'type': typeLabel,
      'state': state,
      'state_label': _stateLabels[state],
      'alt': alt,
      'remark': remarks.isNotEmpty ? remarks : (condition.isNotEmpty ? capitalize(condition) : null),
      'length_km': lengthM == null ? null : double.parse((lengthM! / 1000).toStringAsFixed(1)),
      'color': _slopeColors[typeId],
    };
  }
}

Map<String, dynamic>? _openCount(int? open, int? total, List<_Facility> items) {
  if (total == null || total == 0) return null;
  final prep = items.where((f) => f.state == kPreparing).length;
  final o = open ?? 0;
  return {'open': o, 'total': total, 'prep': prep, 'closed': (total - o - prep).clamp(0, total)};
}

// ------------------------------------------------------------------------------------------ calendrier officiel

const _mois = {
  'janvier': 1, 'février': 2, 'fevrier': 2, 'mars': 3, 'avril': 4, 'mai': 5, 'juin': 6, 'juillet': 7, 'août': 8,
  'aout': 8, 'septembre': 9, 'octobre': 10, 'novembre': 11, 'décembre': 12, 'decembre': 12,
};
const _sectors = ['Bendolla', 'Sorebois'];

class _Rule {
  final DateTime start;
  final DateTime? end;
  final bool weekendsOnly;
  final List<String> sectors;
  final bool conditional;
  _Rule(this.start, this.end, this.weekendsOnly, this.sectors, this.conditional);
}

class _Schedule {
  String season = '';
  final rules = <_Rule>[];
  String openTime = '', lastUp = '', lastDown = '';

  DateTime? get seasonEnd {
    DateTime? e;
    for (final r in rules) {
      if (r.end != null && (e == null || r.end!.isAfter(e))) e = r.end;
    }
    return e;
  }

  (List<String>, bool) plan(DateTime d) {
    final endCap = seasonEnd;
    final s = <String>{};
    var conditional = false, firm = false;
    for (final r in rules) {
      final end = r.end ?? endCap;
      if (d.isBefore(r.start) || (end != null && d.isAfter(end))) continue;
      if (r.weekendsOnly && d.weekday <= 5) continue;
      s.addAll(r.sectors);
      if (r.conditional) {
        conditional = true;
      } else {
        firm = true;
      }
    }
    return ([for (final x in _sectors) if (s.contains(x)) x], conditional && !firm);
  }

  String hoursText() => openTime.isNotEmpty && lastDown.isNotEmpty ? '$openTime–$lastDown' : openTime;

  (DateTime, List<String>, bool)? nextOpening(DateTime today) {
    for (var k = 0; k < 200; k++) {
      final d = DateTime(today.year, today.month, today.day + k);
      final (sectors, cond) = plan(d);
      if (sectors.isNotEmpty) return (d, sectors, cond);
    }
    return null;
  }

  static _Schedule? parse(String? page) {
    if (page == null) return null;
    final sch = _Schedule();
    final m = RegExp(r'<span>\s*(Hiver\s+\d{4}\s*-\s*\d{4})\s*</span>', caseSensitive: false).firstMatch(page);
    if (m == null) return null;
    sch.season = m.group(1)!;
    final rest = page.substring(m.end);
    final stop = RegExp(r'''data-block=("|'|\\")subtitle''').firstMatch(rest);
    final section = stop != null ? rest.substring(0, stop.start) : rest.substring(0, rest.length < 20000 ? rest.length : 20000);
    String clean(String f) => _cleanHtml(f.replaceAll(RegExp(r'<span class="table-mobile-only">.*?</span>', dotAll: true), ' '));
    final dateRe = RegExp('(\\d{1,2})(?:er)?\\s+(${_mois.keys.join('|')})\\s+(\\d{4})', caseSensitive: false);
    for (final row in RegExp(r'<tr>\s*<th>(.*?)</th>(.*?)</tr>', dotAll: true).allMatches(section)) {
      final label = clean(row.group(1)!), text = clean(row.group(2)!);
      if (label.isEmpty && text.isEmpty) continue;
      final low = '$label $text'.toLowerCase();
      if (low.contains('ouverture des installations')) {
        sch.openTime = text.replaceAll('dès', '').trim();
        continue;
      }
      if (low.contains('dernière montée')) {
        sch.lastUp = text;
        continue;
      }
      if (low.contains('dernière descente')) {
        sch.lastDown = text;
        continue;
      }
      final ds = <DateTime>[];
      for (final dm in dateRe.allMatches(text)) {
        final mo = _mois[dm.group(2)!.toLowerCase()];
        if (mo != null) ds.add(DateTime(int.parse(dm.group(3)!), mo, int.parse(dm.group(1)!)));
      }
      if (ds.isEmpty) continue;
      List<String> sectors;
      if (low.contains('deux secteurs') || (low.contains('bendolla') && low.contains('sorebois'))) {
        sectors = _sectors;
      } else if (low.contains('sorebois')) {
        sectors = ['Sorebois'];
      } else if (low.contains('bendolla')) {
        sectors = ['Bendolla'];
      } else {
        sectors = _sectors;
      }
      final end = ds.length >= 2 && RegExp(r'\bau\b').hasMatch(text.toLowerCase()) ? ds[1] : null;
      sch.rules.add(_Rule(ds[0], end, low.contains('week-end') || low.contains('weekend'), sectors,
          low.contains('sous réserve')));
    }
    return (sch.rules.isEmpty && sch.openTime.isEmpty) ? null : sch;
  }
}

// ------------------------------------------------------------------------------------------ construction

/// Met à jour les parties « station » des données (mêmes champs que le backend) à partir de la lecture directe.
void applyStation(Map<String, dynamic> data, StationRaw raw) {
  final reports = _map(raw.infosnow['reports']);
  final facilities = _map(raw.infosnow['facilities']);

  // --- neige
  final snowPoints = <int, Map<String, dynamic>>{};
  for (final it in _list(_map(reports['snow'])['items'])) {
    final item = _map(it);
    final id = (item['id'] as num?)?.toInt();
    if (id != null) snowPoints[id] = item;
  }
  String? quality(Map<String, dynamic> item) {
    for (final k in ['snowCondition', 'snowQuality', 'quality', 'condition']) {
      var v = item[k];
      if (v is Map) v = _map(v['translation'])['fr'] ?? v['fr'];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  // --- avalanche
  int? avLevel;
  String? avModified;
  for (final it in _list(_map(reports['dangers'])['items'])) {
    final d = _map(it);
    final lvl = int.tryParse('${d['state'] ?? ''}');
    if (d['type'] == 'avalanche' && lvl != null && lvl >= 1 && lvl <= 5) {
      avLevel = avLevel == null || lvl > avLevel ? lvl : avLevel;
      avModified = d['modifiedAt']?.toString() ?? avModified;
    }
  }

  // --- installations
  final liftsBlock = _map(facilities['lifts']);
  final slopesBlock = _map(facilities['slopes']);
  final lifts = [for (final it in _list(liftsBlock['items'])) _Facility(_map(it))];
  final slopes = [
    for (final it in _list(slopesBlock['items']))
      if ([13, 14, 15, 16, 17, 18].contains((_map(it)['type'] as num?)?.toInt())) _Facility(_map(it))
  ];
  final liftsTotal = liftsBlock.isEmpty ? null : ((liftsBlock['count'] as num?)?.toInt() ?? lifts.length);
  final liftsOpen = liftsBlock.isEmpty ? null : lifts.where((f) => f.state == kOpen).length;
  final slopesTotal = slopesBlock.isEmpty ? null : slopes.length;
  final slopesOpen = slopesBlock.isEmpty ? null : slopes.where((f) => f.state == kOpen).length;
  double? kmTotal, kmOpen;
  if (_num(slopesBlock['length']) != null && _num(slopesBlock['length'])! > 0) {
    kmTotal = _num(slopesBlock['length'])! / 1000;
    kmOpen = (_num(slopesBlock['length_open']) ?? 0) / 1000;
  }
  final closures = <String>[];
  for (final f in [...lifts, ...slopes]) {
    final txt = '${f.remarks} ${f.condition}'.toLowerCase();
    if (f.state != kOpen && _closureWords.any(txt.contains)) {
      closures.add('${f.name} : ${f.remarks.isNotEmpty ? f.remarks : f.condition}');
    }
  }

  // --- partie « neige » des données
  final snow = _map(data['snow']);
  final measures = _list(snow['measures']).map((m) => _map(m)).toList();
  Map<String, dynamic> measure(String name, Map<String, dynamic>? sp) => {
        'name': name,
        'altitude': null,
        'cm': sp == null ? null : (_num(sp['snowHeight'])?.roundToDouble()),
        'when': sp == null ? null : 'Station · relevé du ${_formatDate(sp['modifiedAt']?.toString(), withTime: true)}',
      };
  final grimentz = measures.where((m) => (m['name'] ?? '').toString().contains('MétéoSuisse')).toList();
  snow['measures'] = [
    ...grimentz,
    measure('Bas du domaine', snowPoints[_pointBottom]),
    measure('Haut du domaine', snowPoints[_pointTop]),
  ];
  final q = [for (final sp in snowPoints.values) if (quality(sp) != null) quality(sp)!];
  snow['quality'] = q.isEmpty ? null : q.first;
  final making = [for (final sp in snowPoints.values) if (sp['snowMaking'] is bool) sp['snowMaking'] as bool];
  snow['making'] = making.isEmpty ? null : (making.any((x) => x) ? 'Oui' : 'Non');
  snow['avalanche'] = {
    'level': avLevel,
    'name': _avalancheNames[avLevel],
    'color': _avalancheColors[avLevel],
    'updated': avModified == null ? null : _formatDate(avModified, withTime: true),
    'source': 'Station (Info live, valdanniviers.ch)',
  };
  final top = snowPoints[_pointTop];
  final topRecent = top != null && _isRecent(top['modifiedAt']?.toString(), 21);
  snow['note'] = topRecent
      ? null
      : "Les relevés officiels ne sont pas encore actualisés pour la saison : cumuls de neige fraîche et dernière "
          "chute d'après MétéoSuisse (Grimentz).";
  // Neige fraîche 24 h : relevé officiel s'il date de moins de 3 jours (même règle que l'application PC)
  final topNew = top == null ? null : _num(top['snowHeightNew']);
  if (top != null && topNew != null && _isRecent(top['modifiedAt']?.toString(), 3)) {
    final fresh = _list(snow['fresh']).map((f) => _map(f)).toList();
    for (final f in fresh) {
      if (f['h'] == 24) {
        f['cm'] = topNew.roundToDouble();
        f['src'] = 'relevé officiel';
      }
    }
    snow['fresh'] = fresh;
  }
  data['snow'] = snow;

  // --- partie « domaine »
  final sch = _Schedule.parse(raw.hoursPage);
  final today = zurichToday();
  final prepSlopes = slopes.where((f) => f.state == kPreparing).toList();
  final prepKm = prepSlopes.fold<double>(0.0, (s, f) => s + (f.lengthM ?? 0.0)) / 1000;
  double? pctOpen, pctPrep;
  if (kmTotal != null && kmTotal > 0) {
    pctOpen = 100 * (kmOpen ?? 0) / kmTotal;
    pctPrep = 100 * prepKm / kmTotal;
  } else if (slopesTotal != null && slopesTotal > 0) {
    pctOpen = 100 * (slopesOpen ?? 0) / slopesTotal;
    pctPrep = 100 * prepSlopes.length / slopesTotal;
  }
  final hours = sch?.hoursText() ?? '';
  final week = <Map<String, dynamic>>[];
  for (var k = 0; k < 7; k++) {
    final d = DateTime(today.year, today.month, today.day + k);
    final (sectors, cond) = sch?.plan(d) ?? (<String>[], false);
    String state, kind;
    if (k == 0 && (liftsOpen ?? 0) > 0) {
      state = 'Ouvert';
      kind = 'open';
    } else if (sectors.isNotEmpty) {
      state = sectors.join(' + ') + (cond ? '*' : '');
      kind = cond ? 'cond' : 'open';
    } else {
      state = 'Fermé';
      kind = 'closed';
    }
    week.add({
      'date': '${d.year}-${two(d.month)}-${two(d.day)}',
      'label': k == 0 ? "Aujourd'hui" : weekday(d),
      'state': state,
      'kind': kind,
      'hours': kind == 'closed' ? '' : hours,
    });
  }
  final nx = sch?.nextOpening(today);
  final stations = <String, dynamic>{};
  for (final key in ['Grimentz', 'Zinal', 'Domaine']) {
    final l = lifts.where((f) => f.sector == key).toList()..sort((a, b) => a.name.compareTo(b.name));
    final s = slopes.where((f) => f.sector == key).toList()
      ..sort((a, b) => a.typeId != b.typeId ? a.typeId.compareTo(b.typeId) : a.name.compareTo(b.name));
    if (l.isEmpty && s.isEmpty) continue;
    stations[key] = {
      'lifts': [for (final f in l) f.toJson()],
      'slopes': [for (final f in s) f.toJson()],
      'lifts_count': _openCount(l.where((f) => f.state == kOpen).length, l.length, l),
      'slopes_count': _openCount(s.where((f) => f.state == kOpen).length, s.length, s),
    };
  }
  double? r1(double? v) => v == null ? null : double.parse(v.toStringAsFixed(1));
  double? r0(double? v) => v?.roundToDouble();
  data['domain'] = {
    'fetched_at': raw.fetchedAt,
    'stale': false,
    'direct': true,
    'lifts': _openCount(liftsOpen, liftsTotal, lifts),
    'slopes': _openCount(slopesOpen, slopesTotal, slopes),
    'km_open': r1(kmOpen),
    'km_total': r0(kmTotal),
    'km_prep': r1(prepKm),
    'pct_open': r0(pctOpen),
    'pct_prep': r0(pctPrep),
    'week': week,
    'season': sch?.season,
    'last_up': (sch == null || sch.lastUp.isEmpty) ? null : sch.lastUp,
    'next_opening': nx == null
        ? null
        : {
            'date': '${nx.$1.year}-${two(nx.$1.month)}-${two(nx.$1.day)}',
            'label': '${weekday(nx.$1)} ${ddmm(nx.$1)}',
            'sectors': nx.$2,
            'cond': nx.$3,
          },
    'stations': stations,
    'closures': closures,
    'official_snow_date': top == null ? kNA : _formatDate(top['modifiedAt']?.toString(), withTime: true),
  };
}
