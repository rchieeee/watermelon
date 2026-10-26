// Smart Irrigation for Watermelon - ESP32 + Firebase Realtime Database
// Main board: soil sensor 1 (capacitive v2.0 on GPIO34), DHT11, relay + pump,
// optional SSD1306 OLED. Wi-Fi only. This board uses ONLY its own soil
// sensor (sensor 1) for the pump. Sensors 2 and 3 are separate boards
// (soil_node_2, soil_node_3); the app shows them, this board ignores them.
// Soil is sampled once each second in a dedicated ESP32 task. That task also
// stops the pump when the soil reaches 70%, on a bad soil reading,
// or at the run-time limit.
// Network calls run in loop(), so a slow request cannot delay pump shutoff.
// Readings go to /irrigation/live every 2 seconds and to /irrigation/history.
// Auto watering starts below 60% soil and stops when the soil reaches 70%.
// In the "Vine growth" stage chosen in the app
// (/irrigation/settings/growth_stage) it also needs 29 C or hotter to start.
// ArduinoJson v7, Adafruit DHT, Adafruit GFX, Adafruit SSD1306 required.
// The app's "Turn pump on" (/irrigation/control/start_request) keeps the pump
// on until "Turn pump off" (/irrigation/control/stop_request), ignoring soil.
// Serial Monitor (115200): w=test pump 15 s, s=status, r=weather,
//                        f=publish now, c=clear safety lock after inspection.

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>

// Wi-Fi name/password and the OpenWeatherMap API key are in secrets.h,
// which is not pushed to GitHub. Copy secrets.example.h to secrets.h.
#include "secrets.h"
const float FARM_LAT = 6.9636;   // Replace with your farm coordinates.
const float FARM_LON = 126.0117;
const char* FIREBASE_URL =
    "https://watermelon-674c0-default-rtdb.asia-southeast1.firebasedatabase.app";

// ---- Pins ----
// Soil sensor AOUT must be on an ADC1 pin (GPIO32-39): ADC2 pins stop
// working while Wi-Fi is on. GPIO34 is input-only, which is fine here.
const int SOIL_PIN = 34;
const int DHT_PIN = 4;
#define DHT_TYPE DHT11           // Change to DHT22 if that is your actual sensor.
const int RELAY_PIN = 26;
// true: relay turns ON when the pin is LOW (most 1-channel relay modules).
// If the pump runs while the log says pump=OFF, flip this value.
const bool RELAY_ACTIVE_LOW = true;
const int OLED_SDA = 21, OLED_SCL = 22;

// ---- Soil sensor calibration ----
// Raw analogRead values (0-4095). To calibrate: send 's' in the Serial
// Monitor with the sensor in dry air (-> SOIL_DRY_RAW), then with it in a
// glass of water up to the line (-> SOIL_WET_RAW). Higher raw = drier.
const int SOIL_DRY_RAW = 3200;   // 0% moisture
const int SOIL_WET_RAW = 1300;   // 100% moisture
const int SOIL_SAMPLES = 10;     // Readings averaged per measurement (less noise).
// A raw value outside this range means the sensor is unplugged or shorted.
const int RAW_MIN_VALID = 100, RAW_MAX_VALID = 4000;

// ---- Moisture thresholds (percent) ----
// The pump turns on below MOIST_DRY and off at MOIST_WET or higher. The gap
// between them stops the relay clicking on and off.
const int MOIST_DRY = 60, MOIST_WET = 70;
const float RAIN_MID = 0.50f, RAIN_HIGH = 0.70f;
// Vine growth (set in the app): the pump turns on only when the soil is
// below MOIST_DRY AND the air is at least this hot. If the DHT has no
// reading, it falls back to soil only so the vines are not left dry.
const float VINE_TEMP_ON = 29.0f;

