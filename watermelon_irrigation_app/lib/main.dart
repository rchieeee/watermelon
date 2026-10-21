import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/sample_field_repository.dart';
import 'data/field_data_repository.dart';
import 'data/firebase_field_repository.dart';
import 'firebase_options.dart';
import 'services/firebase_prediction_service.dart';
import 'services/irrigation_prediction_service.dart';
import 'services/field_control_service.dart';
import 'state/field_controller.dart';

enum DataSource { sample, csv, firebase }

/// sample   = generated design-preview data (shows a banner)
/// csv      = assets/data/watermelon_irrigation.csv
/// firebase = live readings from the ESP32
const dataSource = DataSource.firebase;

/// Same URL as FIREBASE_URL in the ESP32 sketch.
const firebaseDatabaseUrl =
    'https://watermelon-674c0-default-rtdb.asia-southeast1.firebasedatabase.app';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final FieldDataRepository repository;
  IrrigationPredictionService predictionService = const DatasetPredictionService();
  FieldControl? fieldControl;

  switch (dataSource) {
    case DataSource.sample:
      repository = const SampleFieldRepository();
    case DataSource.csv:
      repository = CsvAssetFieldRepository();
    case DataSource.firebase:
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      repository = FirebaseFieldRepository(database: database);
      // ML predictions from the Python service, with the ESP32's
      // decision table as a fallback.
      predictionService = FirebasePredictionService(database: database);
      fieldControl = FirebaseFieldControl(database: database);
  }

  final controller = FieldController(
    repository: repository,
    predictionService: predictionService,
    fieldControl: fieldControl,
  );
  controller.load();
  controller.startListening();

  runApp(WatermelonIrrigationApp(controller: controller));
}
