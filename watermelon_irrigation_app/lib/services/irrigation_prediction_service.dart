import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/field_observation.dart';
import '../models/irrigation_prediction.dart';

/// The single place the app asks for irrigation outputs.
/// Swap the implementation to connect a trained model; the UI stays the same.
abstract class IrrigationPredictionService {
  /// Returns null when no prediction is available. The app never
  /// generates a recommendation on its own.
  Future<IrrigationPrediction?> predict(FieldObservation observation);
}

/// Prototype: uses the prediction values already recorded in the dataset.
class DatasetPredictionService implements IrrigationPredictionService {
  const DatasetPredictionService();

  @override
  Future<IrrigationPrediction?> predict(FieldObservation observation) async {
    final needed = observation.irrigationNeeded;
    if (needed == null) return null;
    return IrrigationPrediction(
      irrigationNeeded: needed == 1,
      wateringDurationMin: observation.wateringDurationMin,
      nextIrrigationHours: observation.nextIrrigationHours,
      basedOn: observation.timestamp,
      source: PredictionSource.dataset,
    );
  }
}

/// For later: sends the six inputs to a model server.
///
/// Expected request body:
///   {"soil_moisture_pct": 68, "temperature_c": 29, "humidity_pct": 78,
///    "rain_probability_12h_pct": 20, "rainfall_forecast_12h_mm": 2,
///    "growth_stage": "flowering"}
/// Expected response body:
///   {"irrigation_needed": 1, "watering_duration_min": 18,
///    "next_irrigation_hours": 3}
class ApiPredictionService implements IrrigationPredictionService {
  ApiPredictionService(this.endpoint, {http.Client? client})
      : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<IrrigationPrediction?> predict(FieldObservation o) async {
    if (!o.hasAllModelInputs) return null;
    try {
      final response = await _client
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'soil_moisture_pct': o.soilMoisturePct,
              'temperature_c': o.temperatureC,
              'humidity_pct': o.humidityPct,
              'rain_probability_12h_pct': o.rainProbability12hPct,
              'rainfall_forecast_12h_mm': o.rainfallForecast12hMm,
              'growth_stage': o.growthStage,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final needed = json['irrigation_needed'];
      if (needed is! num) return null;
      return IrrigationPrediction(
        irrigationNeeded: needed == 1,
        wateringDurationMin: (json['watering_duration_min'] as num?)?.toDouble(),
        nextIrrigationHours: (json['next_irrigation_hours'] as num?)?.toDouble(),
        basedOn: o.timestamp,
        source: PredictionSource.model,
      );
    } catch (_) {
      return null;
    }
  }
}
