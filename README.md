# VitalScore

A SwiftUI wellness-tracking iOS app MVP that lets you pick a lifestyle experiment (e.g. *No Alcohol*, *Magnesium*, *Morning Sunlight*) and watch how a daily wellness score moves against your own baseline. Currently wired to mock health data so the full UI flow can be demoed without HealthKit.

> Wellness tool, not a medical device. Not for diagnosis or treatment.

## What's in the MVP

- **Onboarding** → mock **Health permission sheet** (iOS-style, no real HealthKit calls) → **Experiment selection** → **Dashboard**.
- **Dashboard** with metric cards for Sleep, Resting Heart Rate, HRV, Steps, Active Energy, and a computed Wellness Delta. Pull-to-refresh and a toolbar ↻ refresh.
- **Eye-Focus Test** — 30-second test that combines a reaction-time mini-game (tap when the dot turns red) with **live gaze tracking** from the front camera. Produces a blended `eyeFocusScore`, separate reaction/gaze metrics, and an optional short AI summary.
- **Face-position guide** before each test (`FaceGuideOverlay`) — dashed oval + live dot, with distance/centering checks (good range 0.22–0.40 m) that gate the **Begin Calibration** button until the user is framed correctly.
- **9-point gaze calibration** runs immediately before every test — fixate center, edges, and corners (`GazeCalibrator.targets`). `CalibrationTransform.solve` robustly fits an affine/quadratic map from raw gaze to screen coordinates; the resulting transform is applied to every sample during the run.
- **Two gaze backends, auto-selected**: ARKit `lookAtPoint` on TrueDepth iPhones, Vision face-landmark detection on RGB cameras. Falls back to reaction-only if no camera is available.
- **Per-test JSON log** of gaze samples + aggregated metrics is written to the app's Documents folder for debugging and re-analysis. The post-test user screen does not show raw JSON.
- **OpenAI eye-focus summary** uses the Responses API to turn the computed result and downsampled log into short, non-medical section summaries with a confidence value. The app never asks the model to diagnose disease.
- **Insight report** generated after each eye-focus run by `WellnessScoreEngine`, comparing today's metrics to a rolling 7-day baseline. After the result screen, tapping **Done** returns directly to the dashboard.
- **Settings** screen (gear icon, top-left of dashboard): account info, change experiment, mock-data tools, about, **Reset App**.
- **In-app debug helpers**: `Generate Random Data` button and seeded JSON dataset (`VitalScore/Resources/MockData/health_seed.json`).

## Project structure

Feature-grouped: each user-facing flow owns its view + its dedicated manager. Shared concerns (models, persistence, reusable components) live in `Core/` and `Shared/`. The Mac-side camera bridge lives outside the app target in `Tools/`.

