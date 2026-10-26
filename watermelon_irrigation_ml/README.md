# Watermelon Irrigation ML (offline package)

- `data/watermelon_irrigation_dataset.csv`: training dataset (10 fields + season_id)
- `data/watermelon_irrigation_simulation_full.csv`: same, plus the simulated actual rain
- `data/data_dictionary.csv`: column descriptions
- `src/generate_dataset.py`: field simulation that creates the dataset
- `src/train_models.py`: training, evaluation, ONNX export, figures
- `src/predict.py`: offline prediction with validation and post-processing
- `src/firebase_ml_service.py`: connects the models to Firebase (ESP32 → ML → Flutter app)
- `onnx/`: models for the mobile app
- `models/`: scikit-learn models
- `figures/`: charts for the paper
- `evaluation_results.json`: all metrics
- `MODEL_DOCUMENTATION.md`: full write-up

Quick start:

    pip install -r requirements.txt
    python src/predict.py sample_mobile_input.json

Run the Firebase ML service (keep it running while the system operates):

    python src/firebase_ml_service.py

It reads `irrigation/live` and `irrigation/settings/growth_stage`, and writes
`irrigation/prediction` plus `irrigation/prediction_history`.
