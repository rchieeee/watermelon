import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../models/field_observation.dart';
import '../models/soil_sensor_reading.dart';
import 'field_data_repository.dart';

/// Reads the ESP32's readings from Firebase Realtime Database.
///
/// Database layout (written by the ESP32 sketch):
///   irrigation/live                 latest reading
///   irrigation/history/{pushId}     saved readings
///   irrigation/settings/growth_stage   set by the farmer (text)
///   irrigation/prediction           written by the ML service
///   irrigation/sensors/soil_N/live  each soil sensor (N = 1..3); soil_1 is
///                                   the main ESP32, 2 and 3 are node boards
class FirebaseFieldRepository implements LiveFieldRepository {
  FirebaseFieldRepository({
    required FirebaseDatabase database,
    this.historyLimit = 3000,
    this.soilSensorCount = 3,
  }) : _db = database;

  final FirebaseDatabase _db;
  final int soilSensorCount;

  /// 3000 entries at one per 15 minutes is about 30 days.
  final int historyLimit;

  DatabaseReference get _root => _db.ref('irrigation');

  /// Growth stage from the last full load, attached to live readings.
  String? _stage;

  /// The ESP32 writes irrigation/live every 2 seconds and whenever the pump
  /// turns on or off, so the app can show soil and pump state in realtime.
  @override
  Stream<FieldObservation> get liveReadings => _root
      .child('live')
      .onValue
      .map((e) => _parse(e.snapshot.value, _stage))
      .where((o) => o != null)
      .cast<FieldObservation>();

  /// Each sensor board writes irrigation/sensors/soil_N/live every 5 seconds.
  @override
  Stream<SoilSensorReading> get soilSensorReadings {
    final subs = <StreamSubscription<DatabaseEvent>>[];
    late final StreamController<SoilSensorReading> controller;
    controller = StreamController<SoilSensorReading>(
      onListen: () {
        for (var n = 1; n <= soilSensorCount; n++) {
          subs.add(_root.child('sensors/soil_$n/live').onValue.listen((e) {
            final r = _parseSensor(n, e.snapshot.value);
            if (r != null) controller.add(r);
          }));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  static SoilSensorReading? _parseSensor(int number, Object? value) {
    if (value is! Map) return null;
    final ts = value['timestamp'];
    if (ts is! num) return null;
    final pct = value['soil_moisture_pct'];
    return SoilSensorReading(
      number: number,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
      moisturePct: pct is num ? pct.toDouble() : null,
    );
  }

  /// Fires when the ML service writes a new prediction or the growth stage
  /// changes. Live readings come through [liveReadings] instead.
  @override
  Stream<void> get changes {
    StreamSubscription<DatabaseEvent>? prediction;
    StreamSubscription<DatabaseEvent>? stage;
    late final StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        prediction = _root.child('prediction').onValue.listen((_) => controller.add(null));
        stage = _root.child('settings/growth_stage').onValue.listen((_) => controller.add(null));
      },
      onCancel: () async {
        await prediction?.cancel();
        await stage?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<FieldObservation>> loadObservations() async {
    final results = await Future.wait([
      _root.child('history').orderByKey().limitToLast(historyLimit).get(),
      _root.child('live').get(),
      _root.child('settings/growth_stage').get(),
    ]);

    final stageValue = results[2].value;
    final stage = stageValue == null ? null : stageValue.toString();
    _stage = stage;

    final observations = <FieldObservation>[];
    for (final child in results[0].children) {
      final o = _parse(child.value, stage);
      if (o != null) observations.add(o);
    }

    final live = _parse(results[1].value, stage);
    if (live != null &&
        (observations.isEmpty || live.timestamp.isAfter(observations.last.timestamp))) {
      observations.add(live);
    }

    observations.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return observations;
  }

  static FieldObservation? _parse(Object? value, String? stage) {
    if (value is! Map) return null;
    final ts = value['timestamp'];
    if (ts is! num) return null;

    double? number(String key) {
      final v = value[key];
      return v is num ? v.toDouble() : null;
    }

    final needed = value['irrigation_needed'];
    final pump = value['pump_on'];

    return FieldObservation(
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
      soilMoisturePct: number('soil_moisture_pct'),
      temperatureC: number('temperature_c'),
      humidityPct: number('humidity_pct'),
      rainProbability12hPct: number('rain_probability_12h_pct'),
      rainfallForecast12hMm: number('rainfall_forecast_12h_mm'),
      growthStage: stage,
      irrigationNeeded: needed is num ? needed.toInt() : null,
      wateringDurationMin: number('watering_duration_min'),
      nextIrrigationHours: number('next_irrigation_hours'),
      pumpOn: pump is bool ? pump : null,
    );
  }
}