```
VitalScore/
├── App/
│   ├── VitalScoreApp.swift                # App entry; DEBUG launch resets all state
│   └── ContentView.swift                  # Top-level router: Onboarding → Permission → Experiment → Dashboard
├── Features/
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   ├── HealthPermission/
│   │   ├── HealthPermissionView.swift     # + MockHealthAuthorizationSheet
│   │   └── HealthKitManager.swift         # Mock data provider (no real HKHealthStore calls)
│   ├── Experiment/
│   │   ├── ExperimentSelectionView.swift
│   │   └── ExperimentManager.swift
│   ├── Dashboard/
│   │   ├── HealthDashboardView.swift
│   │   └── WellnessScoreEngine.swift      # Baseline + weighted delta scoring (now includes gaze)
│   ├── EyeFocus/
│   │   ├── EyeFocusTestView.swift         # SwiftUI test UI: face-guide → calibration → countdown → run → result
│   │   ├── EyeFocusTestManager.swift      # Phase state machine (idle/ready/calibrating/countdown/running/finished) + backend selector + gaze buffer
│   │   ├── GazeTrackingService.swift      # ARKit ARFaceAnchor → lookAtPoint → screen-normalized gaze
│   │   ├── GazeARView.swift               # ARSCNView wrapper (TrueDepth iPhone only)
│   │   ├── VisionGazeTrackingService.swift # AVFoundation + VNDetectFaceLandmarksRequest fallback
│   │   ├── CameraPreviewView.swift        # AVCaptureVideoPreviewLayer SwiftUI wrapper
│   │   ├── FaceGuideOverlay.swift         # Dashed oval + face dot + distance/centering status (good/yellow/red)
│   │   ├── GazeDataLogger.swift           # Per-test JSON log writer (Documents/GazeLogs/)
│   │   ├── EyeFocusLogsView.swift         # Developer/debug log browser + re-analysis
│   │   └── OpenAIEyeFocusSummaryClient.swift # Responses API client + structured summary prompt/schema
│   ├── Insight/
│   │   └── InsightReportView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Core/
│   ├── Models/
│   │   ├── DailyHealthRecord.swift        # + gaze fields (accuracy, stability, blink rate, score)
│   │   ├── BaselineMetrics.swift          # + averageGazeScore, averageGazeAccuracyPx
│   │   ├── ExperimentTag.swift
│   │   ├── EyeFocusTestResult.swift       # reactionScore + gazeMetrics? + aiSummary? + blend()
│   │   ├── EyeFocusAISummary.swift        # Stored OpenAI summary + confidence + sections
│   │   ├── GazeMetrics.swift              # Aggregated gaze metrics + GazeSample + GazeAggregator
│   │   ├── GazeCalibration.swift          # CalibrationTransform + robust affine/quadratic solve + 9-point target set
│   │   └── WellnessDeltaResult.swift
│   └── Storage/
│       └── LocalStorageManager.swift      # UserDefaults-backed persistence
├── Shared/
│   └── Components/
│       ├── MetricCard.swift
│       └── DisclaimerBanner.swift
└── Resources/
    ├── Info.plist                         # HealthKit + Camera usage strings
    ├── VitalScore.entitlements            # HealthKit capability
    └── MockData/
        └── health_seed.json               # 7 days of mock metrics, loaded on launch

VitalScoreTests/                           # XCTest suite (6 test files)
project.yml                                # XcodeGen spec (Xcode project is generated)
```

The `VitalScore.xcodeproj/` is generated and `.gitignore`d — regenerate with `xcodegen generate`.

## Per-MacBook configuration

Machine-specific signing and service URLs live in `.env`, which is intentionally ignored by git.

1. Copy `.env.example` to `.env`.
2. Set your Apple team, bundle identifiers, signing values, and URLs.
3. Run `./scripts/generate-local-config.sh`.
4. Run `xcodegen generate`.

The generated `Config/Local.xcconfig` is also ignored. Xcode reads `Config/VitalScore.xcconfig`, which contains safe defaults and optionally includes `Config/Local.xcconfig` when present.

## Voice checks

The default Voice button runs the fixed prompt sequence: quiet calibration, first sustained vowel, repeated sustained vowel, counting from 1 to 10, and the read-aloud sentence. The prompt text is shown on screen before each recording. Audio is analyzed on device for acoustic features, and raw audio is not stored unless the debug-only WAV export is explicitly enabled.

The AI-guided freestyle talk is a separate advanced feature on the dashboard. It skips the fixed acoustic prompts and starts directly with a short conversational AI question. The app speaks, listens to the user's response, transcribes it with iOS Speech, auto-sends after a short pause or when the user taps Send Now, asks `/ai/voice-chat-turn` for the next short reply, and repeats up to three quick turns. Provider keys stay in `.env`; the iOS app only receives `VITALSCORE_AI_DIALOG_ENDPOINT`, provider, model config, and optional voice identifier.

```bash
./scripts/generate-local-config.sh
xcodegen generate
python3 scripts/ai-dialog-server.py
```

For simulator testing, use `VITALSCORE_AI_DIALOG_ENDPOINT=http://127.0.0.1:8787/ai/voice-conversation`. For a physical iPhone, run the server on an address the phone can reach, such as `VITALSCORE_AI_DIALOG_HOST=0.0.0.0` and `VITALSCORE_AI_DIALOG_ENDPOINT=http://<your-mac-lan-ip>:8787/ai/voice-conversation`, then regenerate `Config/Local.xcconfig`.

