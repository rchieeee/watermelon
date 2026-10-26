/// One soil sensor's latest reading, from irrigation/sensors/soil_N/live.
/// Sensor 1 is on the main ESP32; sensors 2 and 3 are separate node boards.
class SoilSensorReading {
  const SoilSensorReading({
    required this.number,
    required this.timestamp,
    this.moisturePct,
  });

  /// 1, 2 or 3.
  final int number;
  final DateTime timestamp;

  /// Null when the sensor's reading was out of range (wiring problem).
  final double? moisturePct;
}

/// What the Soil moisture card shows for one sensor.
class SoilSensorStatus {
  const SoilSensorStatus({required this.number, required this.online, this.moisturePct});

  final int number;

  /// False when the sensor has not reported recently (board off or no Wi-Fi).
  final bool online;

  /// Null when offline, never reported, or the reading was invalid.
  final double? moisturePct;
}
