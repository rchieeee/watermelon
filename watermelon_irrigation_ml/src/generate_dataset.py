"""
Generate a synthetic watermelon irrigation dataset by SIMULATING a field.

Each season is simulated in 30-minute steps:
  1. Weather: temperature, humidity, and actual rain events.
  2. Forecast: 12-hour rain probability and rainfall amount, derived from
     the rain that really falls in the next 12 hours, with realistic error.
  3. Soil moisture: dries through crop water use (depends on growth stage,
     temperature, humidity, time of day), rises with actual rain and
     irrigation.
  4. Labels:
       irrigation_needed      = decision table (soil < 40% AND rain prob < 50%)
       watering_duration_min  = minutes to raise soil to the stage target
       next_irrigation_hours  = actual hours until irrigation is next needed

Irrigation is applied at 06:00 and 17:00 when needed (common practice to
reduce evaporation losses). Labels describe the field state at every
observation, so they are recorded whether or not watering happens then.

This is SYNTHETIC data for development and thesis demonstration.
Parameters are approximations; retrain on real field data before deployment.

Run:  python src/generate_dataset.py
"""

import numpy as np
import pandas as pd
from pathlib import Path

SEED = 42
STEP_MIN = 30
STEPS_PER_DAY = 24 * 60 // STEP_MIN
FORECAST_STEPS = 12 * 60 // STEP_MIN         # 12-hour forecast window

# Decision table thresholds (same as the ESP32)
MOIST_DRY = 40.0
RAIN_PROB_LIMIT = 50.0
# Irrigate up to a stage-dependent target (flowering/fruit set is the most
# water-sensitive period, so it gets the highest target).
TARGET_BY_STAGE = {"germination": 55.0, "vine_development": 60.0,
                   "flowering": 65.0, "fruiting": 60.0}
IRRIGATION_RATE_PCT_PER_MIN = 0.8            # calibrate with a real pump test
IRRIGATION_HOURS = (6.0, 17.0)
NEXT_IRRIGATION_CAP_H = 72.0

# Growth stages: (name, days, crop coefficient at start, at end)
# Crop coefficients follow the usual FAO-56 pattern for watermelon
# (low at establishment, ~1.0 at mid-season, lower at late season).
STAGES = [
    ("germination",      12, 0.45, 0.45),
    ("vine_development", 25, 0.45, 1.00),
    ("flowering",        18, 1.00, 1.00),
    ("fruiting",         30, 1.00, 0.75),
]
SEASON_DAYS = sum(s[1] for s in STAGES)      # 85 days

# Six seasons with different start dates and weather
SEASON_STARTS = [
    "2024-11-04", "2025-01-13", "2025-03-17",
    "2025-10-20", "2025-12-15", "2026-02-16",
]

BASE_DEPLETION_PCT_PER_DAY = 13.0            # at Kc = 1.0, 28 °C, 70 % RH


def stage_and_kc(day):
    start = 0
    for name, days, kc0, kc1 in STAGES:
        if day < start + days:
            frac = (day - start) / days
            return name, kc0 + (kc1 - kc0) * frac
        start += days
    name, _, _, kc1 = STAGES[-1]
    return name, kc1


def simulate_weather(rng, n_steps):
    hours = (np.arange(n_steps) % STEPS_PER_DAY) * STEP_MIN / 60.0
    n_days = n_steps // STEPS_PER_DAY

    # Daily mean temperature: slow random walk around 28.5 °C
    daily_mean = np.empty(n_days)
    daily_mean[0] = rng.normal(28.5, 1.0)
    for d in range(1, n_days):
        daily_mean[d] = 0.8 * daily_mean[d - 1] + 0.2 * 28.5 + rng.normal(0, 0.6)
    diurnal = np.sin(2 * np.pi * (hours - 8) / 24)          # peak ~14:00
    temp = np.repeat(daily_mean, STEPS_PER_DAY) + 4.5 * diurnal + rng.normal(0, 0.4, n_steps)

    # Rain: wet/dry day Markov chain, 1-2 events on wet days
    rain = np.zeros(n_steps)
    wet = False
    for d in range(n_days):
        wet = rng.random() < (0.35 if wet else 0.12)   # dry-season pattern
        if not wet:
            continue
        for _ in range(rng.integers(1, 3)):
            start_h = rng.uniform(12, 20) if rng.random() < 0.7 else rng.uniform(0, 24)
            dur_steps = int(rng.integers(2, 7))
            total_mm = min(rng.gamma(1.3, 6.0), 45.0)
            s = d * STEPS_PER_DAY + int(start_h * 60 / STEP_MIN)
            idx = np.arange(s, min(s + dur_steps, n_steps))
            if len(idx):
                w = rng.dirichlet(np.ones(len(idx)))
                rain[idx] += total_mm * w

    # Rain cools the air
    raining = rain > 0.05
    temp = temp - 2.0 * raining

    # Humidity: inverse of temperature cycle, higher during/after rain
    wet_memory = np.zeros(n_steps)
    for i in range(1, n_steps):
        wet_memory[i] = 0.9 * wet_memory[i - 1] + (1.0 if raining[i] else 0.0)
    hum = 74 - 12 * diurnal + 3.0 * np.minimum(wet_memory, 5) + rng.normal(0, 2.5, n_steps)

    return hours, np.clip(temp, 20, 38), np.clip(hum, 45, 99), rain