const uint32_t SOIL_INTERVAL_MS = 1000;
const uint32_t PUMP_MAX_RUN_MS = 5UL * 60 * 1000;
const uint32_t MANUAL_TEST_MS = 15000;
// A pump turned on from the app runs until the app turns it off. This limit
// only protects the field if the phone loses internet and cannot send OFF.
const uint32_t APP_MAX_RUN_MS = 30UL * 60 * 1000;
const uint32_t LIVE_INTERVAL_MS = 2UL * 1000; // Live soil to Firebase every 2 s (app realtime).
const uint32_t HISTORY_INTERVAL_MS = 10UL * 1000; // New history record every 10 s.
const uint32_t WEATHER_INTERVAL_MS = 30UL * 60 * 1000;
const uint32_t WEATHER_RETRY_MS = 60UL * 1000;
const uint32_t WEATHER_MAX_AGE_MS = 3UL * 60 * 60 * 1000;
const uint32_t WIFI_RETRY_MS = 30UL * 1000;
const uint32_t CONTROL_POLL_MS = 1000; // How often the app's on/off buttons are checked.
const uint32_t APP_STOP_PAUSE_MS = 60UL * 60 * 1000;
const uint32_t DHT_INTERVAL_MS = 5000;
const uint32_t STAGE_POLL_MS = 10UL * 1000; // How often the app's growth stage is read.

// ---- Sensor 1 in /irrigation/sensors/soil_1 ----
// Same format as the node boards (soil_2, soil_3), so the app can show all
// three sensors side by side. This board does not read sensors 2 and 3.
const uint32_t SENSOR_LIVE_MS = 5UL * 1000;    // Sensor 1 to sensors/soil_1/live.
const uint32_t SENSOR_HISTORY_MS = 60UL * 1000; // Sensor 1 to sensors/soil_1/history.

struct Advice {
  bool irrigate;
  const char* shortCode;
  const char* status;
  const char* suggested;
  float nextHours;
};

enum class StopReason : uint8_t {
  NONE, WATERED, MAX_TIME, SENSOR_ERROR, TEST_DONE, APP_STOP, APP_LIMIT
};

// AUTO stops when the soil reaches MOIST_WET (70%). APP (turned on from the
// app) ignores soil and runs until the app turns it off. TEST runs 15 s.
enum class RunMode : uint8_t { AUTO, APP, TEST };

struct SoilState {
  int soilRaw = -1;      // Averaged analogRead value (0-4095); -1 = not read yet.
  int soilPercent = -1;  // 0-100%; -1 = invalid reading.
  uint32_t sequence = 0;
  bool pumpOn = false;
  RunMode mode = RunMode::AUTO;
  uint32_t pumpStartedAt = 0;
  bool safetyLocked = false;
  StopReason pendingStop = StopReason::NONE;
  float pendingMinutes = 0;
  bool pendingWasManual = false;
};

SemaphoreHandle_t soilMutex;
SoilState state;
DHT dht(DHT_PIN, DHT_TYPE);
Adafruit_SSD1306 display(128, 64, &Wire, -1);
bool displayOk = false;

float temperature = NAN, humidity = NAN;
float rainChance = 0, rainMm = 0;
bool haveWeather = false, lastWeatherFetchOk = false, firstWeatherDone = false;
uint32_t weatherAt = 0, lastWeatherTry = 0, lastWifiTry = 0;
uint32_t lastLiveAt = 0, lastHistoryAt = 0, lastDhtAt = 0;
uint32_t lastHistoryTryAt = 0;
uint32_t lastControlPoll = 0, appPausedAt = 0, processedSequence = 0;
uint32_t lastStagePoll = 0;
uint32_t lastSensorLiveAt = 0, lastSensorHistoryAt = 0;
bool sensorLiveSent = false, sensorHistorySent = false;
String growthStage = ""; // From /irrigation/settings/growth_stage; empty until read.
bool historySent = false, historyAttempted = false, liveSent = false, appPaused = false;

String decision = "START", advStatus = "-", advSuggested = "-";
bool adviceValid = false, adviceIrrigate = false;
float adviceNextHours = -1;

SoilState snapshot() {
  SoilState copy;
  xSemaphoreTake(soilMutex, portMAX_DELAY);
  copy = state;
  xSemaphoreGive(soilMutex);
  return copy;
}

bool weatherUsable() {
  return haveWeather && (uint32_t)(millis() - weatherAt) < WEATHER_MAX_AGE_MS;
}

