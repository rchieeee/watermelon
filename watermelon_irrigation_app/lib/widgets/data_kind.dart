import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Every value shown in the app is one of these. Forecast and predicted
/// values are never presented as measured readings.
enum DataKind { current, historical, forecast, predicted }

extension DataKindStyle on DataKind {
  String get label => switch (this) {
        DataKind.current => 'Current',
        DataKind.historical => 'Historical',
        DataKind.forecast => 'Forecast',
        DataKind.predicted => 'Predicted',
      };

  IconData get icon => switch (this) {
        DataKind.current => Icons.sensors,
        DataKind.historical => Icons.history,
        DataKind.forecast => Icons.cloud_outlined,
        DataKind.predicted => Icons.auto_graph,
      };

  Color get foreground => switch (this) {
        DataKind.current => Palette.rind,
        DataKind.historical => Palette.sun,
        DataKind.forecast => Palette.water,
        DataKind.predicted => Palette.stone,
      };

  Color get background => switch (this) {
        DataKind.current => Palette.leafTint,
        DataKind.historical => Palette.sunTint,
        DataKind.forecast => Palette.waterTint,
        DataKind.predicted => Palette.stoneTint,
      };
}

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.kind, this.onDark = false});

  final DataKind kind;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : kind.foreground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withAlpha(40) : kind.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kind.icon, size: 16, color: fg),
          const SizedBox(width: 5),
          Text(kind.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}
