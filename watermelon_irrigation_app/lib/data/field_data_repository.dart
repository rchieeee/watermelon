import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/field_observation.dart';

/// Where field observations come from. The prototype reads a CSV asset;
/// a Firebase or REST implementation can replace it without touching the UI.
abstract class FieldDataRepository {
  /// All observations, sorted oldest to newest.
  Future<List<FieldObservation>> loadObservations();
}

/// A source that can also say when its data has changed, so the app
/// refreshes without the farmer pulling down.
abstract class LiveFieldRepository implements FieldDataRepository {
  /// Fires when data other than the live reading changes.
  Stream<void> get changes;

  /// Each new live reading from the field controller, as it arrives.
  Stream<FieldObservation> get liveReadings;
}

class DatasetNotFoundException implements Exception {
  DatasetNotFoundException(this.path);
  final String path;
  @override
  String toString() => 'Dataset not found at $path';
}

class CsvAssetFieldRepository implements FieldDataRepository {
  CsvAssetFieldRepository({
    this.assetPath = 'assets/data/watermelon_irrigation.csv',
    AssetBundle? bundle,
  }) : _bundle = bundle;

  final String assetPath;
  final AssetBundle? _bundle;

  @override
  Future<List<FieldObservation>> loadObservations() async {
    final String raw;
    try {
      raw = await (_bundle ?? rootBundle).loadString(assetPath);
    } catch (_) {
      throw DatasetNotFoundException(assetPath);
    }
    return parseCsv(raw);
  }

  static const _missingMarkers = {'na', 'n/a', 'nan', 'null', 'none', '-'};

  static List<FieldObservation> parseCsv(String raw) {
    final text = raw
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (text.isEmpty) return [];

    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(text);
    if (rows.length < 2) return [];

    final header =
        rows.first.map((c) => c.toString().trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);

    final iTimestamp = col('timestamp');
    if (iTimestamp < 0) {
      throw const FormatException('The "timestamp" column is missing.');
    }
    final iSoil = col('soil_moisture_pct');
    final iTemp = col('temperature_c');
    final iHum = col('humidity_pct');
    final iRainProb = col('rain_probability_12h_pct');
    final iRainMm = col('rainfall_forecast_12h_mm');
    final iStage = col('growth_stage');
    final iNeeded = col('irrigation_needed');
    final iDuration = col('watering_duration_min');
    final iNext = col('next_irrigation_hours');

    String? cell(List<dynamic> row, int i) {
      if (i < 0 || i >= row.length) return null;
      final v = row[i].toString().trim();
      if (v.isEmpty || _missingMarkers.contains(v.toLowerCase())) return null;
      return v;
    }

    double? number(List<dynamic> row, int i) {
      final v = cell(row, i);
      return v == null ? null : double.tryParse(v);
    }

    int? flag(List<dynamic> row, int i) {
      final v = cell(row, i)?.toLowerCase();
      if (v == null) return null;
      if (v == 'true' || v == 'yes') return 1;
      if (v == 'false' || v == 'no') return 0;
      final n = double.tryParse(v);
      if (n == null) return null;
      if (n == 1) return 1;
      if (n == 0) return 0;
      return null;
    }

    final observations = <FieldObservation>[];
    for (final row in rows.skip(1)) {
      final ts = parseTimestamp(cell(row, iTimestamp));
      if (ts == null) continue; // a row without a valid time can't be placed
      observations.add(FieldObservation(
        timestamp: ts,
        soilMoisturePct: number(row, iSoil),
        temperatureC: number(row, iTemp),
        humidityPct: number(row, iHum),
        rainProbability12hPct: number(row, iRainProb),
        rainfallForecast12hMm: number(row, iRainMm),
        growthStage: cell(row, iStage),
        irrigationNeeded: flag(row, iNeeded),
        wateringDurationMin: number(row, iDuration),
        nextIrrigationHours: number(row, iNext),
      ));
    }
    observations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return observations;
  }

  static final _fallbackFormats = [
    DateFormat('M/d/yyyy H:mm:ss'),
    DateFormat('M/d/yyyy H:mm'),
    DateFormat('M/d/yyyy h:mm a'),
    DateFormat('M/d/yyyy'),
  ];

  static DateTime? parseTimestamp(String? value) {
    if (value == null) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.isUtc ? iso.toLocal() : iso;
    for (final format in _fallbackFormats) {
      try {
        return format.parseStrict(value);
      } catch (_) {}
    }
    return null;
  }
}
