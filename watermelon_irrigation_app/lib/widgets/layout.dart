import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'data_kind.dart';

/// Plain white surface. No shadow: flat, high-contrast panels read
/// better in direct sunlight.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor = Palette.line,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: child,
      );
}

/// Two equal-height tiles side by side.
class TileRow extends StatelessWidget {
  const TileRow({super.key, required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.kind, this.subtitle});
  final String title;
  final DataKind? kind;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: t.titleLarge)),
            if (kind != null) StatusTag(kind: kind!),
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: Palette.muted)),
            ),
        ],
      ),
    );
  }
}

class UnavailableText extends StatelessWidget {
  const UnavailableText(this.text, {super.key, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : Palette.flesh;
    return Row(children: [
      Icon(Icons.error_outline, size: 20, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class UpdatedLine extends StatelessWidget {
  const UpdatedLine(this.timestamp, {super.key});
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) => Text(
        'Updated: ${Fmt.updated(timestamp)}',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Palette.muted),
      );
}

/// Shown when the newest reading is old, so historical data is never
/// mistaken for a live measurement.
class StaleNotice extends StatelessWidget {
  const StaleNotice(this.timestamp, {super.key});
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.sunTint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history, color: Palette.sun),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Showing the latest recorded data, from ${Fmt.updated(timestamp)}. '
                'There is no newer reading yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
}

class GrowthStagePill extends StatelessWidget {
  const GrowthStagePill(this.stage, {super.key, this.onTap});
  final String? stage;

  /// When set, the pill is a button for changing the stage.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (stage == null && onTap == null) {
      return const UnavailableText('Growth stage unavailable');
    }
    final pill = Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.grass, size: 20, color: Palette.rind),
      const SizedBox(width: 8),
      if (stage == null)
        Text('Set growth stage',
            style: t.bodyLarge?.copyWith(color: Palette.rind, fontWeight: FontWeight.w700))
      else ...[
        Text('Growth stage: ', style: t.bodyLarge?.copyWith(color: Palette.rind)),
        Flexible(
          child: Text(Fmt.growthStage(stage!),
              style: t.bodyLarge?.copyWith(color: Palette.rind, fontWeight: FontWeight.w700)),
        ),
      ],
      if (onTap != null) ...[
        const SizedBox(width: 6),
        const Icon(Icons.expand_more, size: 22, color: Palette.rind),
      ],
    ]);
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : 'Change growth stage',
      child: Material(
        color: Palette.leafTint,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, onTap == null ? 12 : 8, 8),
            child: pill,
          ),
        ),
      ),
    );
  }
}
