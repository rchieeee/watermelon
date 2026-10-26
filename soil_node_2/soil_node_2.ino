// Soil sensor node - ESP32 + 1 capacitive soil moisture sensor v2.0
// Reads one soil sensor and saves it to Firebase Realtime Database:
//   /irrigation/sensors/soil_<NODE_ID>/live          latest reading (every 5 s)
//   /irrigation/sensors/soil_<NODE_ID>/history/{id}  saved reading (every 60 s)
// The main ESP32 (smart_irrigation_esp32) averages this with the other
// sensors to decide the pump, and the mobile app shows each sensor.
// This node has no pump, relay, DHT or OLED.
//
// Wiring (breadboard):  sensor VCC -> 3V3,  GND -> GND,  AOUT -> D34
// Serial Monitor (115200): s = status, f = send to Firebase now.
// ArduinoJson v7 required.

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Wi-Fi name/password are in secrets.h, which is not pushed to GitHub.
// Copy secrets.example.h to secrets.h and fill it in.
#include "secrets.h"

// ---- Which sensor this board is ----
// 1 is the main ESP32. Use 2 or 3 here; each board needs a different number.
const int NODE_ID = 2;

const char* FIREBASE_URL =
    "https://watermelon-674c0-default-rtdb.asia-southeast1.firebasedatabase.app";

// ---- Soil sensor ----
// AOUT must be on an ADC1 pin (GPIO32-39): ADC2 pins stop working with Wi-Fi.
const int SOIL_PIN = 34;
// Calibration (raw analogRead, 0-4095). Send 's' with the sensor in dry air
// for SOIL_DRY_RAW, then in water for SOIL_WET_RAW. Higher raw = drier.
const int SOIL_DRY_RAW = 3200;   // 0% moisture
const int SOIL_WET_RAW = 1300;   // 100% moisture
const int SOIL_SAMPLES = 10;     // Readings averaged per measurement.
// Outside this range the sensor is unplugged or shorted: no % is sent.
const int RAW_MIN_VALID = 100, RAW_MAX_VALID = 4000;

// ---- Timing ----
const uint32_t READ_INTERVAL_MS = 1000;           // Read the sensor every 1 s.
const uint32_t LIVE_INTERVAL_MS = 5UL * 1000;     // Send live reading every 5 s.
const uint32_t HISTORY_INTERVAL_MS = 60UL * 1000; // Save history every 60 s.
const uint32_t WIFI_RETRY_MS = 30UL * 1000;

int soilRaw = -1;      // Averaged raw value; -1 = not read yet.
int soilPercent = -1;  // 0-100%; -1 = invalid reading.
uint32_t lastReadAt = 0, lastLiveAt = 0, lastHistoryAt = 0, lastWifiTry = 0;
bool liveSent = false, historySent = false;

String nodePath() { return "/irrigation/sensors/soil_" + String(NODE_ID); }

// Reads the sensor SOIL_SAMPLES times and returns the average raw value.
int readSoilRaw() {
  long sum = 0;
  for (int n = 0; n < SOIL_SAMPLES; n++) {
    sum += analogRead(SOIL_PIN);
    delay(10);
  }
  return sum / SOIL_SAMPLES;
}

// Converts raw to 0-100%, or -1 when the raw value is out of range.
int soilRawToPercent(int raw) {
  if (raw < RAW_MIN_VALID || raw > RAW_MAX_VALID) return -1;
  return constrain(map(raw, SOIL_DRY_RAW, SOIL_WET_RAW, 0, 100), 0, 100);
}

// One HTTPS connection to Firebase, kept open and reused.
WiFiClientSecure fbClient;
HTTPClient fbHttp;
bool fbReady = false;

