import 'package:flutter/material.dart';

import '../models/irrigation_prediction.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'data_kind.dart';
import 'layout.dart';

/// The strongest element in the app: answers "do I need to irrigate?"
/// Hides the ML prediction everywhere (recommendation cards and predicted
/// trends) while the app focuses on soil moisture. Set to true to show it again.
const showPrediction = true;

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.prediction, this.detailed = false});

  final IrrigationPrediction? prediction;

  /// The Irrigation screen shows the explicit Yes/No line as well.
  final bool detailed;

  static Color colorFor(IrrigationPrediction? p) {
    if (p == null) return Palette.stone;
    return p.irrigationNeeded ? Palette.water : Palette.rind;
  }

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    if (p == null) return const _UnavailableRecommendation();

    final t = Theme.of(context).textTheme;
    final needed = p.irrigationNeeded;
    final soft = Colors.white.withAlpha(215);

    return Semantics(
      container: true,
      label: needed ? 'Irrigation needed' : 'Irrigation not needed',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          color: colorFor(p),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  detailed ? 'Current recommendation' : 'Irrigation recommendation',
                  style: t.titleMedium?.copyWith(color: soft),
                ),
              ),
              const StatusTag(kind: DataKind.predicted, onDark: true),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Icon(needed ? Icons.water_drop : Icons.check_circle,
                  color: Colors.white, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  needed ? 'IRRIGATION NEEDED' : 'IRRIGATION NOT NEEDED',
                  style: t.titleLarge?.copyWith(color: Colors.white, fontSize: 22),
                ),
              ),
            ]),
            if (detailed) ...[
              const SizedBox(height: 4),
              Text('Irrigation needed: ${needed ? 'Yes' : 'No'}',
                  style: t.bodyLarge?.copyWith(color: soft)),
            ],
            const SizedBox(height: 18),
            if (needed) _NeededBody(p) else _NotNeededBody(p),
            const SizedBox(height: 16),
            Text('Based on the reading from ${Fmt.updated(p.basedOn)}',
                style: t.bodyMedium?.copyWith(color: soft)),
            if (_sourceLabel(p.source) != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_sourceLabel(p.source)!,
                    style: t.bodyMedium?.copyWith(color: soft)),
              ),
          ],
        ),
      ),
    );
  }
}

String? _sourceLabel(PredictionSource source) => switch (source) {
      PredictionSource.model => 'Estimated by the irrigation model',
      PredictionSource.controller => "From the field controller's rules",
      PredictionSource.dataset => null,
    };

class _NeededBody extends StatelessWidget {
  const _NeededBody(this.p);
  final IrrigationPrediction p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final soft = Colors.white.withAlpha(215);
    final duration = p.wateringDurationMin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (duration != null) ...[
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: Fmt.number(duration),
                  style: t.displayLarge?.copyWith(color: Colors.white)),
              TextSpan(
                  text: ' min',
                  style: t.titleLarge?.copyWith(color: Colors.white, fontSize: 26)),
            ]),
          ),
          const SizedBox(height: 4),
          Text('Recommended watering duration', style: t.bodyLarge?.copyWith(color: soft)),
        ] else
          const UnavailableText('Watering duration unavailable', onDark: true),
        const SizedBox(height: 16),
        Divider(color: Colors.white.withAlpha(70)),
        const SizedBox(height: 14),
        _NextIrrigation(hours: p.nextIrrigationHours),
      ],
    );
  }
}

class _NotNeededBody extends StatelessWidget {
  const _NotNeededBody(this.p);
  final IrrigationPrediction p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final soft = Colors.white.withAlpha(215);
    final h = p.nextIrrigationHours;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No watering is required right now.', style: t.bodyLarge?.copyWith(color: soft)),
        const SizedBox(height: 16),
        if (h != null) ...[
          Text('Next irrigation', style: t.bodyLarge?.copyWith(color: soft)),
          Text(
            h <= 0 ? 'Now' : Fmt.nextIrrigation(h).replaceFirst('in ', ''),
            style: t.headlineMedium?.copyWith(color: Colors.white, fontSize: 40),
          ),
        ] else
          const UnavailableText('Next irrigation time unavailable', onDark: true),
      ],
    );
  }
}

class _NextIrrigation extends StatelessWidget {
  const _NextIrrigation({required this.hours});
  final double? hours;

  @override
  Widget build(BuildContext context) {
    final h = hours;
    if (h == null) {
      return const UnavailableText('Next irrigation time unavailable', onDark: true);
    }
    return Row(children: [
      const Icon(Icons.schedule, color: Colors.white, size: 24),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'Next irrigation ${Fmt.nextIrrigation(h)}',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
      ),
    ]);
  }
}

class _UnavailableRecommendation extends StatelessWidget {
  const _UnavailableRecommendation();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.all(22),
      borderColor: Palette.stone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline, color: Palette.stone, size: 30),
          const SizedBox(height: 10),
          Text('Irrigation recommendation unavailable', style: t.titleLarge),
          const SizedBox(height: 6),
          Text(
            'There is no irrigation prediction for the latest reading. '
            'Check again after the next update.',
            style: t.bodyLarge?.copyWith(color: Palette.muted),
          ),
        ],
      ),
    );
  }
}