The local server posts to OpenAI's Responses API with strict JSON schemas and returns `VoiceAIConversationPlan` for setup, `VoiceAIChatTurnResponse` for live turn replies, and `VoiceAIAnalysisResponse` for post-session analysis. Prompts, replies, and analysis are constrained to wellness reflection and must not diagnose, treat, predict disease, or claim causation.

When `Settings > Voice Export (Debug) > Save raw WAV samples` and `Attach WAV samples to AI analysis` are both enabled, the app includes the debug WAV clips in the `/ai/voice-analysis` request. The local server then uses `VITALSCORE_AI_AUDIO_ANALYSIS_MODEL` (`gpt-audio-1.5` by default) through OpenAI Chat Completions so GPT can inspect the audio alongside the structured acoustic features. This mode is development-only and should only be used after explicit raw-audio consent.

Set `VITALSCORE_AI_VOICE_IDENTIFIER` in `.env` to force a specific iOS text-to-speech voice by identifier or name substring, such as `Ava` or `Samantha`. If the selected voice is not installed on the iPhone, iOS falls back to the best available enhanced or premium English voice.

## Multimodal analysis exports

After each eye-focus or voice test, the app writes an analysis-ready JSON file plus `analysis_exports.jsonl` under the app's Documents directory at `VitalScoreAnalysisExports/`. Each export includes schema version, available/missing modalities, privacy notes, daily health summary, eye or voice result payload, prompt text, question/task background, AI conversation transcripts when present, and a flattened feature vector suitable for later LLM input. Raw audio and raw camera frames are not stored.

After each voice session, if `VITALSCORE_AI_DIALOG_ENDPOINT` is configured, the app posts the completed export JSON to the local `/ai/voice-analysis` endpoint. The request includes the stored export, the background/rationale for each voice prompt, and recent voice-session summaries. The AI response is saved beside the export as `*_voice_ai_analysis_*.json` and indexed in `ai_analysis_results.jsonl`; if the endpoint is unavailable, the local export remains available for later processing.

### Voice feature validation workflow

Debug builds include an internal opt-in setting, `Settings > Voice Export (Debug) > Save raw WAV samples`. When enabled, the app writes local development-only WAV files and a `manifest.json` under the app Documents folder at `VitalScoreDebugVoiceWAV/`. The separate `Attach WAV samples to AI analysis` toggle additionally sends those clips to the configured local AI server after each voice test. These modes are only for local feature validation and should not be shipped, uploaded, or used without explicit consent.

To compare those samples with canonical openSMILE eGeMAPS, install openSMILE locally so `SMILExtract` and `eGeMAPSv02.conf` are available, then run:

```bash
python3 scripts/compare-opensmile-egemaps.py \
  --wav-dir /path/to/VitalScoreDebugVoiceWAV/session-folder \
  --app-export /path/to/VitalScoreAnalysisExports/latest_voice_tracking_export.json \
  --output opensmile_comparison_output/comparison.json
```

Current feature confidence is intentionally conservative:

- Score eligible proxy: loudness mean/variation, energy movement proxy, voiced segment rate, mean voiced length.
- Proxy but not score weighted yet: F0 mean/std and HNR.
- Unsupported until canonical comparison: jitter, shimmer, MFCC placeholders, alpha ratio, Hammarberg index, spectral slopes.

When `.env` changes, regenerate the local config and rebuild/reinstall the app. The key is expanded into the app's `Info.plist` at build time; changing `.env` alone does not update an already-installed app.

```bash
./scripts/generate-local-config.sh
xcodebuild -scheme VitalScore -configuration Debug -destination 'platform=iOS,id=<DEVICE_UDID>' build
xcrun devicectl device install app --device <DEVICE_UDID> ~/Library/Developer/Xcode/DerivedData/VitalScore-*/Build/Products/Debug-iphoneos/VitalScore.app
```

## Wellness score (current weights)

`WellnessScoreEngine` weights five inputs against the rolling 7-day baseline:

| Metric              | Weight |
|---------------------|--------|
| Sleep               | 30%    |
| Resting Heart Rate  | 25%    |
| HRV                 | 20%    |
| Eye-Focus Score     | 15%    |
| Steps               | 10%    |

