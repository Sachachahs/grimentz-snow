/// Accès sûr aux données JSON publiées par le backend.
///
/// Toute valeur absente ou d'un type inattendu donne `null` : l'interface affiche alors
/// « Donnée indisponible » au lieu d'inventer une valeur.
class J {
  final dynamic v;
  const J(this.v);

  static const J empty = J(null);

  J operator [](Object key) {
    final value = v;
    if (value is Map && key is String) return J(value[key]);
    if (value is List && key is int && key >= 0 && key < value.length) return J(value[key]);
    return empty;
  }

  bool get isNull => v == null;
  bool get exists => v != null;

  double? get d => v is num ? (v as num).toDouble() : null;
  int? get i => v is num ? (v as num).round() : null;
  bool get b => v == true;

  /// Texte non vide, sinon null.
  String? get s {
    final value = v;
    if (value == null) return null;
    final t = value.toString();
    return t.isEmpty ? null : t;
  }

  List<J> get list => v is List ? (v as List).map((e) => J(e)).toList() : <J>[];

  Map<String, J> get map {
    final value = v;
    if (value is! Map) return <String, J>{};
    return {for (final e in value.entries) e.key.toString(): J(e.value)};
  }

  int get length => v is List ? (v as List).length : (v is Map ? (v as Map).length : 0);
}
