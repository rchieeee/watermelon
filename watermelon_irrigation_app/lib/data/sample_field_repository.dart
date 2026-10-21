import 'dart:math';

import '../models/field_observation.dart';
import 'field_data_repository.dart';

/// Design preview only: generates 7 days of plausible hourly readings ending
/// now, so every screen can be shown before the real dataset exists.
class SampleFieldRepository implements FieldDataRepository {
  const SampleFieldRepository();

  @override
  Future<List<FieldObservation>> loadObservations() async {
    final rng = Random(42);
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, now.hour);
    const hours = 7 * 24;

    var soil = 72.0;
    final observations = <FieldObservation>[];
    for (var i = hours - 1; i >= 0; i--) {
      final t = end.subtract(Duration(hours: i));
      final dayCycle = sin((t.hour - 9) / 24 * 2 * pi); // warmest mid-afternoon
      final temp = 27 + 5 * dayCycle + rng.nextDouble() * 1.2;
      final humidity = 74 - 12 * dayCycle + rng.nextDouble() * 4;
      final rainProb = (20 + 25 * sin(i / 30) + rng.nextDouble() * 10).clamp(0, 100);
      final rainMm = rainProb > 40 ? rng.nextDouble() * 4 : rng.nextDouble() * 0.8;

      // Soil dries faster in the heat; irrigate when it drops below 55%.
      soil -= 0.35 + max(0, dayCycle) * 0.5 + rng.nextDouble() * 0.2;
      final needed = soil < 55;
      if (needed) soil = 75 + rng.nextDouble() * 5;

      observations.add(FieldObservation(
        timestamp: t,
        soilMoisturePct: double.parse(soil.toStringAsFixed(1)),
        temperatureC: double.parse(temp.toStringAsFixed(1)),
        humidityPct: double.parse(humidity.toStringAsFixed(1)),
        rainProbability12hPct: rainProb.roundToDouble(),
        rainfallForecast12hMm: double.parse(rainMm.toStringAsFixed(1)),
        growthStage: 'flowering',
        irrigationNeeded: needed ? 1 : 0,
        wateringDurationMin: needed ? 18 : 0,
        nextIrrigationHours: ((soil - 55) / 0.6).clamp(1, 48).roundToDouble(),
      ));
    }

    // Make the latest reading call for water so the recommendation card is shown.
    final last = observations.removeLast();
    observations.add(FieldObservation(
      timestamp: last.timestamp,
      soilMoisturePct: 54.2,
      temperatureC: last.temperatureC,
      humidityPct: last.humidityPct,
      rainProbability12hPct: 15,
      rainfallForecast12hMm: 0.4,
      growthStage: 'flowering',
      irrigationNeeded: 1,
      wateringDurationMin: 18,
      nextIrrigationHours: 3,
    ));
    return observations;
  }
}