Advice getAdvice(int moisture, bool haveRain, float rain) {
  if (!haveRain) {
    if (moisture < MOIST_DRY)
      return {true, "WATER*", "Irrigation needed (soil only)", "Now / within 1 hour", 0};
    if (moisture < MOIST_WET)
      return {false, "HOLD", "Usually no immediate irrigation", "Recheck in ~6-12 hours", 9};
    return {false, "NO NEED", "No irrigation", "Recheck in ~12-24 hours", 18};
  }
  if (moisture < MOIST_DRY) {
    if (rain < RAIN_MID)
      return {true, "IRRIGATE", "Irrigation needed", "Now / within 1 hour", 0};
    if (rain < RAIN_HIGH)
      return {false, "MONITOR", "Monitor", "Wait ~6-12 hours and reassess", 9};
    return {false, "RAIN", "No immediate irrigation", "Wait ~12-24 hours / after rainfall", 18};
  }
  if (moisture < MOIST_WET) {
    if (rain < RAIN_MID)
      return {false, "HOLD", "Usually no immediate irrigation", "Recheck in ~6-12 hours", 9};
    if (rain < RAIN_HIGH)
      return {false, "HOLD", "No immediate irrigation", "Recheck in ~12 hours", 12};
    return {false, "NO NEED", "No irrigation", "Recheck in ~24 hours", 24};
  }
  if (rain < RAIN_MID)
    return {false, "NO NEED", "No irrigation", "Recheck in ~12-24 hours", 18};
  return {false, "NO NEED", "No irrigation", "Recheck in ~24 hours", 24};
}

// These functions run only in loop(), never in the soil task.
// One HTTPS connection to Firebase, kept open and reused by every request.
// A new secure connection costs about 1 s; reusing it makes each request
// ~0.1-0.3 s, so app taps and live readings reach each side quickly.
WiFiClientSecure fbClient;
HTTPClient fbHttp;
bool fbReady = false;

int firebaseRequest(const char* method, const String& path, const String& json,
                    String* response) {
  if (WiFi.status() != WL_CONNECTED) return -1;
  if (!fbReady) {
    fbClient.setInsecure(); // Prototype only: HTTPS certificate is not verified.
    fbHttp.setReuse(true);
    fbReady = true;
  }
  if (!fbHttp.begin(fbClient, String(FIREBASE_URL) + path + ".json")) return -1;
  fbHttp.setTimeout(5000);
  if (strcmp(method, "GET") != 0 && strcmp(method, "DELETE") != 0)
    fbHttp.addHeader("Content-Type", "application/json");
  int code = fbHttp.sendRequest(method, json);
  if (response && code == 200) *response = fbHttp.getString();
  fbHttp.end();
  if (code < 0) fbClient.stop(); // Broken connection: open a fresh one next time.
  return code;
}

bool firebaseSend(const char* method, const String& path, const String& json) {
  int code = firebaseRequest(method, path, json, nullptr);
  if (code == 200) return true;
  Serial.printf("Firebase %s %s: HTTP %d\n", method, path.c_str(), code);
  return false;
}

String firebaseGet(const String& path) {
  String body;
  firebaseRequest("GET", path, "", &body);
  body.trim();
  return body;
}

String buildReadingJson(float wateringMin) {
  SoilState s = snapshot();
  JsonDocument doc;
  doc["timestamp"][".sv"] = "timestamp";
  if (s.soilPercent >= 0) doc["soil_moisture_pct"] = s.soilPercent;
  if (!isnan(temperature)) doc["temperature_c"] = round(temperature * 10) / 10.0;
  if (!isnan(humidity)) doc["humidity_pct"] = round(humidity);
  if (weatherUsable()) {
    doc["rain_probability_12h_pct"] = round(rainChance * 100);
    doc["rainfall_forecast_12h_mm"] = round(rainMm * 10) / 10.0;
  }
  if (adviceValid) {
    doc["irrigation_needed"] = adviceIrrigate ? 1 : 0;
    doc["next_irrigation_hours"] = adviceNextHours;
    doc["status"] = advStatus;
    doc["suggested_time"] = advSuggested;
  }
  if (wateringMin >= 0)
    doc["watering_duration_min"] = round(wateringMin * 10) / 10.0;
  doc["pump_on"] = s.pumpOn;
  String out;
  serializeJson(doc, out);
  return out;
}

void publishLive() {
  // Throttle failed writes as well as successful ones.
  lastLiveAt = millis();
  liveSent = true;
  if (firebaseSend("PUT", "/irrigation/live", buildReadingJson(-1))) {
    Serial.println("Firebase: live updated");
  }
}

void publishHistory(float wateringMin) {
  lastHistoryTryAt = millis();
  historyAttempted = true;
  if (firebaseSend("POST", "/irrigation/history", buildReadingJson(wateringMin))) {
    lastHistoryAt = millis();
    historySent = true;
    Serial.println("Firebase: history saved");
  }
}

