"""
Train, evaluate, and export the three watermelon irrigation models.

  1. irrigation_needed       Random Forest classifier
  2. watering_duration_min   Random Forest regressor (trained on needed rows)
  3. next_irrigation_hours   Random Forest regressor (trained on not-needed rows)

Evaluation uses a SEASON-BASED split: seasons 1-4 for training and seasons
5-6 for testing. A random row split would leak information, because rows
30 minutes apart are almost identical.

Outputs:
  models/*.joblib            scikit-learn models
  onnx/*.onnx                mobile/offline models (ONNX Runtime)
  model_metadata.json        features, stages, post-processing rules
  evaluation_results.json    all metrics
  figures/*.png              charts for the paper

Run:  python src/train_models.py
"""

import json
from pathlib import Path

import joblib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import (accuracy_score, confusion_matrix, f1_score,
                             mean_absolute_error, mean_squared_error,
                             precision_score, r2_score, recall_score)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

ROOT = Path(__file__).resolve().parent.parent
SEED = 42

GROWTH_STAGES = ["germination", "vine_development", "flowering", "fruiting"]
NUMERIC = ["soil_moisture_pct", "temperature_c", "humidity_pct",
           "rain_probability_12h_pct", "rainfall_forecast_12h_mm", "hour"]
CATEGORICAL = ["growth_stage"]
FEATURES = NUMERIC + CATEGORICAL
TRAIN_SEASONS = [1, 2, 3, 4]
TEST_SEASONS = [5, 6]


def load():
    df = pd.read_csv(ROOT / "data" / "watermelon_irrigation_dataset.csv", parse_dates=["timestamp"])
    df["hour"] = df.timestamp.dt.hour + df.timestamp.dt.minute / 60.0
    return df


def make_pipeline(model):
    pre = ColumnTransformer([
        ("num", "passthrough", NUMERIC),
        ("stage", OneHotEncoder(categories=[GROWTH_STAGES], handle_unknown="ignore"), CATEGORICAL),
    ])
    return Pipeline([("pre", pre), ("model", model)])


def regression_metrics(y, p):
    return {"MAE": round(float(mean_absolute_error(y, p)), 3),
            "RMSE": round(float(np.sqrt(mean_squared_error(y, p))), 3),
            "R2": round(float(r2_score(y, p)), 3)}


def export_onnx(pipe, name, is_classifier):
    from skl2onnx import convert_sklearn
    from skl2onnx.common.data_types import FloatTensorType, StringTensorType

    inputs = [(c, FloatTensorType([None, 1])) for c in NUMERIC] + \
             [("growth_stage", StringTensorType([None, 1]))]
    options = {id(pipe.named_steps["model"]): {"zipmap": False}} if is_classifier else None
    onx = convert_sklearn(pipe, initial_types=inputs, options=options, target_opset=15)
    path = ROOT / "onnx" / f"{name}.onnx"
    path.write_bytes(onx.SerializeToString())
    return path


def check_onnx(path, pipe, X, is_classifier):
    import onnxruntime as ort
    sess = ort.InferenceSession(str(path))
    feed = {c: X[[c]].to_numpy(np.float32) for c in NUMERIC}
    feed["growth_stage"] = X[["growth_stage"]].to_numpy(object)
    out = sess.run(None, feed)
    if is_classifier:
        return float(np.max(np.abs(out[1][:, 1] - pipe.predict_proba(X)[:, 1])))
    return float(np.max(np.abs(out[0].ravel() - pipe.predict(X))))


