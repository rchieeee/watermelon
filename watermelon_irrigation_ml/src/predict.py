"""
Offline irrigation prediction with the ONNX models.

Usage:
  python src/predict.py                          # uses sample_mobile_input.json
  python src/predict.py path/to/input.json

Input JSON (same fields the ESP32 sends to Firebase, plus growth_stage):
  {
    "timestamp": "2026-09-27T10:30:00",
    "soil_moisture_pct": 38.0,
    "temperature_c": 31.0,
    "humidity_pct": 65.0,
    "rain_probability_12h_pct": 15.0,
    "rainfall_forecast_12h_mm": 0.5,
    "growth_stage": "flowering"
  }
"""

import json
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import onnxruntime as ort

ROOT = Path(__file__).resolve().parent.parent
META = json.loads((ROOT / "model_metadata.json").read_text())
NUMERIC = META["numeric_features"]
STAGES = META["growth_stage_values"]

_sessions = {}


def session(name):
    if name not in _sessions:
        _sessions[name] = ort.InferenceSession(str(ROOT / "onnx" / f"{name}.onnx"))
    return _sessions[name]


def validate(reading):
    required = ["timestamp", "soil_moisture_pct", "temperature_c", "humidity_pct",
                "rain_probability_12h_pct", "rainfall_forecast_12h_mm", "growth_stage"]
    missing = [k for k in required if reading.get(k) is None]
    if missing:
        raise ValueError(f"Missing values: {', '.join(missing)}")
    if reading["growth_stage"] not in STAGES:
        raise ValueError(f"Unknown growth stage '{reading['growth_stage']}'. Use one of: {', '.join(STAGES)}")


def predict(reading):
    validate(reading)
    t = datetime.fromisoformat(str(reading["timestamp"]))
    values = dict(reading, hour=t.hour + t.minute / 60.0)

    feed = {c: np.array([[float(values[c])]], dtype=np.float32) for c in NUMERIC}
    feed["growth_stage"] = np.array([[values["growth_stage"]]], dtype=object)

    label, proba = session("irrigation_needed").run(None, feed)
    needed = int(label[0])
    probability = float(proba[0][1])

    if needed:
        duration = float(session("watering_duration").run(None, feed)[0][0][0])
        next_hours = 0.0
    else:
        duration = 0.0
        next_hours = float(session("next_irrigation_hours").run(None, feed)[0][0][0])

    return {
        "irrigation_needed": needed,
        "irrigation_probability": round(probability, 4),
        "watering_duration_min": round(max(duration, 0.0), 1),
        "next_irrigation_hours": round(min(max(next_hours, 0.0), 72.0), 1),
        "status": "IRRIGATION_REQUIRED" if needed else "NO_IRRIGATION_NEEDED",
    }


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sample_mobile_input.json"
    reading = json.loads(path.read_text())
    print(json.dumps(predict(reading), indent=2))


if __name__ == "__main__":
    main()