void updateDisplay(const SoilState& s) {
  if (!displayOk) return;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(0, 0);
  if (s.soilPercent >= 0) { display.print(s.soilPercent); display.print('%'); }
  else display.print("--%");
  display.setTextSize(1);
  display.setCursor(80, 0);
  display.print(s.pumpOn ? "PUMP ON" : "PUMP OFF");
  display.setCursor(80, 9);
  display.print(decision);
  display.setCursor(0, 24);
  display.print("Soil raw:");
  display.print(s.soilRaw);
  if (s.soilPercent < 0) display.print(" ERR");
  display.setCursor(0, 42);
  display.print("T:");
  if (!isnan(temperature)) { display.print(temperature, 1); display.print('C'); }
  else display.print("--");
  display.print("  H:");
  if (!isnan(humidity)) { display.print((int)humidity); display.print('%'); }
  else display.print("--");
  display.setCursor(0, 54);
  display.print("R:");
  if (weatherUsable()) {
    display.print((int)(rainChance * 100)); display.print("% ");
    display.print(rainMm, 1); display.print("mm");
  } else display.print("--");
  display.setCursor(104, 54);
  display.print(WiFi.status() == WL_CONNECTED ? "WiFi" : "OFF");
  display.display();
}

// Switches the relay. For an active-LOW 5 V relay module, OFF disconnects
// the pin (INPUT), exactly like pulling the wire off pin 26: the module's own
// pull-up then turns it fully off. A 3.3 V HIGH is too weak and leaves it on.
void relaySet(bool on) {
  if (RELAY_ACTIVE_LOW) {
    if (on) {
      digitalWrite(RELAY_PIN, LOW);
      pinMode(RELAY_PIN, OUTPUT);
      digitalWrite(RELAY_PIN, LOW);
    } else {
      pinMode(RELAY_PIN, INPUT);
    }
  } else {
    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  }
}

// Must be called with soilMutex held. No network, display, or String operations.
void endPumpLocked(StopReason why, uint32_t now) {
  if (!state.pumpOn) return;
  state.pendingMinutes = (uint32_t)(now - state.pumpStartedAt) / 60000.0f;
  state.pendingWasManual = state.mode == RunMode::TEST;
  state.pendingStop = why;
  state.pumpOn = false;
  state.mode = RunMode::AUTO;
  if (why == StopReason::MAX_TIME || why == StopReason::SENSOR_ERROR)
    state.safetyLocked = true; // Inspect pump and sensors; clear with 'c'.
  relaySet(false);
}

void startPump(RunMode mode) {
  bool started = false;
  xSemaphoreTake(soilMutex, portMAX_DELAY);
  if (!state.pumpOn && (mode != RunMode::AUTO || !state.safetyLocked)) {
    state.pumpStartedAt = millis();
    state.mode = mode;
    state.pumpOn = true;
    relaySet(true);
    started = true;
  }
  xSemaphoreGive(soilMutex);
  if (started) {
    liveSent = false; // Tell the app right away that the pump is on.
    Serial.println(mode == RunMode::TEST ? ">> Manual test pump ON"
                   : mode == RunMode::APP ? ">> Pump ON (from app)" : ">> Pump ON");
  }
}

// Reads the soil sensor SOIL_SAMPLES times and returns the average raw value
// (0-4095). The raw value is always returned so the log shows what the pin
// really reads, even when it is out of range.
int readSoilRaw() {
  long sum = 0;
  for (int n = 0; n < SOIL_SAMPLES; n++) {
    sum += analogRead(SOIL_PIN);
    delay(10);
  }
  return sum / SOIL_SAMPLES;
}

// Converts a raw reading to 0-100% using the calibration values. Returns -1
// (sensor error: pump stays off) when the raw value is out of range.
int soilRawToPercent(int raw) {
  if (raw < RAW_MIN_VALID || raw > RAW_MAX_VALID) return -1;
  return constrain(map(raw, SOIL_DRY_RAW, SOIL_WET_RAW, 0, 100), 0, 100);
}

