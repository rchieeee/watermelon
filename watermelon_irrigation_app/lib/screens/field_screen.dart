import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/data_kind.dart';
import '../widgets/field_page.dart';
import '../widgets/layout.dart';
import '../widgets/metrics.dart';

class FieldScreen extends StatelessWidget {
  const FieldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FieldPage(
      title: 'Field',
      builder: (context, c) {
        final o = c.latest!;
        final t = Theme.of(context).textTheme;
        final readingKind = c.isLatestStale ? DataKind.historical : DataKind.current;

        return [
          Panel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current crop', style: t.bodyLarge?.copyWith(color: Palette.muted)),
                Text('Watermelon', style: t.headlineMedium),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text('Growth stage', style: t.bodyLarge?.copyWith(color: Palette.muted)),
                const SizedBox(height: 4),
                if (o.growthStage != null)
                  Row(children: [
                    const Icon(Icons.grass, color: Palette.leaf, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(Fmt.growthStage(o.growthStage!),
                          style: t.headlineMedium?.copyWith(color: Palette.rind)),
                    ),
                  ])
                else
                  const UnavailableText('Growth stage unavailable'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          UpdatedLine(o.timestamp),
          if (c.isLatestStale) ...[
            const SizedBox(height: 12),
            StaleNotice(o.timestamp),
          ],
          SectionHeader(title: 'Current field conditions', kind: readingKind),
          ConditionList(rows: [
            ConditionRow(
              icon: Icons.water_drop,
              label: 'Soil moisture',
              value: o.soilMoisturePct == null ? null : Fmt.percent(o.soilMoisturePct!),
              unavailableLabel: 'Soil moisture unavailable',
              accent: Palette.leaf,
            ),
            ConditionRow(
              icon: Icons.thermostat,
              label: 'Temperature',
              value: o.temperatureC == null ? null : Fmt.celsius(o.temperatureC!),
              unavailableLabel: 'Temperature unavailable',
              accent: Palette.sun,
            ),
            ConditionRow(
              icon: Icons.opacity,
              label: 'Humidity',
              value: o.humidityPct == null ? null : Fmt.percent(o.humidityPct!),
              unavailableLabel: 'Humidity unavailable',
              accent: Palette.water,
            ),
          ]),
          const SectionHeader(
            title: 'Weather forecast',
            subtitle: 'Next 12 hours',
            kind: DataKind.forecast,
          ),
          ConditionList(rows: [
            ConditionRow(
              icon: Icons.umbrella,
              label: 'Rain probability',
              value: o.rainProbability12hPct == null
                  ? null
                  : Fmt.percent(o.rainProbability12hPct!),
              unavailableLabel: 'Rain probability unavailable',
              accent: Palette.water,
            ),
            ConditionRow(
              icon: Icons.grain,
              label: 'Forecast rainfall',
              value: o.rainfallForecast12hMm == null
                  ? null
                  : Fmt.mm(o.rainfallForecast12hMm!),
              unavailableLabel: 'Rainfall forecast unavailable',
              accent: Palette.water,
            ),
          ]),
        ];
      },
    );
  }
}
