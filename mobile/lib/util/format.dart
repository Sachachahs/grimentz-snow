import 'package:flutter/material.dart';

/// Formatage et dates (français, heure de Grimentz).
///
/// Les dates publiées par le backend sont en heure suisse (Europe/Zurich), sans fuseau.
/// Elles sont manipulées ici comme des « heures murales suisses » (DateTime sans fuseau),
/// et comparées à l'heure actuelle en Suisse, quel que soit le pays où se trouve le téléphone.

const String kNA = 'Donnée indisponible';

const List<String> kJours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const List<String> kJoursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const List<String> kMois = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const List<String> kMoisLongs = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

/// Nombre formaté (« -0 » évité), ou null si la valeur est absente.
String? fmt(num? v, {String unit = '', int digits = 0}) {
  if (v == null || v.isNaN) return null;
  var t = v.toStringAsFixed(digits);
  if (RegExp(r'^-0(\.0+)?$').hasMatch(t)) t = t.substring(1);
  return unit.isEmpty ? t : '$t $unit';
}

/// Comme [fmt] mais renvoie « — » si absent.
String fmtOr(num? v, {String unit = '', int digits = 0, String fallback = '—'}) =>
    fmt(v, unit: unit, digits: digits) ?? fallback;

/// Quantité de neige : une décimale sous 1 cm, sinon entier.
String? fmtCm(num? v) {
  if (v == null) return null;
  return fmt(v, unit: 'cm', digits: (v > 0 && v < 1) ? 1 : 0);
}

String two(int n) => n.toString().padLeft(2, '0');

/// Décalage de Zurich (CET / CEST) pour un instant UTC.
Duration zurichOffset(DateTime utc) {
  DateTime lastSunday(int year, int month) {
    var d = DateTime.utc(year, month + 1, 1).subtract(const Duration(days: 1));
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  final y = utc.year;
  final start = lastSunday(y, 3).add(const Duration(hours: 1));
  final end = lastSunday(y, 10).add(const Duration(hours: 1));
  final summer = !utc.isBefore(start) && utc.isBefore(end);
  return Duration(hours: summer ? 2 : 1);
}

/// Heure murale suisse d'un instant.
DateTime toZurich(DateTime instant) {
  final utc = instant.toUtc();
  final z = utc.add(zurichOffset(utc));
  return DateTime(z.year, z.month, z.day, z.hour, z.minute, z.second);
}

DateTime zurichNow() => toZurich(DateTime.now());

DateTime zurichToday() {
  final n = zurichNow();
  return DateTime(n.year, n.month, n.day);
}

DateTime? fromEpoch(num? seconds) =>
    seconds == null ? null : toZurich(DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true));

/// Lit « AAAA-MM-JJ » ou « AAAA-MM-JJTHH:MM » (heure suisse) sans conversion de fuseau.
DateTime? parseLocal(String? iso) {
  if (iso == null || iso.length < 10) return null;
  try {
    final y = int.parse(iso.substring(0, 4));
    final m = int.parse(iso.substring(5, 7));
    final d = int.parse(iso.substring(8, 10));
    var h = 0, mi = 0;
    if (iso.length >= 16) {
      h = int.parse(iso.substring(11, 13));
      mi = int.parse(iso.substring(14, 16));
    }
    return DateTime(y, m, d, h, mi);
  } catch (_) {
    return null;
  }
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
int daysBetween(DateTime a, DateTime b) => dayOf(b).difference(dayOf(a)).inHours ~/ 24;

String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String ddmm(DateTime d) => '${two(d.day)}.${two(d.month)}';
String ddmmyyyy(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
String dayShort(DateTime d) => '${d.day} ${kMois[d.month - 1]}';
String weekday(DateTime d) => kJours[d.weekday - 1];
String weekdayShort(DateTime d) => kJoursCourts[d.weekday - 1];
String longDate(DateTime d) => '${weekday(d)} ${d.day} ${kMoisLongs[d.month - 1]} ${d.year}';

/// « aujourd'hui à 21:40 », « hier à 18:05 », « le 23.11 à 07:30 ».
String whenText(DateTime d) {
  final today = zurichToday();
  final diff = daysBetween(d, today);
  if (diff == 0) return "aujourd'hui à ${hm(d)}";
  if (diff == 1) return 'hier à ${hm(d)}';
  return 'le ${ddmm(d)} à ${hm(d)}';
}

/// Âge lisible : « il y a 5 min », « il y a 2 h », « il y a 3 j ».
String ageText(DateTime d) {
  final mins = zurichNow().difference(d).inMinutes;
  if (mins < 1) return "à l'instant";
  if (mins < 60) return 'il y a $mins min';
  if (mins < 48 * 60) return 'il y a ${mins ~/ 60} h';
  return 'il y a ${mins ~/ 1440} j';
}

/// Couleur d'une température (dégradé froid → chaud), comme l'application PC.
Color tempColor(double? t) {
  if (t == null) return const Color(0xFF5E6675);
  const stops = <List<num>>[
    [-20, 40, 70, 200],
    [-10, 55, 105, 225],
    [0, 85, 160, 240],
    [10, 190, 228, 255],
    [17, 255, 205, 160],
    [25, 255, 120, 90],
    [35, 225, 35, 45],
  ];
  Color c(List<num> s) => Color.fromARGB(255, s[1].toInt(), s[2].toInt(), s[3].toInt());
  if (t <= stops.first[0]) return c(stops.first);
  for (var i = 0; i < stops.length - 1; i++) {
    final a = stops[i], b = stops[i + 1];
    if (t <= b[0]) {
      final f = (t - a[0]) / (b[0] - a[0]);
      int lerp(int k) => (a[k] + (b[k] - a[k]) * f).round().clamp(0, 255).toInt();
      return Color.fromARGB(255, lerp(1), lerp(2), lerp(3));
    }
  }
  return c(stops.last);
}

Color hexColor(String? hex, [Color fallback = const Color(0xFF91A0B4)]) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