def main():
    for d in ["models", "onnx", "figures"]:
        (ROOT / d).mkdir(exist_ok=True)

    df = load()
    train = df[df.season_id.isin(TRAIN_SEASONS)]
    test = df[df.season_id.isin(TEST_SEASONS)]
    results = {"dataset_rows": len(df), "train_rows": len(train), "test_rows": len(test),
               "split": "season-based: seasons 1-4 train, seasons 5-6 test"}

    # ---------- 1. irrigation_needed ----------
    clf = make_pipeline(RandomForestClassifier(
        n_estimators=100, max_depth=10, min_samples_leaf=3,
        class_weight="balanced", random_state=SEED, n_jobs=-1))
    clf.fit(train[FEATURES], train.irrigation_needed)
    pred = clf.predict(test[FEATURES])
    y = test.irrigation_needed
    cm = confusion_matrix(y, pred)
    table = ((test.soil_moisture_pct < 40) & (test.rain_probability_12h_pct < 50)).astype(int)
    results["irrigation_needed"] = {
        "model": "RandomForestClassifier(n_estimators=100, max_depth=10, min_samples_leaf=3, class_weight=balanced)",
        "accuracy": round(float(accuracy_score(y, pred)), 4),
        "precision": round(float(precision_score(y, pred)), 4),
        "recall": round(float(recall_score(y, pred)), 4),
        "f1": round(float(f1_score(y, pred)), 4),
        "confusion_matrix [[TN, FP], [FN, TP]]": cm.tolist(),
        "positive_rate_test": round(float(y.mean()), 4),
        "agreement_with_decision_table": round(float((pred == table).mean()), 4),
    }

    # ---------- 2. watering_duration_min (needed rows) ----------
    tr_n, te_n = train[train.irrigation_needed == 1], test[test.irrigation_needed == 1]
    dur = make_pipeline(RandomForestRegressor(
        n_estimators=100, max_depth=10, min_samples_leaf=3, random_state=SEED, n_jobs=-1))
    dur.fit(tr_n[FEATURES], tr_n.watering_duration_min)
    p_dur = dur.predict(te_n[FEATURES])
    results["watering_duration_min"] = {
        "model": "RandomForestRegressor(n_estimators=100, max_depth=10, min_samples_leaf=3)",
        "train_rows": len(tr_n), "test_rows": len(te_n),
        **regression_metrics(te_n.watering_duration_min, p_dur),
        "baseline_MAE_predict_mean": round(float(mean_absolute_error(
            te_n.watering_duration_min, np.full(len(te_n), tr_n.watering_duration_min.mean()))), 3),
    }

    # ---------- 3. next_irrigation_hours (not-needed rows) ----------
    tr_x, te_x = train[train.irrigation_needed == 0], test[test.irrigation_needed == 0]
    nxt = make_pipeline(RandomForestRegressor(
        n_estimators=100, max_depth=12, min_samples_leaf=5, random_state=SEED, n_jobs=-1))
    nxt.fit(tr_x[FEATURES], tr_x.next_irrigation_hours)
    p_nxt = nxt.predict(te_x[FEATURES])
    within_6 = float((np.abs(p_nxt - te_x.next_irrigation_hours) <= 6).mean())
    results["next_irrigation_hours"] = {
        "model": "RandomForestRegressor(n_estimators=100, max_depth=12, min_samples_leaf=5)",
        "train_rows": len(tr_x), "test_rows": len(te_x),
        **regression_metrics(te_x.next_irrigation_hours, p_nxt),
        "within_6_hours": round(within_6, 3),
        "baseline_MAE_predict_mean": round(float(mean_absolute_error(
            te_x.next_irrigation_hours, np.full(len(te_x), tr_x.next_irrigation_hours.mean()))), 3),
        "note": "Values are capped at 72 h (no irrigation expected within 3 days).",
    }

    # ---------- feature importance ----------
    names = NUMERIC + [f"stage_{s}" for s in GROWTH_STAGES]
    results["feature_importance"] = {
        key: dict(sorted(zip(names, np.round(p.named_steps["model"].feature_importances_, 3).tolist()),
                         key=lambda kv: -kv[1]))
        for key, p in [("irrigation_needed", clf), ("watering_duration_min", dur),
                       ("next_irrigation_hours", nxt)]
    }

    # ---------- save + export ----------
    sizes, onnx_check = {}, {}
    for name, pipe, is_clf, Xchk in [("irrigation_needed", clf, True, test[FEATURES]),
                                     ("watering_duration", dur, False, te_n[FEATURES]),
                                     ("next_irrigation_hours", nxt, False, te_x[FEATURES])]:
        joblib.dump(pipe, ROOT / "models" / f"{name}.joblib", compress=3)
        path = export_onnx(pipe, name, is_clf)
        sizes[name] = round(path.stat().st_size / 1e6, 2)
        onnx_check[name] = check_onnx(path, pipe, Xchk, is_clf)
    results["onnx_size_mb"] = sizes
    results["onnx_vs_sklearn_max_difference"] = onnx_check

    (ROOT / "evaluation_results.json").write_text(json.dumps(results, indent=2))

    metadata = {
        "feature_columns": FEATURES,
        "numeric_features": NUMERIC,
        "categorical_features": CATEGORICAL,
        "growth_stage_values": GROWTH_STAGES,
        "hour_definition": "hour + minute/60 of the reading's local time (e.g. 10:30 -> 10.5)",
        "model_type": "RandomForest (scikit-learn), exported with skl2onnx",
        "onnx_inputs": "one [N,1] tensor per feature; growth_stage is a string tensor",
        "onnx_outputs": {
            "irrigation_needed": "label (int64) and probabilities (float [N,2], column 1 = needed)",
            "watering_duration": "minutes (float [N,1])",
            "next_irrigation_hours": "hours (float [N,1])",
        },
        "post_processing": [
            "Reject growth stages not in growth_stage_values (the model cannot handle them).",
            "If irrigation_needed = 1: next_irrigation_hours = 0.",
            "If irrigation_needed = 0: watering_duration_min = 0.",
            "Clamp watering_duration_min >= 0 and next_irrigation_hours to 0..72.",
        ],
        "seed": SEED,
        "dataset_rows": len(df),
        "notes": [
            "Synthetic dataset from a field simulation (src/generate_dataset.py).",
            "irrigation_needed labels follow the ESP32 decision table (soil < 40% and rain probability < 50%).",
            "Retrain and validate on real field data before deployment.",
        ],
    }
    (ROOT / "model_metadata.json").write_text(json.dumps(metadata, indent=2))

    # ---------- figures ----------
    make_figures(df, test, te_x, p_nxt, cm)
    print(json.dumps(results, indent=2))


