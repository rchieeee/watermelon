import 'package:flutter/material.dart';

import '../models/soil_sensor_reading.dart';
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
/// field reading behind the irrigation decision. With [sensors], it also
/// lists each soil sensor (1, 2, 3) under it.
class SoilMoistureTile extends StatelessWidget {
  const SoilMoistureTile({super.key, required this.valuePct, this.sensors = const []});

  /// Sensor 1 on the main ESP32, which is the reading the pump uses.
  final double? valuePct;
  final List<SoilSensorStatus> sensors;

  static String _pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}%';

  @override
  Widget build(BuildContext context) {
    final v = valuePct;
    return MetricTile(
      icon: Icons.water_drop,
      label: sensors.isEmpty
          ? 'Soil moisture'
          : 'Soil moisture · sensor 1 (controls the pump)',
      value: v == null ? null : _pct(v),
      unavailableLabel: 'Soil moisture unavailable',
      accent: Palette.leaf,
      footer: v == null
          ? null
          : Column(children: [
              Semantics(
                label: 'Soil moisture ${v.round()} percent',
                child: _MoistureBar(v, height: 12),
              ),
              if (sensors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Palette.line),
                for (final sensor in sensors) _SensorRow(sensor),
              ],
            ]),
    );
  }
}

/// "Sensor 2   [bar]   65%", or "Offline" / "Sensor error" instead.
class _SensorRow extends StatelessWidget {
  const _SensorRow(this.sensor);
  final SoilSensorStatus sensor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = sensor.moisturePct;
    final problem = !sensor.online ? 'Offline' : (pct == null ? 'Sensor error' : null);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label: 'Sensor ${sensor.number}: '
            '${problem ?? '${pct!.round()} percent'}',
        excludeSemantics: true,
        child: Row(children: [
          SizedBox(
            width: 76,
            child: Text('Sensor ${sensor.number}',
                style: t.bodyMedium?.copyWith(color: Palette.muted)),
          ),
          Expanded(
            child: pct == null ? const SizedBox.shrink() : _MoistureBar(pct, height: 8),
          ),
          SizedBox(
            width: 96,
            child: Text(
              problem ?? SoilMoistureTile._pct(pct!),
              textAlign: TextAlign.right,
              style: problem != null
                  ? t.bodyMedium?.copyWith(color: Palette.flesh)
                  : t.titleMedium,
            ),
          ),
        ]),
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
