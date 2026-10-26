import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/data_kind.dart';
import '../widgets/field_page.dart';
import '../widgets/growth_stage_picker.dart';
import '../widgets/layout.dart';
import '../widgets/metrics.dart';
import '../widgets/pump_card.dart';
import '../widgets/recommendation_card.dart';

/// Answers "do I need to irrigate right now?" before anything else.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FieldPage(
      title: 'Watermelon field',
      builder: (context, c) {
        final o = c.latest!;
        final readingKind = c.isLatestStale ? DataKind.historical : DataKind.current;
        return [
          UpdatedLine(o.timestamp),
          if (c.isLatestStale) ...[
            const SizedBox(height: 12),
            StaleNotice(o.timestamp),
          ],
          if (showPrediction) ...[
            const SizedBox(height: 18),
            RecommendationCard(prediction: c.prediction),
          ],

          SectionHeader(title: 'Current conditions', kind: readingKind),
          SoilMoistureTile(
            valuePct: o.soilMoisturePct,
            sensors: c.hasSoilSensors ? c.soilSensors : const [],
          ),
          const SizedBox(height: 12),
          TileRow(
            left: MetricTile(
              icon: Icons.thermostat,
              label: 'Temperature',
              value: o.temperatureC == null ? null : Fmt.celsius(o.temperatureC!),
              unavailableLabel: 'Temperature unavailable',
              accent: Palette.sun,
            ),
            right: MetricTile(
              icon: Icons.opacity,
              label: 'Humidity',
              value: o.humidityPct == null ? null : Fmt.percent(o.humidityPct!),
              unavailableLabel: 'Humidity unavailable',
              accent: Palette.water,
            ),
          ),

          const SizedBox(height: 18),
          if (c.canSetGrowthStage)
            GrowthStageButtons(controller: c)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: GrowthStagePill(o.growthStage),
            ),
          if (c.canControlPump) ...[
            const SizedBox(height: 16),
            PumpCard(controller: c),
          ],

          const SectionHeader(
            title: 'Next 12 hours',
            subtitle: 'Weather forecast',
            kind: DataKind.forecast,
          ),
          TileRow(
            left: MetricTile(
              icon: Icons.umbrella,
              label: 'Rain probability',
              value: o.rainProbability12hPct == null
                  ? null
                  : Fmt.percent(o.rainProbability12hPct!),
              unavailableLabel: 'Rain probability unavailable',
              accent: Palette.water,
            ),
            right: MetricTile(
              icon: Icons.grain,
              label: 'Forecast rainfall',
              value: o.rainfallForecast12hMm == null
                  ? null
                  : Fmt.mm(o.rainfallForecast12hMm!),
              unavailableLabel: 'Rainfall forecast unavailable',
              accent: Palette.water,
            ),
          ),
        ];
      },
    );
  }
}
