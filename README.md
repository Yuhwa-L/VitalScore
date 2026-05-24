# VitalScore

*Measure What Works For You*

VitalScore is a personalized intervention analytics platform, built as a native iOS app in SwiftUI, that helps users objectively measure how lifestyle interventions affect their cognitive and physical performance over time. It is not a medical device and should not be used for diagnosis or treatment.

## Service Overview

Millions of people experience fatigue, brain fog, and poor focus, but lack accessible tools to determine which lifestyle interventions actually improve their functioning. Existing wellness platforms primarily track passive biomarkers such as sleep duration, activity, and heart rate. VitalScore combines those biomarkers with short, active daily assessments to track the efficacy of interventions such as new supplements, diets, sleep schedules, or exercise routines.

Using a short daily assessment combined with wearable data, VitalScore establishes a highly personalized baseline and detects how interventions shift focus, fatigue, recovery, and cognitive performance. Functional outcomes are measured directly through eye tracking, vocal analysis, and wearable biomarkers, using active assessments inspired by validated methods from published clinical literature. Users tag different situations, such as `Morning`, `Gym`, or `Alcohol`, so similar days can be compared against similar days rather than against a single generic score.

The platform surfaces actionable insights such as *"Meditation improved alertness over the past two weeks"* or *"Magnesium improved your wellness score versus baseline."* Apple HealthKit provides continuous heart rate, HRV, step, and activity data; ARKit and iPhone sensors power the eye-tracking and motion assessments; and a cloud-based AI engine establishes personalized baselines and identifies how interventions affect them. The current MVP includes dashboard analytics, wellness scoring, insight generation, and longitudinal trend analysis. AI is used to summarize patterns and suggest low-risk things to track next, not to diagnose, treat, or make medical claims.

## Current Demo Data

VitalScore currently uses mock data so the dashboard can show history and trend graphs right away.

The demo data is stored in the repository under:

```text
VitalScore/Resources/Data/TagData/
VitalScore/Resources/Data/TagData/GazeLogs/
```

These files include sample daily records, voice sessions, and gaze logs for tags such as `Morning`, `Gym`, and `Alcohol`. In debug builds the app copies this bundled data into local app storage so the iPhone can display history and trend views without needing real HealthKit history.

## Project Layout

The app is organized by responsibility:

- `VitalScore/App` contains app startup and top-level routing.
- `VitalScore/Core/Models` contains shared app data models.
- `VitalScore/Core/DataStore` contains local storage, demo data import, exports, and saved-data helpers.
- `VitalScore/Core/Scoring` contains wellness score calculations.
- `VitalScore/Core/AI` contains direct OpenAI API clients and prompt builders.
- `VitalScore/Features/*/Views` contains screen UI.
- `VitalScore/Features/*/Services` or `Stores` contains feature logic and managers.
- `VitalScore/Features/Subscription` contains the subscription/paywall UI.
- `VitalScore/Resources/Data` contains bundled demo JSON data.
- `VitalScore/Shared/Components` contains reusable SwiftUI components.

## Requirements

- macOS
- Xcode from the Mac App Store
- An Apple ID signed into Xcode
- A connected iPhone for device testing
- XcodeGen:

```bash
brew install xcodegen
```

## Apple Account Setup

1. Open Xcode.
2. Go to `Xcode > Settings > Accounts`.
3. Add your Apple ID.
4. Select your Apple ID and confirm your Apple development team is listed.

To find your Team ID in Xcode, select your Apple ID under `Xcode > Settings > Accounts`, then look at the team details for the 10-character Team ID. You can also find it on the Apple Developer website under account membership details.

From Terminal, this command can show local Apple Development signing identities:

```bash
security find-identity -p codesigning -v
```

Use Xcode or the Apple Developer website as the source of truth for the Team ID. If the Terminal identity includes an identifier at the end, confirm it matches the team shown in Xcode before using it:

```text
Apple Development: name@example.com (TEAMID1234)
```

Use that value in `.env`:

```bash
VITALSCORE_DEVELOPMENT_TEAM=TEAMID1234
```

## Bundle Identifier Setup

Every iPhone app needs a bundle identifier that is unique to your Apple developer account. Use reverse-domain style, usually lowercase letters, numbers, and dots.

Examples:

```text
com.yourname.vitalscore
com.yourcompany.vitalscore
```

Set the same app identifier in `.env`:

```bash
VITALSCORE_BUNDLE_IDENTIFIER=com.yourname.vitalscore
```

The test bundle identifier is optional. If you do not set it, the project automatically uses the app bundle identifier plus `.tests`, such as `com.yourname.vitalscore.tests`. Only add `VITALSCORE_TEST_BUNDLE_IDENTIFIER` if Xcode test signing needs a different value.

If Xcode says the identifier is already taken, change the first part to something unique, such as your name, company, or initials.

After changing the bundle identifier, regenerate the local Xcode config and project:

```bash
./scripts/generate-local-config.sh
xcodegen generate
```

Then open `VitalScore.xcodeproj`, select the `VitalScore` target, go to `Signing & Capabilities`, choose your Apple team, and confirm Xcode shows the same bundle identifier from `.env`.

## Local Configuration

Local configuration is intentionally not committed.

Create your own `.env` file only when you need to override signing, API URLs, or AI settings. The checked-in `.env.example` is intentionally blank so no local values or secrets are copied by accident.

Common values you may need:

```bash
VITALSCORE_DEVELOPMENT_TEAM=YOUR_TEAM_ID
VITALSCORE_BUNDLE_IDENTIFIER=com.yourname.vitalscore
VITALSCORE_OPENAI_API_KEY=YOUR_OPENAI_API_KEY
VITALSCORE_OPENAI_MODEL=gpt-5-mini
```

Optional test override:

```bash
VITALSCORE_TEST_BUNDLE_IDENTIFIER=com.yourname.vitalscore.tests
```

After editing `.env`, generate the local Xcode config:

```bash
./scripts/generate-local-config.sh
xcodegen generate
```

`Config/Local.xcconfig` is generated locally and ignored by git.

## Run On iPhone

1. Connect your iPhone by USB.
2. Trust the Mac on the iPhone if prompted.
3. Open `VitalScore.xcodeproj` in Xcode.
4. Select your iPhone as the run destination.
5. Press Run.

Command-line install example:

```bash
xcodebuild -project VitalScore.xcodeproj -scheme VitalScore -destination 'platform=iOS,id=<DEVICE_UDID>' build
xcrun devicectl device install app --device <DEVICE_UDID> ~/Library/Developer/Xcode/DerivedData/VitalScore-*/Build/Products/Debug-iphoneos/VitalScore.app
```

## AI Analysis

AI analysis calls the OpenAI API directly from the app build using `VITALSCORE_OPENAI_API_KEY`.

The eye-focus summary, voice conversation, voice export analysis, and wellness suggestions all use the configured API key and model. No local Python AI server or endpoint URL is required.

After changing `.env`, regenerate local config and rebuild the app.

## Useful Commands

```bash
xcodegen generate
xcodebuild test -project VitalScore.xcodeproj -scheme VitalScore -destination 'platform=iOS,id=<DEVICE_UDID>'
```

## Notes

- Mock history and trends come from files in `VitalScore/Resources/Data/TagData`.
- Local secrets belong in `.env`, never in git.
- Generated/local files such as `Config/Local.xcconfig`, `.DS_Store`, and build output should stay out of commits.