`eyeFocusScore` is itself a blend of reaction-time and gaze sub-scores (see below). Tune weights in `VitalScore/Features/Dashboard/WellnessScoreEngine.swift`.

## Eye-focus test backends

The test runs the same 30-second dot-tap reaction game everywhere, but layers gaze tracking on top using whichever backend the device supports:

| Backend | When auto-selected | What it uses | Precision |
|---|---|---|---|
| `arkit` | iPhone X+ (TrueDepth front camera) | `ARFaceAnchor.lookAtPoint` projected to screen coords | High — depth-aware |
| `vision` | iPhones without TrueDepth | AVFoundation front camera + `VNDetectFaceLandmarksRequest` (pupil-relative-to-eye geometry) | Moderate — RGB only |
| `none` | No camera / face tracking | Reaction-time only | n/a |

Selection logic lives in `EyeFocusTestManager.swift` (`GazeBackend.detect()`). Calibration (next section) applies on top of whichever backend was picked.

### Test flow (per run)

```
idle  →  ready (face-guide oval green)  →  calibrating (9 points, 2.2s each, collect from 0.7s)
                                                    │
                                                    ▼
                              CalibrationTransform.solve (robust affine/quadratic)
                                                    │
                                                    ▼
                       countdown (3,2,1)  →  running (30s)  →  processing  →  result
```

`FaceGuideOverlay` reads the backend's face center + estimated distance and turns the oval green only when the user is within `goodDistanceRange` (0.22–0.40 m) and centered within ±0.20 of the frame; **Begin Calibration** is disabled until then.

The result screen shows the numeric score, reaction/gaze metrics, and, when configured, short AI-generated section summaries. It does not show the raw JSON log. Tapping **Done** saves the result and returns to the dashboard.

### Calibration

Nine fixation targets — center plus eight edge/corner points in normalized screen coordinates:

```
(0.50, 0.50), (0.15, 0.20), (0.50, 0.20), (0.85, 0.20),
(0.85, 0.50), (0.85, 0.80), (0.50, 0.80), (0.15, 0.80),
(0.15, 0.50)
```

For each target the manager waits 0.7 s for the user to fixate, then collects until 2.2 s. Calibration keeps stable, non-blink samples, uses a robust mean per target, and evaluates affine/quadratic candidates with a small complexity penalty. The selected transform is applied to every gaze sample for the rest of the test; mean residual, sample count, and baseline head pose are retained as quality indicators.

### Score blending

```
eyeFocusScore = (gazeMetrics == nil)
  ? reactionScore
  : 0.4 * reactionScore + 0.6 * gazeScore
```

Reaction sub-score and gaze sub-score are each clamped to `[0, 100]` using the formulas in `EyeFocusTestManager.calculateScore` and `GazeMetrics.calculateScore`.

### Gaze data pipeline

```
ARKit  ARFaceAnchor (~60 Hz)      Vision  VNDetectFaceLandmarksRequest (~15 Hz)
              │                                          │
              ▼                                          ▼
     project lookAtPoint                     pupil-relative-to-eye geometry,
     through camera transform                stretch [0.3,0.7]→[0,1], flip Y
              │                                          │
              └────────────────┬─────────────────────────┘
                               ▼
            CGPoint in normalized screen coords (0…1)
                               │
                               ▼
            GazeSample { timestamp, rawGazePoint, gazePoint, targetPoint (= dot),
                         blink values, trackingValid, motion/head-pose quality flags }
                               │
            buffered in EyeFocusTestManager during the 30s test
                               │
                               ▼
            GazeAggregator.aggregate(samples, durationSeconds:)
                               │
                               ▼
            GazeMetrics { gazeAccuracyPx, gazeStabilityPx,
                          fixationDurationMs, blinkRatePerMin,
                          trackingLossPct, gazeScore, sampleCount }
                               │
            ┌──────────────────┼───────────────────────┬──────────────────────┐
            ▼                  ▼                       ▼                      ▼
     blend into            persist into          write JSON via        summarize via
     eyeFocusScore         DailyHealthRecord     GazeDataLogger        OpenAI Responses API
                                                 (Documents/GazeLogs/) (optional)
```

