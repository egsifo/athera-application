# ATHERA ↔ external AI integration

ATHERA contains **no model**. It talks to your own services (for example a TensorFlow/Keras LSTM for
forecasting and an XGBoost classifier for risk) through a small, validated HTTP contract.
Everything below describes that contract, not any trained or validated model.

```
Sensors → app (SampleStore) → ForecastRequest ──► /api/v1/forecast        (your LSTM service)
                                     │                     │
                                     │            ForecastResponse (predictions)
                                     ▼                     ▼
              RiskRequest (current + features + forecast) ► /api/v1/risk-assessment (your XGBoost service)
                                                           │
                                                   RiskResponse ──► dashboard
```

The app never calls the models directly. It calls the **gateway** in `backend/` (or any server that
implements the same contract). In `proxy` mode the gateway forwards validated requests to your services,
validates what comes back, and keeps your model URLs and keys on the server.

## 0. Connecting the team's own model server (`api.py` + `athera_ai.py`)

This is the integration that is actually wired in. In **Settings -> AI service** choose **ATHERA model**, enter the
base URL of the server and press **Test connection**.

| | |
|---|---|
| Start the server | `uvicorn api:app --host 0.0.0.0 --port 8000` (`--host 0.0.0.0` lets a phone reach it) |
| Android emulator URL | `http://10.0.2.2:8000` |
| iOS simulator URL | `http://127.0.0.1:8000` |
| Real phone URL | `http://<computer LAN IP>:8000` (same Wi-Fi) |
| Health check | `GET /` -> `{"status":"ok","predicts_minutes_ahead":120}` |
| Prediction | `POST /predict` with `{"history":[ ...13+ readings... ]}` |

Each reading has exactly these 9 numbers: `Heart_Rate, SBP, DBP, SpO2, Body_Temp, HRV_Stress_Index,
Radiation_Level, Sleep_Hours, Physical_Activity_Load`. Readings are **15 minutes apart, oldest first**, at least 13
(3 h 15 min). The app builds each reading as the mean of the stored measurements in that 15-minute bucket.

The reply (`current_status`, `predicted_status`, `minutes_ahead`, `risk_score`, `probabilities`, `reasons`, `alert`)
maps to the app like this:

| Model field | In the app |
|---|---|
| `predicted_status` SAFE / EARLY_WARNING / CRITICAL | risk class (Normal / Early warning / Critical) |
| `current_status` | "Now (model rule)" |
| `minutes_ahead` | "Predicted in 2 h" |
| `risk_score` | risk index 0-100, shown as model-defined, not a probability |
| `probabilities` | class probabilities, shown as "reported by the model" |
| `reasons` | contributing features list |
| `alert` | model warning card |

Rules the app follows:
- **No forecast chart.** This model predicts a class, not vital-sign values, so nothing is drawn as a "forecast".
- **Nothing is invented.** If any of the 9 values is missing in any of the 13 readings, the request is not sent and the
  AI screen says which values are missing.
- **Inputs the app has no sensor for.** `HRV_Stress_Index`, `Radiation_Level`, `Sleep_Hours` and
  `Physical_Activity_Load` have no source outside demo mode yet. Outside demo mode the AI screen reports them as missing
  until a sensor or manual-entry source is added (`AppController._modelRows`).
- **Demo mode** feeds the model SIMULATED values (`DemoGenerator.modelContext`) and the result is labelled DEMO INPUT.
  The simulated units/scales for the four extra inputs are placeholders: match them to your training data first.
- The model sends no timestamp or version; the app uses the time it received the reply and shows version "not reported".
- Errors: HTTP 400 `detail` from your server is shown as-is; network errors show "AI service unavailable" and the
  rest of the app keeps working.
- Tests: `flutter test test/athera_model_service_test.dart`.

## 1. Where to configure the AI base URL

| Where | How |
|---|---|
| Build-time default | `flutter run --dart-define=ATHERA_AI_BASE_URL=http://192.168.1.20:8000` (also `ATHERA_AI_MODE=gateway`, `ATHERA_DEMO_MODE=false`). See `lib/core/config.dart`. |
| Run-time (recommended) | **Settings → AI service → HTTP gateway**, enter the URL, optional API key, tap **Test connection**. |

