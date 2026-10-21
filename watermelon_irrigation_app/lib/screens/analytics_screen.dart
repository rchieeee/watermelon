import 'package:flutter/material.dart';

import '../models/field_observation.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/data_kind.dart';
import '../widgets/field_page.dart';
import '../widgets/layout.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/trend_card.dart';

enum TrendRange { day, week, month }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  TrendRange _range = TrendRange.day;

  /// Only offer ranges the data can actually fill. A 30-day view of
  /// 5 days of data would look identical to the 7-day view.
  static List<TrendRange> _availableRanges(List<FieldObservation> h) {
    if (h.isEmpty) return const [];
    final span = h.last.timestamp.difference(h.first.timestamp);
    return [
      TrendRange.day,
      if (span > const Duration(days: 1)) TrendRange.week,
      if (span > const Duration(days: 7)) TrendRange.month,
    ];
  }

  /// Ranges are anchored to the newest reading, so older datasets
  /// still show their real data instead of an empty chart.
  static List<FieldObservation> _window(List<FieldObservation> h, TrendRange r) {
    final anchor = h.last.timestamp;
    return switch (r) {
      TrendRange.day =>
        h.where((o) => DateUtils.isSameDay(o.timestamp, anchor)).toList(),
      TrendRange.week => h
          .where((o) => !o.timestamp.isBefore(anchor.subtract(const Duration(days: 7))))
          .toList(),
      TrendRange.month => h
          .where((o) => !o.timestamp.isBefore(anchor.subtract(const Duration(days: 30))))
          .toList(),
    };
  }

  static String _label(TrendRange r, DateTime anchor) => switch (r) {
        TrendRange.day =>
          DateUtils.isSameDay(anchor, DateTime.now()) ? 'Today' : 'Latest day',
        TrendRange.week => 'Last 7 days',
        TrendRange.month => 'Last 30 days',
      };

  static List<TrendPoint> _series(
      List<FieldObservation> w, double? Function(FieldObservation) pick) {
    return [
      for (final o in w)
        if (pick(o) != null) TrendPoint(o.timestamp, pick(o)!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FieldPage(
      title: 'Analytics',
      builder: (context, c) {
        final t = Theme.of(context).textTheme;
        final history = c.history;

        if (history.length < 2) {
          return [
            const SizedBox(height: 40),
            Center(
              child: Text('No historical data available yet.',
                  style: t.titleLarge, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Trends appear once there are at least two readings.',
                  style: t.bodyLarge?.copyWith(color: Palette.muted),
                  textAlign: TextAlign.center),
            ),
          ];
        }

        final ranges = _availableRanges(history);
        final range = ranges.contains(_range) ? _range : ranges.first;
        final w = _window(history, range);
        final anchor = history.last.timestamp;

        return [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TrendRange>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Palette.rind,
                selectedForegroundColor: Colors.white,
                foregroundColor: Palette.ink,
                minimumSize: const Size.fromHeight(48),
                textStyle: t.labelLarge,
              ),
              segments: [
                for (final r in ranges)
                  ButtonSegment(value: r, label: Text(_label(r, anchor))),
              ],
              selected: {range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            w.isEmpty ? '' : Fmt.period(w.first.timestamp, w.last.timestamp),
            style: t.bodyLarge?.copyWith(color: Palette.muted),
          ),
          const SectionHeader(title: 'Field readings'),
          TrendCard(
            title: 'Soil moisture',
            kind: DataKind.historical,
            points: _series(w, (o) => o.soilMoisturePct),
            format: Fmt.percent,
            color: Palette.leaf,
            minBound: 0,
            maxBound: 100,
          ),
          const SizedBox(height: 12),
          TrendCard(
            title: 'Temperature',
            kind: DataKind.historical,
            points: _series(w, (o) => o.temperatureC),
            format: Fmt.celsius,
            color: Palette.sun,
          ),
          const SizedBox(height: 12),
          TrendCard(
            title: 'Humidity',
            kind: DataKind.historical,
            points: _series(w, (o) => o.humidityPct),
            format: Fmt.percent,
            color: Palette.water,
            minBound: 0,
            maxBound: 100,
          ),
          const SectionHeader(title: 'Weather forecasts'),
          TrendCard(
            title: 'Rain probability',
            kind: DataKind.forecast,
            points: _series(w, (o) => o.rainProbability12hPct),
            format: Fmt.percent,
            color: Palette.water,
            minBound: 0,
            maxBound: 100,
          ),
          const SizedBox(height: 12),
          TrendCard(
            title: 'Forecast rainfall',
            kind: DataKind.forecast,
            points: _series(w, (o) => o.rainfallForecast12hMm),
            format: Fmt.mm,
            color: Palette.water,
            minBound: 0,
          ),
          if (showPrediction) ...[
            const SectionHeader(title: 'Irrigation predictions'),
            TrendCard(
              title: 'Watering duration',
              kind: DataKind.predicted,
              points: _series(w, (o) => o.wateringDurationMin),
              format: Fmt.minutes,
              color: Palette.rind,
              minBound: 0,
            ),
            const SizedBox(height: 12),
            TrendCard(
              title: 'Next irrigation',
              kind: DataKind.predicted,
              points: _series(w, (o) => o.nextIrrigationHours),
              format: Fmt.hours,
              color: Palette.rind,
              minBound: 0,
            ),
          ],
        ];
      },
    );
  }
}
