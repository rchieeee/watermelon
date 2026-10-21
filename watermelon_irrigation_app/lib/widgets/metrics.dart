import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'data_kind.dart';
import 'layout.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unavailableLabel,
    this.accent = Palette.rind,
    this.footer,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String unavailableLabel;
  final Color accent;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(label, style: t.labelLarge?.copyWith(color: Palette.muted))),
          ]),
          const SizedBox(height: 10),
          if (value != null)
            Text(value!, style: t.headlineMedium?.copyWith(fontSize: 34))
          else
            UnavailableText(unavailableLabel),
          if (footer != null && value != null) ...[
            const SizedBox(height: 14),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// Soil moisture gets the full width and a bar, because it is the main
/// field reading behind the irrigation decision.
class SoilMoistureTile extends StatelessWidget {
  const SoilMoistureTile({super.key, required this.valuePct});
  final double? valuePct;

  static String _pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}%';

  @override
  Widget build(BuildContext context) {
    final v = valuePct;
    return MetricTile(
      icon: Icons.water_drop,
      label: 'Soil moisture',
      value: v == null ? null : _pct(v),
      unavailableLabel: 'Soil moisture unavailable',
      accent: Palette.leaf,
      footer: v == null
          ? null
          : Semantics(
              label: 'Soil moisture ${v.round()} percent',
              child: _MoistureBar(v, height: 12),
            ),
    );
  }
}

class _MoistureBar extends StatelessWidget {
  const _MoistureBar(this.pct, {required this.height});
  final double pct;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: (pct / 100).clamp(0.0, 1.0),
          minHeight: height,
          color: Palette.leaf,
          backgroundColor: Palette.leafTint,
        ),
      );
}

/// A labeled value in a list, with its data kind.
class ConditionRow extends StatelessWidget {
  const ConditionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unavailableLabel,
    this.kind,
    this.accent = Palette.rind,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String unavailableLabel;
  final DataKind? kind;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.bodyMedium?.copyWith(color: Palette.muted)),
                const SizedBox(height: 2),
                if (value != null)
                  Text(value!, style: t.titleLarge?.copyWith(fontSize: 22))
                else
                  UnavailableText(unavailableLabel),
              ],
            ),
          ),
          if (kind != null) ...[
            const SizedBox(width: 8),
            StatusTag(kind: kind!),
          ],
        ],
      ),
    );
  }
}

/// Rows separated by dividers inside one panel.
class ConditionList extends StatelessWidget {
  const ConditionList({super.key, required this.rows, this.header});
  final List<Widget> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (header != null) ...[header!, const SizedBox(height: 4)],
    ];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider());
      children.add(rows[i]);
    }
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
