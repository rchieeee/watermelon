/// One row of the dataset. Every field except [timestamp] may be missing,
/// and missing values stay null so the UI can show an "unavailable" state
/// instead of a made-up number.
class FieldObservation {
  const FieldObservation({
    required this.timestamp,
    this.soilMoisturePct,
    this.temperatureC,
    this.humidityPct,
    this.rainProbability12hPct,
    this.rainfallForecast12hMm,
    this.growthStage,
    this.irrigationNeeded,
    this.wateringDurationMin,
    this.nextIrrigationHours,
    this.pumpOn,
  });

  final DateTime timestamp;

  // Monitoring / input data
  /// From the field's single soil moisture sensor.
  final double? soilMoisturePct;
  final double? temperatureC;
  final double? humidityPct;
  final double? rainProbability12hPct;
  final double? rainfallForecast12hMm;
  final String? growthStage;

  // Prediction / recommendation outputs recorded in the dataset
  final int? irrigationNeeded;
  final double? wateringDurationMin;
  final double? nextIrrigationHours;

  /// Whether the field controller's pump was running at this reading.
  final bool? pumpOn;

  /// True when all six model inputs are present.
  bool get hasAllModelInputs =>
      soilMoisturePct != null &&
      temperatureC != null &&
      humidityPct != null &&
      rainProbability12hPct != null &&
      rainfallForecast12hMm != null &&
      growthStage != null;
}