def make_figures(df, test, te_x, p_nxt, cm):
    # Soil moisture over one test season with irrigation events
    full = pd.read_csv(ROOT / "data" / "watermelon_irrigation_simulation_full.csv", parse_dates=["timestamp"])
    s = full[full.season_id == TEST_SEASONS[0]].iloc[: 30 * 48]
    fig, ax = plt.subplots(figsize=(11, 4))
    ax.plot(s.timestamp, s.soil_moisture_pct, lw=1, color="#3D7F3A", label="Soil moisture")
    ax.axhline(40, ls="--", color="#B8313D", lw=1, label="40% irrigation threshold")
    ev = s[(s.irrigation_needed == 1) & (s.timestamp.dt.hour.isin([6, 17])) & (s.timestamp.dt.minute == 0)]
    ax.scatter(ev.timestamp, ev.soil_moisture_pct, color="#1667A8", s=18, zorder=3, label="Irrigation")
    ax2 = ax.twinx()
    ax2.bar(s.timestamp, s.actual_rain_mm, width=0.02, color="#8fb8de", label="Rain (mm)")
    ax2.set_ylabel("Rain per 30 min (mm)")
    ax.set_ylabel("Soil moisture (%)")
    ax.set_title("Simulated field, first 30 days of a test season")
    ax.legend(loc="upper left", fontsize=8)
    fig.tight_layout()
    fig.savefig(ROOT / "figures" / "soil_moisture_simulation.png", dpi=150)
    plt.close(fig)

    # Confusion matrix
    fig, ax = plt.subplots(figsize=(4, 4))
    ax.imshow(cm, cmap="Greens")
    for (i, j), v in np.ndenumerate(cm):
        ax.text(j, i, str(v), ha="center", va="center", fontsize=12)
    ax.set_xticks([0, 1], ["Not needed", "Needed"])
    ax.set_yticks([0, 1], ["Not needed", "Needed"])
    ax.set_xlabel("Predicted")
    ax.set_ylabel("Actual")
    ax.set_title("Irrigation needed (test seasons)")
    fig.tight_layout()
    fig.savefig(ROOT / "figures" / "confusion_matrix.png", dpi=150)
    plt.close(fig)

    # Next irrigation: predicted vs actual
    fig, ax = plt.subplots(figsize=(5, 5))
    ax.scatter(te_x.next_irrigation_hours, p_nxt, s=3, alpha=0.25, color="#1E5130")
    ax.plot([0, 72], [0, 72], color="#B8313D", lw=1)
    ax.set_xlabel("Actual hours until next irrigation")
    ax.set_ylabel("Predicted hours")
    ax.set_title("Next irrigation (test seasons)")
    fig.tight_layout()
    fig.savefig(ROOT / "figures" / "next_irrigation_pred_vs_actual.png", dpi=150)
    plt.close(fig)


if __name__ == "__main__":
    main()
