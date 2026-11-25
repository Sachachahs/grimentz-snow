import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/format.dart';

/// Carte gris foncé à bordure discrète.
class AppCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(14), this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text((title ?? '').toUpperCase(), style: T.title, maxLines: 2)),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: content)),
    );
  }
}

/// « Donnée indisponible ».
class NA extends StatelessWidget {
  final String text;
  const NA({super.key, this.text = kNA});
  @override
  Widget build(BuildContext context) => Text(text, style: T.na);
}

/// Petite tuile de valeur (icône, libellé, valeur, complément).
class Tile extends StatelessWidget {
  final IconData? icon;
  final Color iconColor;
  final String label;
  final String? value; // null → « Donnée indisponible »
  final Color? valueColor;
  final String? small; // complément à côté de la valeur (ex. direction du vent)
  final String? sub; // ligne sous la valeur
  final double valueSize;

  const Tile({
    super.key,
    this.icon,
    this.iconColor = C.muted,
    required this.label,
    required this.value,
    this.valueColor,
    this.small,
    this.sub,
    this.valueSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: C.tile,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 15, color: iconColor), const SizedBox(width: 5)],
            Expanded(child: Text(label, style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          if (value == null)
            const NA()
          else
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: value,
                    style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w700, color: valueColor ?? C.text)),
                if (small != null && small!.isNotEmpty)
                  TextSpan(text: '  $small', style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub!, style: T.small, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Grille de tuiles à colonnes fixes (hauteur adaptée au contenu).
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  final double gap;
  const TileGrid({super.key, required this.children, this.columns = 2, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var k = 0; k < columns; k++) {
        if (k > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(child: i + k < children.length ? children[i + k] : const SizedBox()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Choix segmenté compact (périodes, points de prévision…).
class Seg<V> extends StatelessWidget {
  final List<(V, String)> options;
  final V value;
  final ValueChanged<V> onChanged;
  const Seg({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chip(text: o.$2, selected: o.$1 == value, onTap: () => onChanged(o.$1)),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;
  const _Chip({required this.text, required this.selected, required this.onTap, this.dot});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? C.blue.withValues(alpha: 0.16) : C.tile,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? C.blue : C.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(text,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: selected ? C.ice : C.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Puce de série de graphique activable (légende cliquable).
class ToggleChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  const ToggleChip({super.key, required this.text, required this.color, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: on ? 1 : 0.45, child: _Chip(text: text, selected: false, onTap: onTap, dot: color));
}

class Dot extends StatelessWidget {
  final Color color;
  final double size;
  const Dot(this.color, {super.key, this.size = 9});
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class Legend extends StatelessWidget {
  final List<(Color, String)> items;
  const Legend(this.items, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 6, children: [
        for (final it in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: it.$1, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(it.$2, style: T.small.copyWith(color: C.muted)),
          ]),
      ]);
}

/// Bandeau d'information (hors connexion, données anciennes, note officielle…).
class Banner2 extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;
  const Banner2({super.key, required this.icon, required this.color, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.95)))),
        if (action != null) action!,
      ]),
    );
  }
}

/// Bloc gris animé pendant le premier chargement.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({super.key, required this.height, this.width, this.radius = 16});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(C.card, C.card2, _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: C.border.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(14),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          Skeleton(height: 170),
          SizedBox(height: 12),
          Skeleton(height: 120),
          SizedBox(height: 12),
          Skeleton(height: 150),
          SizedBox(height: 12),
          Skeleton(height: 110),
        ],
      );
}

/// Barre horizontale (hauteur de neige relative).
class Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  const Bar(this.fraction, {super.key, this.color = C.snow});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Container(color: C.border),
            FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0).toDouble(), child: Container(color: color)),
          ]),
        ),
      );
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