// Independent of Wi-Fi/Firebase: samples the soil sensor every second.
void soilTask(void*) {
  TickType_t nextTick = xTaskGetTickCount();
  for (;;) {
    int soilRaw = readSoilRaw();
    int soilPercent = soilRawToPercent(soilRaw);
    uint32_t now = millis();
    StopReason stopped = StopReason::NONE;
    xSemaphoreTake(soilMutex, portMAX_DELAY);
    state.soilRaw = soilRaw;
    state.soilPercent = soilPercent;
    state.sequence++;
    if (state.pumpOn) {
      uint32_t elapsed = (uint32_t)(now - state.pumpStartedAt);
      if (state.mode == RunMode::TEST) {
        if (elapsed >= MANUAL_TEST_MS) stopped = StopReason::TEST_DONE;
      } else if (state.mode == RunMode::APP) {
        // Manual from the app: soil moisture does not stop it.
        if (elapsed >= APP_MAX_RUN_MS) stopped = StopReason::APP_LIMIT;
      } else if (soilPercent < 0) {
        stopped = StopReason::SENSOR_ERROR;
      } else if (soilPercent >= MOIST_WET) {
        stopped = StopReason::WATERED;
      } else if (elapsed >= PUMP_MAX_RUN_MS) {
        stopped = StopReason::MAX_TIME;
      }
      if (stopped != StopReason::NONE) endPumpLocked(stopped, now);
    }
    // Failsafe: whenever the pump should be off (e.g. soil at 70% or more),
    // drive the relay off every second, even if something else switched it on.
    if (!state.pumpOn) relaySet(false);
    bool pumpNow = state.pumpOn;
    xSemaphoreGive(soilMutex);
    if (soilPercent < 0)
      Serial.printf("Soil: raw=%d OUT OF RANGE (%d-%d) - check sensor wiring | pump=%s\n",
                    soilRaw, RAW_MIN_VALID, RAW_MAX_VALID, pumpNow ? "ON" : "OFF");
    else
      Serial.printf("Soil: raw=%d | moisture=%d%% | pump=%s\n",
                    soilRaw, soilPercent, pumpNow ? "ON" : "OFF");
    if (stopped != StopReason::NONE) Serial.println(">> Pump OFF (soil task)");
    vTaskDelayUntil(&nextTick, pdMS_TO_TICKS(SOIL_INTERVAL_MS));
  }
}

void handleStopEvent() {
  StopReason reason;
  float minutes;
  bool wasManual;
  xSemaphoreTake(soilMutex, portMAX_DELAY);
  reason = state.pendingStop;
  minutes = state.pendingMinutes;
  wasManual = state.pendingWasManual;
  state.pendingStop = StopReason::NONE;
  xSemaphoreGive(soilMutex);
  if (reason == StopReason::NONE) return;

  switch (reason) {
    case StopReason::WATERED: decision = "WATERED"; break;
    case StopReason::MAX_TIME: decision = "MAX TIME"; break;
    case StopReason::SENSOR_ERROR: decision = "SENS ERR"; break;
    case StopReason::TEST_DONE: decision = "TEST OK"; break;
    case StopReason::APP_STOP: decision = "APP STOP"; break;
    case StopReason::APP_LIMIT: decision = "APP LIMIT"; break;
    default: break;
  }
  if (reason == StopReason::WATERED) {
    adviceValid = true;
    adviceIrrigate = false;
    adviceNextHours = 9;
    advStatus = "Watering completed";
    advSuggested = "Continue monitoring soil";
  } else if (reason == StopReason::MAX_TIME || reason == StopReason::SENSOR_ERROR) {
    advStatus = "Automatic watering locked for safety";
    advSuggested = "Inspect pump and sensors; clear lock with c";
  } else if (reason == StopReason::APP_STOP) {
    advStatus = "Watering stopped from app";
    advSuggested = "Automatic watering paused for 1 hour";
  } else if (reason == StopReason::APP_LIMIT) {
    advStatus = "Pump from app stopped after 30 minutes (safety limit)";
    advSuggested = "Tap Turn pump on again to keep watering";
  }
  Serial.printf("Pump stopped: %s (%.1f min)\n", decision.c_str(), minutes);
  if (reason == StopReason::MAX_TIME || reason == StopReason::SENSOR_ERROR)
    Serial.println("Safety lock ON. Inspect water supply/sensors; send 'c' to clear.");
  if (reason == StopReason::APP_STOP) {
    appPaused = true;
    appPausedAt = millis();
  }
  updateDisplay(snapshot());
  publishLive();
  if (!wasManual) publishHistory(minutes);
}

// "Turn pump off" in the app. Works whether or not the code thinks the pump
// is on, and forces the relay off.
void appStop() {
  xSemaphoreTake(soilMutex, portMAX_DELAY);
  bool wasOn = state.pumpOn;
  endPumpLocked(StopReason::APP_STOP, millis());
  relaySet(false);
  xSemaphoreGive(soilMutex);
  if (wasOn) {
    handleStopEvent();
    return;
  }
  appPaused = true;
  appPausedAt = millis();
  decision = "APP STOP";
  advStatus = "Pump turned off from app";
  advSuggested = "Automatic watering paused for 1 hour";
  Serial.println(">> Pump forced OFF (from app)");
  updateDisplay(snapshot());
  publishLive();
}