Each test writes one JSON file under `Documents/GazeLogs/`. Logs contain backend metadata, screen size, calibration summary, reaction summary, aggregate metrics, and per-frame gaze samples. Logs are for developer debugging and API re-analysis only; the normal post-test UI shows only short section summaries.

The OpenAI request sends computed metrics plus a capped/downsampled log trace (`maxSamplesToSend = 400`) and requests strict JSON:

```json
{
  "overall_summary": "Short user-facing summary.",
  "confidence": "high | medium | low",
  "sections": [
    { "title": "Reaction", "summary": "One short sentence." },
    { "title": "Gaze accuracy", "summary": "One short sentence." },
    { "title": "Gaze stability", "summary": "One short sentence." },
    { "title": "Tracking quality", "summary": "One short sentence." },
    { "title": "Calibration", "summary": "One short sentence." },
    { "title": "Practical note", "summary": "One short sentence." }
  ]
}
```

The summary prompt is intentionally non-medical: it forbids diagnosis, treatment advice, raw JSON, raw samples, file paths, logs, code blocks, and technical dumps. If tracking quality is weak, the model should lower confidence and say to interpret the result cautiously.

## Running the eye-focus test

The eye-focus test requires real front-camera frames, so it must run on a physical iPhone — the iOS Simulator cannot access the host Mac's camera via `AVCaptureDevice`. Build/run on a device (Xcode → select your iPhone as destination), then walk through Onboarding → Permission → Experiment → Dashboard → **Run Eye-Focus Test**. The idle screen shows the live front-camera feed with the face-guide oval; once it turns green tap **Begin Calibration**, fixate each of the nine dots, then run the 30 s reaction test.

After processing, the app shows the eye-focus score, key metrics, and short AI summary sections if `VITALSCORE_OPENAI_API_KEY` was configured for the build. Tap **Done** to save and return directly to the dashboard.

The rest of the app (dashboard, settings, mock data, score engine) runs fine in the simulator.

## Mock data

The dashboard reads from `VitalScore/Resources/MockData/health_seed.json` — a flat list of `dayOffset`-relative rows for the past week. The file is committed so every teammate sees identical values on first run.

```jsonc
{ "dayOffset": 0, "restingHeartRateBPM": 62, "hrvMs": 64, "steps": 6210, "activeEnergyKcal": 305, "sleepHours": 7.2 }
```

Tap **Generate Random Data** in Settings (or on the dashboard in DEBUG) to randomize the in-memory values without editing the file.

## DEBUG behavior (simulator only)

- **Reset-on-launch**: `VitalScoreApp.init()` calls `storage.resetAll()` under `#if DEBUG`, so each simulator launch starts from the welcome screen with a fresh permission flow. Remove the `#if DEBUG` block before shipping.
- **Dashboard debug buttons**: `Generate Random Data` button is `#if DEBUG`-gated.

## Building

The Xcode project is generated by [XcodeGen](https://github.com/yonkeltron/xcodegen) from `project.yml`.

```bash
# one-time
brew install xcodegen

# generate / regenerate the .xcodeproj after editing project.yml or adding source files
xcodegen generate

# open in Xcode
open VitalScore.xcodeproj

# or build from CLI for the simulator
xcodebuild -project VitalScore.xcodeproj \
           -scheme VitalScore \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

**Requirements:** Xcode 15+, iOS 17.0+ deployment target, Swift 5.9.

If `xcodebuild` complains *"tool requires Xcode but active developer directory is Command Line Tools"*, run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Tests

`VitalScoreTests/` covers the score engine, baseline calculations, eye-focus scoring, eye-summary storage, voice scoring, and sleep parsing.

```bash
xcodebuild -project VitalScore.xcodeproj -scheme VitalScore \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Or in Xcode: ⌘U.

## Roadmap (out of scope for this MVP)

- Swap `HealthKitManager` back to a real `HKHealthStore`-backed implementation (the original wiring is in git history; Info.plist + entitlements are still in place).
- Persist daily records into a richer store (Core Data / SwiftData).
- Persist the per-user `CalibrationTransform` across sessions and re-prompt only when residual error grows.
- Real notifications for the daily reminder and weekly insight toggles in Settings.
- Replace mock Apple ID / Privacy / Terms placeholders with real services.
