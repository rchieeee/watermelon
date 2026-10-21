/// Where a prediction came from.
///  dataset    = values recorded in a CSV / sample dataset
///  model      = the machine learning service (irrigation/prediction)
///  controller = the ESP32's decision table (fallback when ML is unavailable)
enum PredictionSource { dataset, model, controller }

/// The three irrigation outputs: classification + two regressions.
class IrrigationPrediction {
  const IrrigationPrediction({
    required this.irrigationNeeded,
    required this.basedOn,
    required this.source,
    this.wateringDurationMin,
    this.nextIrrigationHours,
  });

  final bool irrigationNeeded;
  final double? wateringDurationMin;
  final double? nextIrrigationHours;

  /// Timestamp of the observation this prediction was made from.
  final DateTime basedOn;
  final PredictionSource source;
}
