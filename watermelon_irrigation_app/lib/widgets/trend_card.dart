import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'data_kind.dart';
import 'layout.dart';

class TrendPoint {
  const TrendPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.title,
    required this.kind,
    required this.points,
    required this.format,
    required this.color,
    this.minBound,
    this.maxBound,
  });

  final String title;
  final DataKind kind;
  final List<TrendPoint> points;
  final String Function(double) format;
  final Color color;
  final double? minBound;
  final double? maxBound;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final enough = points.length >= 2 && points.first.time != points.last.time;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: t.titleMedium)),
            StatusTag(kind: kind),
          ]),
          if (!enough)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Not enough data in this period to show a trend.',
                  style: t.bodyLarge?.copyWith(color: Palette.muted)),
            )
          else ...[
            const SizedBox(height: 8),
            _Summary(points: points, format: format),
            const SizedBox(height: 14),
            SizedBox(height: 150, child: _chart()),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Fmt.shortDateTime(points.first.time),
                    style: t.bodyMedium?.copyWith(color: Palette.muted)),
                Text(Fmt.shortDateTime(points.last.time),
                    style: t.bodyMedium?.copyWith(color: Palette.muted)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chart() {
    final values = points.map((p) => p.value);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    var pad = (hi - lo) * 0.15;
    if (pad == 0) pad = hi.abs() * 0.1 + 1;
    var minY = lo - pad;
    var maxY = hi + pad;
    if (minBound != null) minY = math.max(minY, minBound!);
    if (maxBound != null) maxY = math.min(maxY, maxBound!);
    if (maxY <= minY) maxY = minY + 1;

    double x(DateTime t) => t.millisecondsSinceEpoch.toDouble();

    return LineChart(
      LineChartData(
        minX: x(points.first.time),
        maxX: x(points.last.time),
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 3,
          getDrawingHorizontalLine: (_) => FlLine(color: Palette.line, strokeWidth: 1),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Palette.ink,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${format(s.y)}\n'
                      '${Fmt.shortDateTime(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                      const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ))
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points.map((p) => FlSpot(x(p.time), p.value)).toList(),
            isCurved: false,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: points.length <= 24),
            belowBarData: BarAreaData(show: true, color: color.withAlpha(30)),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.points, required this.format});
  final List<TrendPoint> points;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final values = points.map((p) => p.value);
    return Wrap(
      spacing: 18,
      runSpacing: 4,
      children: [
        Text('Latest ${format(points.last.value)}', style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text('Lowest ${format(values.reduce(math.min))}',
            style: t.bodyLarge?.copyWith(color: Palette.muted)),
        Text('Highest ${format(values.reduce(math.max))}',
            style: t.bodyLarge?.copyWith(color: Palette.muted)),
      ],
    );
  }
}
