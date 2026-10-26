"""
Firebase ML service: connects the ESP32, the ML models, and the Flutter app.

Every few seconds it:
  1. Reads the latest ESP32 reading   -> irrigation/live
  2. Reads the farmer's growth stage  -> irrigation/settings/growth_stage
  3. Runs the 3 ONNX models (only when there is a NEW reading)
  4. Writes the result                -> irrigation/prediction
  5. Saves a copy for analysis        -> irrigation/prediction_history
     (includes the ESP32 decision-table result, for comparison in the paper)

Run from the package folder:
    pip install -r requirements.txt
    python src/firebase_ml_service.py

Options:
    --url URL        Firebase Realtime Database URL
    --interval SEC   how often to check for a new reading (default 30)
    --once           process the current reading once and exit (for testing)

Notes:
  - Uses the Firebase REST API with the open test-mode rules. If you lock the
    rules later, add authentication.
  - The hour input uses this computer's local time, so keep its time zone set
    to Philippine time.
"""

import argparse
import sys
import time
from datetime import datetime
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from predict import predict  # noqa: E402

DEFAULT_URL = "https://watermelon-674c0-default-rtdb.asia-southeast1.firebasedatabase.app"
MODEL_VERSION = "random-forest-sim-v1"
TIMEOUT = 10


def fb_get(url, path):
    r = requests.get(f"{url}/{path}.json", timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


def fb_put(url, path, data):
    r = requests.put(f"{url}/{path}.json", json=data, timeout=TIMEOUT)
    r.raise_for_status()


def fb_post(url, path, data):
    r = requests.post(f"{url}/{path}.json", json=data, timeout=TIMEOUT)
    r.raise_for_status()


def build_reading(live, growth_stage):
    """Convert the ESP32's Firebase reading into the model's input format."""
    ts_ms = live["timestamp"]
    return {
        "timestamp": datetime.fromtimestamp(ts_ms / 1000).isoformat(timespec="minutes"),
        "soil_moisture_pct": live.get("soil_moisture_pct"),
        "temperature_c": live.get("temperature_c"),
        "humidity_pct": live.get("humidity_pct"),
        "rain_probability_12h_pct": live.get("rain_probability_12h_pct"),
        "rainfall_forecast_12h_mm": live.get("rainfall_forecast_12h_mm"),
        "growth_stage": growth_stage,
    }


def make_prediction(live, growth_stage):
    """Return the record written to irrigation/prediction."""
    ts_ms = live["timestamp"]
    base = {
        "based_on": ts_ms,                        # timestamp of the ESP32 reading
        "predicted_at": {".sv": "timestamp"},     # Firebase server time
        "model_version": MODEL_VERSION,
        "growth_stage": growth_stage,
    }
    try:
        result = predict(build_reading(live, growth_stage))
        return {**base, **result}
    except ValueError as e:
        # Missing sensor value or unknown growth stage: say so instead of guessing.
        return {**base, "status": "UNAVAILABLE", "reason": str(e)}


def process(url, live, growth_stage):
    record = make_prediction(live, growth_stage)
    fb_put(url, "irrigation/prediction", record)

    history = dict(record)
    history["soil_moisture_pct"] = live.get("soil_moisture_pct")
    history["decision_table_irrigation_needed"] = live.get("irrigation_needed")
    fb_post(url, "irrigation/prediction_history", history)
    return record


def describe(record):
    if record.get("status") == "UNAVAILABLE":
        return f"UNAVAILABLE: {record['reason']}"
    if record["irrigation_needed"]:
        return (f"IRRIGATION NEEDED (p={record['irrigation_probability']:.2f}), "
                f"water {record['watering_duration_min']} min")
    return (f"not needed (p={record['irrigation_probability']:.2f}), "
            f"next in {record['next_irrigation_hours']} h")


def run(url, interval, once):
    print(f"ML service started. Database: {url}")
    print(f"Checking for new readings every {interval} s. Press Ctrl+C to stop.\n")
    last_ts = None
    last_stage = None
    while True:
        try:
            live = fb_get(url, "irrigation/live")
            stage = fb_get(url, "irrigation/settings/growth_stage")
            if not live or "timestamp" not in live:
                print("Waiting for the first ESP32 reading...")
            elif live["timestamp"] != last_ts or stage != last_stage or once:
                record = process(url, live, stage)
                last_ts = live["timestamp"]
                last_stage = stage
                when = datetime.fromtimestamp(last_ts / 1000).strftime("%b %d %H:%M")
                print(f"[{datetime.now():%H:%M:%S}] Reading {when} -> {describe(record)}")
        except requests.RequestException as e:
            print(f"[{datetime.now():%H:%M:%S}] Network error: {e}. Retrying...")
        except Exception as e:  # keep the service alive
            print(f"[{datetime.now():%H:%M:%S}] Error: {e}")

        if once:
            break
        time.sleep(interval)


def main():
    ap = argparse.ArgumentParser(description="Watermelon irrigation ML service for Firebase")
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--interval", type=int, default=30)
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()
    try:
        run(args.url.rstrip("/"), args.interval, args.once)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