// "Turn pump on" in the app. The pump stays on until "Turn pump off", whatever
// the soil moisture (APP_MAX_RUN_MS is only a safety limit).
void appStart() {
  bool alreadyOn;
  xSemaphoreTake(soilMutex, portMAX_DELAY);
  alreadyOn = state.pumpOn;
  if (alreadyOn) {
    // Already watering automatically: hand it to the app so it keeps running.
    state.mode = RunMode::APP;
    state.pumpStartedAt = millis();
  }
  xSemaphoreGive(soilMutex);
  if (!alreadyOn) startPump(RunMode::APP);
  appPaused = false;
  decision = "APP ON";
  advStatus = "Pump turned on from app";
  advSuggested = "Runs until you tap Turn pump off";
  Serial.println(">> Pump ON (from app) - stays on until app turns it off");
  updateDisplay(snapshot());
  publishLive();
}

// The app writes irrigation/control/start_request ("Turn pump on") or
// irrigation/control/stop_request ("Turn pump off"). Both are read with one
// request every 2 s. If both are there, OFF wins.
void checkAppControl() {
  if ((uint32_t)(millis() - lastControlPoll) < CONTROL_POLL_MS) return;
  lastControlPoll = millis();
  String body = firebaseGet("/irrigation/control");
  if (body.isEmpty() || body == "null") return;
  JsonDocument doc;
  if (deserializeJson(doc, body) != DeserializationError::Ok) return;
  bool wantStop = !doc["stop_request"].isNull();
  bool wantStart = !doc["start_request"].isNull();
  if (!wantStop && !wantStart) return;
  firebaseSend("DELETE", "/irrigation/control", "");
  if (wantStop) appStop();
  else appStart();
}

// The stage the farmer picked in the app. Kept as-is on a network error.
void checkGrowthStage() {
  if (lastStagePoll != 0 && (uint32_t)(millis() - lastStagePoll) < STAGE_POLL_MS) return;
  lastStagePoll = millis();
  String body = firebaseGet("/irrigation/settings/growth_stage");
  if (body.isEmpty()) return;
  JsonDocument doc;
  if (deserializeJson(doc, body) != DeserializationError::Ok) return;
  String stage = doc.is<const char*>() ? String(doc.as<const char*>()) : String("");
  if (stage != growthStage) {
    growthStage = stage;
    Serial.printf("Growth stage: %s\n", stage.isEmpty() ? "(not set)" : stage.c_str());
  }
}

// Sensor 1 (this board) to /irrigation/sensors/soil_1, in the same format
// the node boards use, so the app can show all three sensors the same way.
String buildSensorJson(const SoilState& s) {
  JsonDocument doc;
  doc["timestamp"][".sv"] = "timestamp";
  if (s.soilPercent >= 0) doc["soil_moisture_pct"] = s.soilPercent;
  doc["raw"] = s.soilRaw;
  String out;
  serializeJson(doc, out);
  return out;
}

void publishSensor1() {
  SoilState s = snapshot();
  if (!sensorLiveSent || (uint32_t)(millis() - lastSensorLiveAt) >= SENSOR_LIVE_MS) {
    lastSensorLiveAt = millis();
    sensorLiveSent = true;
    firebaseSend("PUT", "/irrigation/sensors/soil_1/live", buildSensorJson(s));
  }
  if (!sensorHistorySent || (uint32_t)(millis() - lastSensorHistoryAt) >= SENSOR_HISTORY_MS) {
    lastSensorHistoryAt = millis();
    sensorHistorySent = true;
    firebaseSend("POST", "/irrigation/sensors/soil_1/history", buildSensorJson(s));
  }
}

void readClimate() {
  lastDhtAt = millis();
  float t = dht.readTemperature(), h = dht.readHumidity();
  temperature = (!isnan(t) && t > -10 && t < 60) ? t : NAN;
  humidity = (!isnan(h) && h >= 0 && h <= 100) ? h : NAN;
}

