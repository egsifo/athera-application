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

Not yet compiled or run in the authoring sandbox (no Flutter SDK, no PyPI access there).
Run `flutter analyze && flutter test` and `pytest` first and fix anything they report.
