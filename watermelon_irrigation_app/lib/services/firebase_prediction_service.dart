import 'package:firebase_database/firebase_database.dart';

import '../models/field_observation.dart';
import '../models/irrigation_prediction.dart';
import 'irrigation_prediction_service.dart';

/// Reads the ML service's result from irrigation/prediction.
///
/// The ML prediction is used only when it was made from the SAME reading
/// the app is showing. Otherwise (service not running, prediction still
/// being computed, or a sensor value missing) the app falls back to the
/// ESP32's own decision-table result, so the farmer always sees a
/// recommendation that matches the latest reading.
class FirebasePredictionService implements IrrigationPredictionService {
  FirebasePredictionService({
    required FirebaseDatabase database,
    this.maxTimeGap = const Duration(minutes: 1),
  }) : _db = database;

  final FirebaseDatabase _db;
  final Duration maxTimeGap;

  @override
  Future<IrrigationPrediction?> predict(FieldObservation observation) async {
    try {
      final snapshot = await _db.ref('irrigation/prediction').get();
      final ml = _fromModel(snapshot.value, observation);
      if (ml != null) return ml;
    } catch (_) {
      // Network problem: use the fallback below.
    }
    return _fromController(observation);
  }

  IrrigationPrediction? _fromModel(Object? value, FieldObservation o) {
    if (value is! Map) return null;
    if (value['status'] == 'UNAVAILABLE') return null;

    final basedOn = value['based_on'];
    if (basedOn is! num) return null;
    final predictionFor = DateTime.fromMillisecondsSinceEpoch(basedOn.toInt());
    if (predictionFor.difference(o.timestamp).abs() > maxTimeGap) return null;

    final needed = value['irrigation_needed'];
    if (needed is! num) return null;

    double? number(String key) {
      final v = value[key];
      return v is num ? v.toDouble() : null;
    }

    return IrrigationPrediction(
      irrigationNeeded: needed == 1,
      wateringDurationMin: number('watering_duration_min'),
      nextIrrigationHours: number('next_irrigation_hours'),
      basedOn: o.timestamp,
      source: PredictionSource.model,
    );
  }

  /// The ESP32's decision table. It has no duration estimate, because the
  /// controller waters until the soil reaches its target.
  IrrigationPrediction? _fromController(FieldObservation o) {
    final needed = o.irrigationNeeded;
    if (needed == null) return null;
    return IrrigationPrediction(
      irrigationNeeded: needed == 1,
      wateringDurationMin: needed == 1 ? null : 0,
      nextIrrigationHours: needed == 1 ? 0 : o.nextIrrigationHours,
      basedOn: o.timestamp,
      source: PredictionSource.controller,
    );
  }
}