void fetchWeather() {
  lastWeatherTry = millis();
  firstWeatherDone = true;
  lastWeatherFetchOk = false;
  if (WiFi.status() != WL_CONNECTED) return;

  String url = "https://api.openweathermap.org/data/2.5/forecast?lat=" +
      String(FARM_LAT, 4) + "&lon=" + String(FARM_LON, 4) +
      "&units=metric&cnt=4&appid=" + OWM_KEY;
  WiFiClientSecure client;
  client.setInsecure(); // Prototype only.
  HTTPClient http;
  http.setTimeout(8000);
  if (!http.begin(client, url)) return;
  int code = http.GET();
  if (code == 200) {
    JsonDocument doc;
    if (deserializeJson(doc, http.getString()) == DeserializationError::Ok) {
      JsonArray slots = doc["list"].as<JsonArray>();
      if (slots.size() > 0) {
        float maxPop = 0, totalMm = 0;
        for (JsonObject slot : slots) {
          float pop = slot["pop"] | 0.0f;
          if (pop > maxPop) maxPop = pop;
          totalMm += slot["rain"]["3h"] | 0.0f;
        }
        rainChance = maxPop;
        rainMm = totalMm;
        haveWeather = true;
        weatherAt = millis();
        lastWeatherFetchOk = true;
        Serial.printf("Forecast: max 3h rain chance %.0f%%, total 12h %.1f mm\n",
                      rainChance * 100, rainMm);
      }
    }
  } else Serial.printf("Weather request: HTTP %d\n", code);
  http.end();
}

void controlCycle(const SoilState& s) {
  if (s.soilPercent < 0) {
    decision = "SENS ERR";
    advStatus = "Sensor error - not watering";
    advSuggested = "Check soil sensor wiring";
    adviceValid = false;
    return;
  }
  // Soil moisture only for now: the rain forecast does not affect the pump.
  Advice a = getAdvice(s.soilPercent, false, 0);
  if (growthStage == "vine_development" && a.irrigate) {
    if (isnan(temperature)) {
      a.status = "Irrigation needed (soil only - no temperature reading)";
    } else if (temperature < VINE_TEMP_ON) {
      a = {false, "HOLD", "Soil dry, but below 29 C (vine growth)",
           "Waters when soil <60% and temp >=29 C", 1};
    } else {
      a.status = "Irrigation needed (soil <60% and temp >=29 C)";
    }
  }
  decision = a.shortCode;
  advStatus = a.status;
  advSuggested = a.suggested;
  adviceValid = true;
  adviceIrrigate = a.irrigate;
  adviceNextHours = a.nextHours;

  if (appPaused && (uint32_t)(millis() - appPausedAt) >= APP_STOP_PAUSE_MS)
    appPaused = false;
  if (a.irrigate && s.safetyLocked) {
    decision = "LOCKED";
    advStatus = "Irrigation needed - safety lock";
    advSuggested = "Inspect pump and sensors; clear lock with c";
  } else if (a.irrigate && appPaused) {
    decision = "PAUSED";
    advStatus = "Irrigation needed - paused from app";
    advSuggested = "Automatic watering resumes in 1 hour";
  } else if (a.irrigate && !s.pumpOn) {
    startPump(RunMode::AUTO);
  }
}

void printStatus() {
  SoilState s = snapshot();
  Serial.println("==== STATUS ====");
  Serial.printf("Wi-Fi: %s | OLED: %s\n",
                WiFi.status() == WL_CONNECTED ? "connected" : "offline",
                displayOk ? "working" : "not found");
  Serial.printf("Soil: raw=%d (dry=%d, wet=%d) | moisture=%d%%\n",
                s.soilRaw, SOIL_DRY_RAW, SOIL_WET_RAW, s.soilPercent);
  Serial.printf("Temperature: %.1f C | Humidity: %.0f%%\n", temperature, humidity);
  if (weatherUsable())
    Serial.printf("Forecast: %.0f%% max slot chance, %.1f mm/12h\n",
                  rainChance * 100, rainMm);
  else Serial.println("Forecast unavailable");
  Serial.printf("Growth stage: %s\n", growthStage.isEmpty() ? "(not set)" : growthStage.c_str());
  Serial.printf("Pump: %s | Safety lock: %s\n", s.pumpOn ? "ON" : "OFF",
                s.safetyLocked ? "ON" : "OFF");
  Serial.printf("Status: %s | Suggested: %s\n",
                advStatus.c_str(), advSuggested.c_str());
}

