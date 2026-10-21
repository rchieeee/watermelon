import 'package:firebase_database/firebase_database.dart';

/// Sends the farmer's commands and settings to the field system.
abstract class FieldControl {
  /// Asks the controller (ESP32) to turn the pump off now.
  Future<void> requestStop();

  /// Asks the controller (ESP32) to start watering now.
  Future<void> requestStart();

  /// Withdraws an ON request the controller never picked up, so the pump
  /// does not start by surprise when the controller comes back online.
  Future<void> cancelStart();

  /// Saves the crop's growth stage, which the ML model uses.
  Future<void> setGrowthStage(String stage);
}

class FirebaseFieldControl implements FieldControl {
  FirebaseFieldControl({required FirebaseDatabase database}) : _db = database;

  final FirebaseDatabase _db;

  /// The ESP32 checks irrigation/control/stop_request every few seconds
  /// even when it thinks the pump is off, forces the relay off and clears it.
  @override
  Future<void> requestStop() =>
      _db.ref('irrigation/control/stop_request').set(ServerValue.timestamp);

  /// The ESP32 checks irrigation/control every 2 seconds. A pump turned on
  /// here ignores soil moisture and stays on until [requestStop] (with a
  /// 30-minute safety limit in case the phone loses internet).
  @override
  Future<void> requestStart() =>
      _db.ref('irrigation/control/start_request').set(ServerValue.timestamp);

  @override
  Future<void> cancelStart() => _db.ref('irrigation/control/start_request').remove();

  @override
  Future<void> setGrowthStage(String stage) =>
      _db.ref('irrigation/settings/growth_stage').set(stage);
}
