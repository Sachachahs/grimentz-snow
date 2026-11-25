import 'package:flutter/material.dart';

/// Identité visuelle reprise de l'application PC (fond anthracite, cartes gris foncé, bordures discrètes).
class C {
  static const bg = Color(0xFF101216);
  static const surface = Color(0xFF0D0F13);
  static const card = Color(0xFF191D24);
  static const card2 = Color(0xFF202630);
  static const tile = Color(0xFF1F242C);
  static const border = Color(0xFF2B3440);
  static const text = Color(0xFFF1F3F5);
  static const muted = Color(0xFF91A0B4);
  static const subtle = Color(0xFF5E6675);
  static const blue = Color(0xFF4D9BFF);
  static const ice = Color(0xFFA9D1FF);
  static const snow = Color(0xFF39C5DC);
  static const sun = Color(0xFFFFBE36);
  static const good = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);
  static const measured = Color(0xFF398BEB);
  static const forecast = Color(0xFF75869B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.blue,
    brightness: Brightness.dark,
  ).copyWith(
    primary: C.blue,
    secondary: C.snow,
    surface: C.card,
    onSurface: C.text,
    error: C.bad,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    dividerColor: C.border,
    textTheme: Typography.whiteMountainView.apply(bodyColor: C.text, displayColor: C.text),
  );
}

class T {
  static const title = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: C.muted);
  static const label = TextStyle(fontSize: 12.5, color: C.muted);
  static const small = TextStyle(fontSize: 11.5, color: C.subtle);
  static const body = TextStyle(fontSize: 14.5, color: C.text);
  static const sub = TextStyle(fontSize: 13, color: C.muted);
  static const value = TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: C.text);
  static const mid = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text);
  static const big = TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: C.text, height: 1.05);
  static const na = TextStyle(fontSize: 13, color: C.subtle, fontStyle: FontStyle.italic);
}