void startOled() {
  uint8_t addr = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf("I2C device at 0x%02X\n", a);
      if (a == 0x3C || a == 0x3D) addr = a;
    }
  }
  if (addr == 0) {
    Serial.println("OLED not found; continuing without screen");
    return;
  }
  displayOk = display.begin(SSD1306_SWITCHCAPVCC, addr);
  if (displayOk) updateDisplay(snapshot());
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  relaySet(false); // Pump OFF at boot.
  pinMode(SOIL_PIN, INPUT);
  analogReadResolution(12);
  soilMutex = xSemaphoreCreateMutex();
  if (!soilMutex) {
    Serial.println("FATAL: cannot create soil mutex");
    while (true) delay(1000);
  }
  Wire.begin(OLED_SDA, OLED_SCL);
  startOled();
  dht.begin();
  if (xTaskCreatePinnedToCore(soilTask, "soil-1s", 4096, nullptr, 2,
                              nullptr, 1) != pdPASS) {
    Serial.println("FATAL: cannot start soil task; pump remains OFF");
    while (true) delay(1000);
  }
  WiFi.mode(WIFI_STA);
  // Wi-Fi diagnostics: why a connection attempt failed (e.g. 15 or 204 =
  // wrong password, 201 = network not found, 200/202 = weak signal/timeout).
  WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) {
    Serial.printf("Wi-Fi: disconnected, reason %d\n",
                  info.wifi_sta_disconnected.reason);
  }, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  int found = WiFi.scanNetworks();
  Serial.printf("Wi-Fi scan: %d networks\n", found);
  for (int i = 0; i < found; i++)
    Serial.printf("  %s  (%d dBm)%s\n", WiFi.SSID(i).c_str(), (int)WiFi.RSSI(i),
                  WiFi.SSID(i) == WIFI_SSID ? "  <-- ours" : "");
  WiFi.scanDelete();
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  lastWifiTry = millis();
  Serial.println("Smart irrigation started: soil sampled every 1 second");
}

void loop() {
  handleStopEvent(); // Read task's pump stop event before any network calls.
  checkAppControl();

  static bool wasConnected = false;
  bool connected = WiFi.status() == WL_CONNECTED;
  if (connected && !wasConnected) {
    Serial.print("Wi-Fi connected, IP: ");
    Serial.println(WiFi.localIP());
    fetchWeather();
  }
  wasConnected = connected;
  if (connected) {
    checkGrowthStage();
    if (snapshot().sequence != 0) publishSensor1(); // To sensors/soil_1.
  }
  if (!connected && (uint32_t)(millis() - lastWifiTry) >= WIFI_RETRY_MS) {
    lastWifiTry = millis();
    // Start a clean attempt; reconnect() errors while one is still running.
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASS);
  }
  if (connected && firstWeatherDone &&
      (uint32_t)(millis() - lastWeatherTry) >=
          (lastWeatherFetchOk ? WEATHER_INTERVAL_MS : WEATHER_RETRY_MS))
    fetchWeather();

  if (lastDhtAt == 0 || (uint32_t)(millis() - lastDhtAt) >= DHT_INTERVAL_MS)
    readClimate();

  SoilState s = snapshot();
  if (s.sequence != 0 && s.sequence != processedSequence) {
    processedSequence = s.sequence;
    if (!s.pumpOn) controlCycle(s);
    updateDisplay(snapshot());
  }

  if (s.sequence != 0 && connected &&
      (!liveSent || (uint32_t)(millis() - lastLiveAt) >= LIVE_INTERVAL_MS))
    publishLive();
  if (s.sequence != 0 && connected &&
      (!historySent || (uint32_t)(millis() - lastHistoryAt) >= HISTORY_INTERVAL_MS) &&
      (!historyAttempted ||
       (uint32_t)(millis() - lastHistoryTryAt) >= WEATHER_RETRY_MS))
    publishHistory(-1);

  if (Serial.available()) {
    char command = Serial.read();
    if (command == 'w' && !snapshot().pumpOn) {
      decision = "TEST";
      startPump(RunMode::TEST);
      updateDisplay(snapshot());
    } else if (command == 's') printStatus();
    else if (command == 'r') fetchWeather();
    else if (command == 'f') { publishLive(); publishHistory(-1); }
    else if (command == 'c') {
      xSemaphoreTake(soilMutex, portMAX_DELAY);
      state.safetyLocked = false;
      xSemaphoreGive(soilMutex);
      Serial.println("Safety lock cleared; automatic decisions resumed");
    }
  }
  delay(20);
}