def simulate_forecast(rng, rain):
    n = len(rain)
    future = np.array([rain[i + 1:i + 1 + FORECAST_STEPS].sum() for i in range(n)])
    prob = np.empty(n)
    mm = np.empty(n)
    p_prev = 30.0
    for i in range(n):
        if future[i] > 0.5:
            p_new = rng.beta(5.0, 2.2) * 100      # rain coming: usually high
        else:
            p_new = rng.beta(1.6, 4.5) * 100      # no rain: usually low
        p_prev = 0.75 * p_prev + 0.25 * p_new     # forecasts change gradually
        prob[i] = p_prev
        if future[i] > 0.5:
            mm[i] = min(future[i] * rng.lognormal(0, 0.45), 80.0)
        else:
            mm[i] = rng.exponential(0.25) * prob[i] / 50
    return np.clip(prob, 0, 100), np.clip(mm, 0, None)


def simulate_season(season_id, start_date, rng):
    n = SEASON_DAYS * STEPS_PER_DAY
    hours, temp, hum, rain = simulate_weather(rng, n)
    rain_prob, rain_mm = simulate_forecast(rng, rain)
    timestamps = pd.date_range(start_date, periods=n, freq=f"{STEP_MIN}min")

    # Daily sunlight weighting (crop water use happens mostly in daytime)
    sun = np.clip(np.sin(np.pi * (hours - 6) / 12), 0, None) + 0.08
    sun = sun / sun[:STEPS_PER_DAY].sum()          # sums to 1 per day

    soil = np.empty(n)
    stage = []
    needed = np.zeros(n, dtype=int)
    duration = np.zeros(n)
    s = rng.uniform(58, 66)                         # start near target after planting
    for i in range(n):
        day = i // STEPS_PER_DAY
        name, kc = stage_and_kc(day)
        stage.append(name)

        # --- record the observation (state before this step's changes) ---
        soil[i] = s
        if s < MOIST_DRY and rain_prob[i] < RAIN_PROB_LIMIT:
            needed[i] = 1
            duration[i] = (TARGET_BY_STAGE[name] - s) / IRRIGATION_RATE_PCT_PER_MIN

        # --- irrigation at the scheduled windows ---
        if needed[i] and hours[i] in IRRIGATION_HOURS:
            s = TARGET_BY_STAGE[name] + rng.normal(0, 1.5)

        # --- soil water balance for the next 30 minutes ---
        f_temp = 1 + 0.06 * (temp[i] - 28)
        f_hum = 1 - 0.008 * (hum[i] - 70)
        depletion = BASE_DEPLETION_PCT_PER_DAY * kc * f_temp * f_hum * sun[i]
        drainage = 0.25 * max(0.0, s - 70) / 30        # fast drainage when very wet
        s = s - depletion - drainage + 1.2 * rain[i]
        s = float(np.clip(s + rng.normal(0, 0.05), 5, 95))

    # Sensor noise on the recorded value
    soil_obs = np.clip(soil + rng.normal(0, 0.6, n), 0, 100)

    # Next irrigation: hours until the next "needed" observation
    next_h = np.full(n, np.nan)
    upcoming = np.where(needed == 1)[0]
    for i in range(n):
        if needed[i]:
            next_h[i] = 0.0
            continue
        k = np.searchsorted(upcoming, i + 1)
        if k < len(upcoming):
            next_h[i] = min((upcoming[k] - i) * STEP_MIN / 60, NEXT_IRRIGATION_CAP_H)
        elif (n - i) * STEP_MIN / 60 >= NEXT_IRRIGATION_CAP_H:
            next_h[i] = NEXT_IRRIGATION_CAP_H      # no need within the cap
        # else: unknown (end of season) -> row dropped

    df = pd.DataFrame({
        "timestamp": timestamps,
        "soil_moisture_pct": soil_obs.round(2),
        "temperature_c": temp.round(2),
        "humidity_pct": hum.round(2),
        "rain_probability_12h_pct": rain_prob.round(2),
        "rainfall_forecast_12h_mm": rain_mm.round(2),
        "growth_stage": stage,
        "irrigation_needed": needed,
        "watering_duration_min": duration.round(1),
        "next_irrigation_hours": np.round(next_h, 1),
        "season_id": season_id,
        "actual_rain_mm": rain.round(2),           # simulation truth, not a model input
    })
    return df.dropna(subset=["next_irrigation_hours"])


def main():
    rng = np.random.default_rng(SEED)
    seasons = [simulate_season(k + 1, d, rng) for k, d in enumerate(SEASON_STARTS)]
    full = pd.concat(seasons, ignore_index=True)

    out = Path(__file__).resolve().parent.parent / "data"
    out.mkdir(exist_ok=True)
    full.to_csv(out / "watermelon_irrigation_simulation_full.csv", index=False)

    # Training / app file: the 10 dataset fields + season_id
    cols = ["timestamp", "soil_moisture_pct", "temperature_c", "humidity_pct",
            "rain_probability_12h_pct", "rainfall_forecast_12h_mm", "growth_stage",
            "irrigation_needed", "watering_duration_min", "next_irrigation_hours", "season_id"]
    full[cols].to_csv(out / "watermelon_irrigation_dataset.csv", index=False)

    print(f"Rows: {len(full):,}  Seasons: {full.season_id.nunique()}")
    print(f"Irrigation needed: {full.irrigation_needed.mean():.1%} of rows")
    print(full.groupby("growth_stage", sort=False).irrigation_needed.agg(["count", "mean"]).round(3))


if __name__ == "__main__":
    main()