The API key is typed in the app and stored only in the platform keystore (`flutter_secure_storage`).
It is never compiled in and never written to shared preferences.

Android emulator reaches your computer at `http://10.0.2.2:8000`. A physical phone needs your computer's
LAN address. Android blocks plain `http://` to non-local hosts by default; use `https://` for anything real.

## 2. Run the app against the mock gateway

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env            # ATHERA_GATEWAY_MODE=mock
set -a; source .env; set +a
uvicorn app.main:app --host 0.0.0.0 --port 8000
# interactive docs: http://localhost:8000/docs
```

In the app: Settings → AI service → **HTTP gateway** → URL → **Test connection**.
Mock mode returns results with `"status": "mock"`; the app labels them **ILLUSTRATIVE**.
`ATHERA_MOCK_RISK_CLASS=early_warning` changes the class. Send header `X-Mock-Error: 503` to make an
endpoint fail on purpose and see the "AI service unavailable" path.

The app also has built-in **Demo fixtures** (no network at all) for offline demos.

## 3. Point the app at your real service

1. Host your models behind HTTP endpoints that accept the *forecast* and *risk* payloads below
   (the gateway forwards the request body unchanged and expects a response matching the schema).
2. Run the gateway in proxy mode:
   ```bash
   ATHERA_GATEWAY_MODE=proxy
   ATHERA_UPSTREAM_FORECAST_URL=https://lstm.internal.example/predict
   ATHERA_UPSTREAM_RISK_URL=https://xgb.internal.example/classify
   ATHERA_UPSTREAM_API_KEY=...        # stays on the server
   ATHERA_API_KEY=...                 # what the mobile app must send as X-API-Key
   ATHERA_SUPPORTED_HORIZONS=300,600,1800   # must match what the LSTM was trained for
   ```
3. Or skip the gateway and expose the same four endpoints from your own service.
4. In the app choose HTTP gateway, enter the URL and key, **Test connection**.

## 4. How the app sends history

`POST /api/v1/forecast` — the app builds a **regular grid** (default 60 samples, 60 s apart) ending now.
Missing slots are sent as objects without that vital (never zero-filled). If less than 50 % of the grid is
populated the app does **not** send the request and shows why.

```json
{
  "astronaut_id": "demo-astronaut-01",
  "window_size": 60,
  "sampling_interval_seconds": 60,
  "prediction_horizon_seconds": 600,
  "measurements": [
    { "timestamp": "2026-10-19T11:01:00Z", "heart_rate_bpm": 85, "spo2_percent": 98,
      "temperature_celsius": 36.8, "respiratory_rate_bpm": 16 }
  ]
}
```

The example shows one row for readability. The gateway rejects (HTTP 422, with *all* problems listed) when:
`len(measurements) != window_size`, window outside `[ATHERA_MIN_WINDOW_SIZE, ATHERA_MAX_WINDOW_SIZE]`,
horizon not in `ATHERA_SUPPORTED_HORIZONS`, timestamps not strictly increasing or off the
`sampling_interval_seconds` grid, or no core vital has ≥ `ATHERA_MIN_COMPLETENESS` populated.
Your model service should repeat the checks that matter for *its* training (feature count, scaling, order).

| Field | Required | Nullable | Validation |
|---|---|---|---|
| `astronaut_id` | yes | no | 1–64 chars, `[A-Za-z0-9_-]` |
| `window_size` | yes | no | integer, must equal `len(measurements)` |
| `sampling_interval_seconds` | yes | no | 1–3600 |
| `prediction_horizon_seconds` | yes | no | in supported horizons, ≥ sampling interval |
| `measurements[].timestamp` | yes | no | timezone-aware ISO-8601, strictly increasing |
| `measurements[].heart_rate_bpm` | no | omitted = not measured | 20–250 |
| `…spo2_percent` | no | omitted | 50–100 |
| `…temperature_celsius` | no | omitted | 30–45 |
| `…respiratory_rate_bpm` | no | omitted | 4–60 |
| `…systolic_mmhg` / `diastolic_mmhg` | no | omitted | 50–260 / 20–160 |

Unknown fields are **rejected** in requests (typos fail loudly).

## 5. How the app receives results

`ForecastResponse` (unknown extra fields are ignored so you can add fields without breaking old apps):

```json
{
  "astronaut_id": "demo-astronaut-01",
  "model_name": "LSTM",
  "model_version": "your-version",
  "status": "ok",
  "prediction_horizon_seconds": 600,
  "step_seconds": 60,
  "predictions": [
    { "timestamp": "2026-10-19T12:01:00Z", "heart_rate_bpm": 92, "spo2_percent": 97.5,
      "temperature_celsius": 37.0, "respiratory_rate_bpm": 18 }
  ],
  "generated_at": "2026-10-19T12:00:01Z",
  "data_quality": { "input_completeness": { "heart_rate_bpm": 0.97 }, "notes": [] }
}
```

Required: `astronaut_id`, `model_name`, `model_version`, `status` (`ok` | `mock` | `degraded`),
`prediction_horizon_seconds`, `step_seconds` (≤ horizon), `predictions` (≥ 1, strictly increasing
timestamps), `generated_at`. Optional/nullable: each predicted vital, `data_quality`.
Predicted values are drawn only as **dashed violet** lines with a PREDICTED tag — never as measurements.

`POST /api/v1/risk-assessment` request:

```json
{
  "astronaut_id": "demo-astronaut-01",
  "assessed_at": "2026-10-19T12:00:02Z",
  "current": { "timestamp": "2026-10-19T12:00:00Z", "heart_rate_bpm": 85, "spo2_percent": 98 },
  "features": { "hr_mean_5m": 84.2, "hr_slope_per_h": 1.3, "rr_mean_5m": 16.1 },
  "forecast": { "model_name": "LSTM", "model_version": "your-version", "step_seconds": 60,
                "predictions": [ { "timestamp": "2026-10-19T12:01:00Z", "heart_rate_bpm": 92 } ] }
}
```

`features` is a free-form `name → number|null` map (max 200). **The final feature set belongs to the
XGBoost model owner**: see §10.

`RiskResponse`:

```json
{
  "astronaut_id": "demo-astronaut-01",
  "model_name": "XGBoost",
  "model_version": "your-version",
  "status": "ok",
  "risk_class": "early_warning",
  "risk_score": null,
  "class_probabilities": null,
  "generated_at": "2026-10-19T12:00:02Z",
  "contributing_features": [ { "feature": "hr_slope_per_h", "direction": "increase", "weight": 0.31 } ],
  "warnings": [ { "code": "RR_RISING", "message": "Respiratory rate trending up", "severity": "warning" } ],
  "anomalies": [],
  "data_quality": null
}
```

| Field | Required | Nullable | Notes |
|---|---|---|---|
| `risk_class` | yes | no | `normal` \| `early_warning` \| `critical` \| `unknown` |
| `risk_score` | no | **yes** | 0–100 index defined by you. **Not a probability.** Shown as "index". |
| `class_probabilities` | no | **yes** | Only if the model produces them; must sum to 1 ±0.01. The app **never derives** probabilities from the score and shows none when null. |
| `contributing_features[].direction` | no | yes | `increase` \| `decrease` |
| `warnings`, `anomalies` | no | empty list | Shown as "Reported by the AI service" |
| `status` | yes | no | `ok` \| `mock` \| `degraded` |

Other endpoints: `GET /api/v1/model-status` (versions, supported horizons, window limits, used to build the
horizon selector), `GET /api/v1/predictions?astronaut_id=…&limit=50`, `GET /health` (no auth).
No confidence or accuracy number is ever displayed unless your model returns probabilities.

## 6. How the LSTM output feeds the risk request

`AppController.refreshAi` (`lib/state/app_controller.dart`) runs the chain:
`getModelStatus → build window → getForecast → getRiskAssessment(RiskRequest(current, features, forecast))`.
`ForecastSummaryDto.fromResult` copies the predictions from the validated forecast response into the risk
request. If the forecast fails, **no risk request is sent** and the error is shown; the app never fabricates
a forecast. Feature engineering currently lives in `lib/ai/ai_input_builder.dart`
(`current`, `features`, `window`, `completeness`).

## 7. Errors and unavailable services

| Situation | App behaviour |
|---|---|
| Network down / refused | "AI service unavailable" banner; last stored result stays visible and marked **STALE** after 15 min; an `AI service unavailable` alert is raised once and resolved on recovery |
| Timeout (8 s) | "AI service timed out" |
| 401 | "AI service rejected the API key" (not retried) |
| 422 / validation | "Request not sent" with the reasons (not retried) |
| 5xx, timeout, unreachable | retried with back-off (400 ms, 1.2 s), then reported |
| Response fails schema | "AI service returned an invalid response" with field paths. Nothing is guessed or defaulted |
| Not enough sensor data | request is not sent; message says how full the window is |

Rule-based monitoring, charts, crew and SOS keep working in every case. Gateway error bodies look like
`{"error": {"code": "...", "message": "...", "details": ["..."]}}`.

## 8. Testing the integration

```bash
cd backend && python3 -m unittest discover -s tests -v     # contract, validation, gateway, API tests
curl -s localhost:8000/api/v1/model-status | python3 -m json.tool
curl -s -X POST localhost:8000/api/v1/forecast -H 'Content-Type: application/json' -d @sample_forecast.json
curl -s -X POST localhost:8000/api/v1/risk-assessment -H 'Content-Type: application/json' -d @sample_risk.json
curl -s -X POST localhost:8000/api/v1/forecast -H 'X-Mock-Error: 503' ...   # failure path
```

Build `sample_forecast.json` from §4 (60 rows, 60 s apart; `backend/tests/helpers.py` shows how). Mock results
carry `"status": "mock"`. The `/docs` page lets you try each call. The API tests need `fastapi` and `httpx`
installed; they skip themselves if not.

## 9. Deploying your model service securely

* Terminate TLS (https) in front of the gateway and models. Do not expose model services directly to phones.
* Set `ATHERA_API_KEY`; rotate it. This is a shared secret, not user authentication. For multi-user
  deployments put the gateway behind OIDC/OAuth and verify tokens server-side (see `AccessPolicy`).
* Keep `ATHERA_UPSTREAM_*` URLs and keys server-side only. Run the gateway as a non-root user, on a private
  network to the models, with request size limits at the proxy.
* Logs contain astronaut ids and sizes, never measurements or keys. Keep it that way.
* Treat the data as health data: encrypt at rest, define retention, and get ethics/privacy approval before
  any real person's data is used. Synthetic demo data must never be mixed with real data
  (every demo row is flagged `is_simulated`).
* Validate, version and monitor your models independently. A model passing the contract says nothing about
  clinical validity.

## 10. What changes when your final schemas exist

| Change | Where |
|---|---|
| Exact feature set / names / order for XGBoost | `lib/ai/ai_input_builder.dart` (`features`) and the `features` map documented here. Keep names identical to training |
| Window length, sampling interval, supported horizons | `ATHERA_SUPPORTED_HORIZONS`, `ATHERA_MIN/MAX_WINDOW_SIZE` and `windowSize`/`interval` in `AppController.refreshAi` |
| Extra vitals (e.g. HRV, stress) | add a `VitalType` (`lib/domain/models.dart`) with `apiField`, and the matching fields in `backend/app/schemas.py` |
| Different response shape | `backend/app/schemas.py` (gateway) and `lib/domain/ai_models.dart` (`*.parse`); parsing is strict about required fields, so update both and the tests |
| Risk classes | `RiskClass` in `ai_models.dart` + `RiskClass` literal in `schemas.py` |
| Real calibration / probabilities | return `class_probabilities`; the UI will display them automatically |
| Auth | replace the `X-API-Key` check in `backend/app/main.py`; app side in `HttpAiService` |
| Replace HTTP entirely | implement `AiService` (`lib/ai/ai_service.dart`), select it in `AppController._configureAi` |
