// Soil sensor pin test - ESP32 DevKit V1
// Reads every ADC1 pin once per second and prints the raw value (0-4095)
// and the voltage in millivolts. Use it to find which pin, if any, the soil
// sensor's yellow AOUT wire is really connected to.
//
// What to expect (Serial Monitor at 115200):
//   - The pin with the sensor: about 2500-3500 raw (about 2.5-3.0 V) in air,
//     and it DROPS (about 1000-1500 mV) when the sensor is put in water.
//   - Pins with nothing connected: random or jumpy values, or 0.
//   - Every pin stuck at 0: the sensor has no power, or AOUT is not reaching
//     the ESP32 at all.
//
// Wi-Fi is not used here, so nothing else affects the readings.

#include <Arduino.h>

// All ADC1 pins on the 30-pin DevKit. 36 and 39 are labeled VP and VN.
const int PINS[] = {32, 33, 34, 35, 36, 39};
const int PIN_COUNT = sizeof(PINS) / sizeof(PINS[0]);
const int SAMPLES = 10;  // Readings averaged per pin, to reduce noise.

void setup() {
  Serial.begin(115200);
  delay(1000);
  analogReadResolution(12);  // 0-4095
  for (int i = 0; i < PIN_COUNT; i++) {
    pinMode(PINS[i], INPUT);
    analogSetPinAttenuation(PINS[i], ADC_11db);  // Full 0-3.3 V range.
  }
  Serial.println();
  Serial.println("Soil pin test: in air the sensor pin should read ~2500-3500 raw,");
  Serial.println("and drop when the sensor is put in water.");
}

void loop() {
  for (int i = 0; i < PIN_COUNT; i++) {
    long rawSum = 0, mvSum = 0;
    for (int n = 0; n < SAMPLES; n++) {
      rawSum += analogRead(PINS[i]);
      mvSum += analogReadMilliVolts(PINS[i]);
      delay(2);
    }
    Serial.printf("GPIO%d: %4ld raw %4ld mV   ", PINS[i], rawSum / SAMPLES, mvSum / SAMPLES);
  }
  Serial.println();
  delay(1000);
}
