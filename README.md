# ATHERA — Predict. Protect. Connect.

Astronaut health-monitoring prototype (Flutter app + optional FastAPI gateway).
Research prototype, **not a medical device**. All readings in demo mode are labelled DEMO DATA.
The LSTM / XGBoost models are NOT included: the app talks to them through a documented API
(see `AI_INTEGRATION.md`).

## Run the app (demo mode, no hardware, no account)

```bash
flutter create . --platforms=android,ios   # once: generates platform folders
flutter pub get
flutter run
```

Tap "Enter demo mode" on the onboarding screen.

## Build an APK to install on an Android phone

`bash tool/build_apk.sh` (needs Flutter + Android SDK). The file appears at
`build/app/outputs/flutter-apk/app-release.apk`; copy it to the phone and open it (allow "install unknown apps").
No local setup? Push this folder to GitHub: the **Build Android APK** workflow builds it, and the APK is under
Actions -> the run -> Artifacts -> `athera-apk`.

## Connect your own model (api.py / athera_ai.py)

1. Start it: `uvicorn api:app --host 0.0.0.0 --port 8000`
2. App: Settings -> AI service -> **ATHERA model** -> URL (`http://10.0.2.2:8000` on the Android emulator,
   `http://<your PC IP>:8000` on a phone) -> Test connection.
3. Plain `http://` needs `android:usesCleartextTraffic="true"` on `<application>` in
   `android/app/src/main/AndroidManifest.xml` (release builds) and an ATS exception on iOS. Use HTTPS for anything real.

Details and field mapping: `AI_INTEGRATION.md` section 0.

## Real NASA data in the app

`tools/build_real_data_assets.py <data pack dir>` turns the team's NASA data pack into two small assets:
ISS radiation dose rates (RadLab, 2019-2024, absorbed dose in µGy, never converted to mSv) and Inspiration4 crew blood
tests (OSDR, 4 people). The app shows them under Health -> Explore. This data has no heart-rate/SpO2 time series, so it
is NOT used to train the risk model (that still needs 15-minute vitals, see below).

## On-device insights (`lib/insights`)

Personal baseline (median/MAD), anomaly detection against the astronaut's own history, data-quality score, check-in
trends, and an explanation of the AI result. All pure Dart, offline, unit-tested; with too little history they say so.

## The AI service (`ai_service/`) and swapping the training data

```bash
cd ai_service
pip install -r requirements-dev.txt
python -m pytest -q                      # contract, data-validation and retraining tests
uvicorn api:app --host 0.0.0.0 --port 8000
```

When the real data arrives (CSV: `Timestamp`, `Heart_Rate`, `SBP`+`DBP` or `Blood_Pressure`, `SpO2`, `Body_Temp`,
`HRV_Stress_Index`, `Radiation_Level`, `Sleep_Hours`, `Physical_Activity_Load`; one row every 15 minutes, oldest first):

```bash
python retrain.py --data real_data.csv --data-kind real
```

It validates the file first (gaps, NaNs, impossible values, missing columns are rejected and nothing is written),
trains, saves `athera_model.joblib` + `metrics.json`, and rewrites `assets/ai/backtest.json`, which feeds the app's
**Model report card**. The card says "real" or "simulated" from `--data-kind`, so it never mislabels the data.
Rebuild the app afterwards (the report is bundled as an asset). The app and the `/predict` contract do not change.
The "critical" labels come from rule thresholds in `athera_ai.label_risk`; edit them if clinicians give better ones.

## Run with the mock AI gateway

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
pytest
```

Then in the app: Settings -> API connection -> `http://10.0.2.2:8000` (Android emulator)
or your machine's LAN IP on a real phone. Interactive API docs: `http://localhost:8000/docs`.

## Layout

- `lib/domain` models · `lib/sensors` data acquisition + demo generator · `lib/data` SQLite/memory repositories
- `lib/ai` external AI client (HTTP + fixture) · `lib/emergency` SOS + transport interface
- `lib/connectivity` link abstraction · `lib/state` app controller · `lib/ui` screens and widgets
- `backend/` FastAPI gateway with validated schemas (no ML inside)
- `docs/HARDWARE.md` sensor / radio requirements

## Status of this build

CI (GitHub Actions) runs `flutter analyze`, `flutter test`, builds the APK, and runs the `ai_service` pytest suite.
Never run on a physical device by the authoring tool: test on a phone before demoing.
