import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/data_kind.dart';
import '../widgets/field_page.dart';
import '../widgets/layout.dart';
import '../widgets/metrics.dart';
import '../widgets/pump_card.dart';
import '../widgets/recommendation_card.dart';

class IrrigationScreen extends StatelessWidget {
  const IrrigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FieldPage(
      title: 'Irrigation',
      builder: (context, c) {
        final o = c.latest!;
        final readingKind = c.isLatestStale ? DataKind.historical : DataKind.current;
        final linkColor = RecommendationCard.colorFor(c.prediction);
        final t = Theme.of(context).textTheme;

        return [
          UpdatedLine(o.timestamp),
          if (c.isLatestStale) ...[
            const SizedBox(height: 12),
            StaleNotice(o.timestamp),
          ],
          if (c.canControlPump) ...[
            const SizedBox(height: 16),
            PumpCard(controller: c),
          ],
          if (showPrediction) ...[
            const SizedBox(height: 16),
            RecommendationCard(prediction: c.prediction, detailed: true),

            // Connector: ties the recommendation to the conditions below it.
            // Align stops the ListView from stretching it to full width.
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Container(width: 4, height: 22, color: linkColor),
              ),
            ),
          ] else
            const SizedBox(height: 16),

          ConditionList(
            header: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(showPrediction ? 'Based on these conditions' : 'Field conditions',
                      style: t.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    showPrediction
                        ? 'The recommendation uses the latest field reading, '
                            'the 12-hour forecast and the growth stage.'
                        : 'The pump turns on when the soil average is below 60% '
                            'and off when it goes above 75%.',
                    style: t.bodyMedium?.copyWith(color: Palette.muted),
                  ),
                ],
              ),
            ),
            rows: [
              ConditionRow(
                icon: Icons.water_drop,
                label: 'Soil moisture',
                value: o.soilMoisturePct == null ? null : Fmt.percent(o.soilMoisturePct!),
                unavailableLabel: 'Soil moisture unavailable',
                kind: readingKind,
                accent: Palette.leaf,
              ),
              ConditionRow(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: o.temperatureC == null ? null : Fmt.celsius(o.temperatureC!),
                unavailableLabel: 'Temperature unavailable',
                kind: readingKind,
                accent: Palette.sun,
              ),
              ConditionRow(
                icon: Icons.opacity,
                label: 'Humidity',
                value: o.humidityPct == null ? null : Fmt.percent(o.humidityPct!),
                unavailableLabel: 'Humidity unavailable',
                kind: readingKind,
                accent: Palette.water,
              ),
              ConditionRow(
                icon: Icons.umbrella,
                label: 'Rain probability, next 12 hours',
                value: o.rainProbability12hPct == null
                    ? null
                    : Fmt.percent(o.rainProbability12hPct!),
                unavailableLabel: 'Rain probability unavailable',
                kind: DataKind.forecast,
                accent: Palette.water,
              ),
              ConditionRow(
                icon: Icons.grain,
                label: 'Forecast rainfall, next 12 hours',
                value: o.rainfallForecast12hMm == null
                    ? null
                    : Fmt.mm(o.rainfallForecast12hMm!),
                unavailableLabel: 'Rainfall forecast unavailable',
                kind: DataKind.forecast,
                accent: Palette.water,
              ),
              ConditionRow(
                icon: Icons.grass,
                label: 'Growth stage',
                value: o.growthStage == null ? null : Fmt.growthStage(o.growthStage!),
                unavailableLabel: 'Growth stage unavailable',
                kind: readingKind,
                accent: Palette.rind,
              ),
            ],
          ),
        ];
      },
    );
  }
}