bool firebaseSend(const char* method, const String& path, const String& json) {
  if (WiFi.status() != WL_CONNECTED) return false;
  if (!fbReady) {
    fbClient.setInsecure(); // Prototype only: HTTPS certificate is not verified.
    fbHttp.setReuse(true);
    fbReady = true;
  }
  if (!fbHttp.begin(fbClient, String(FIREBASE_URL) + path + ".json")) return false;
  fbHttp.setTimeout(5000);
  fbHttp.addHeader("Content-Type", "application/json");
  int code = fbHttp.sendRequest(method, json);
  fbHttp.end();
  if (code < 0) fbClient.stop(); // Broken connection: open a fresh one next time.
  if (code == 200) return true;
  Serial.printf("Firebase %s %s: HTTP %d\n", method, path.c_str(), code);
  return false;
}

// {"timestamp": <server time>, "soil_moisture_pct": 65, "raw": 2400}
// soil_moisture_pct is left out when the reading is invalid.
String buildReadingJson() {
  JsonDocument doc;
  doc["timestamp"][".sv"] = "timestamp";
  if (soilPercent >= 0) doc["soil_moisture_pct"] = soilPercent;
  doc["raw"] = soilRaw;
  String out;
  serializeJson(doc, out);
  return out;
}

void publishLive() {
  lastLiveAt = millis();
  liveSent = true;
  if (firebaseSend("PUT", nodePath() + "/live", buildReadingJson()))
    Serial.println("Firebase: live updated");
}

void publishHistory() {
  lastHistoryAt = millis();
  historySent = true;
  if (firebaseSend("POST", nodePath() + "/history", buildReadingJson()))
    Serial.println("Firebase: history saved");
}

void printStatus() {
  Serial.println("==== STATUS ====");
  Serial.printf("Node: soil_%d | Wi-Fi: %s\n", NODE_ID,
                WiFi.status() == WL_CONNECTED ? "connected" : "offline");
  Serial.printf("Soil: raw=%d (dry=%d, wet=%d) | moisture=%d%%\n",
                soilRaw, SOIL_DRY_RAW, SOIL_WET_RAW, soilPercent);
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  pinMode(SOIL_PIN, INPUT);
  analogReadResolution(12);
  WiFi.mode(WIFI_STA);
  // Why a connection attempt failed (e.g. 201 = network not found,
  // 15 or 204 = wrong password, 200/202 = weak signal/timeout).
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
    Serial.printf("Wi-Fi: disconnected, reason %d\n",
                  info.wifi_sta_disconnected.reason);
  }, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  lastWifiTry = millis();
  Serial.printf("Soil node soil_%d started\n", NODE_ID);
}

void loop() {
  uint32_t now = millis();

  if (lastReadAt == 0 || (uint32_t)(now - lastReadAt) >= READ_INTERVAL_MS) {
    lastReadAt = now;
    soilRaw = readSoilRaw();
    soilPercent = soilRawToPercent(soilRaw);
    if (soilPercent < 0)
      Serial.printf("Soil: raw=%d OUT OF RANGE (%d-%d) - check sensor wiring\n",
                    soilRaw, RAW_MIN_VALID, RAW_MAX_VALID);
    else
      Serial.printf("Soil: raw=%d | moisture=%d%%\n", soilRaw, soilPercent);
  }

  static bool wasConnected = false;
  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected && !wasConnected) {
    Serial.print("Wi-Fi connected, IP: ");
    Serial.println(WiFi.localIP());
  }
  wasConnected = connected;
  if (!connected && (uint32_t)(now - lastWifiTry) >= WIFI_RETRY_MS) {
    lastWifiTry = now;
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASS);
  }

  if (connected && soilRaw >= 0) {
    if (!liveSent || (uint32_t)(millis() - lastLiveAt) >= LIVE_INTERVAL_MS) publishLive();
    if (!historySent || (uint32_t)(millis() - lastHistoryAt) >= HISTORY_INTERVAL_MS)
      publishHistory();
  }

  if (Serial.available()) {
    char command = Serial.read();
    if (command == 's') printStatus();
    else if (command == 'f') { publishLive(); publishHistory(); }
  }
  delay(20);
}
