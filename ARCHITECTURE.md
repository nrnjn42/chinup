# ChinUp - Architecture

Real-time head/neck posture monitor for macOS via AirPods Pro motion sensors: tracks poor posture live, voice/haptic alerts.
Mac Catalyst (`SDKROOT = iphoneos`, `SUPPORTS_MACCATALYST = YES`, iOS 18.0 deployment target, ships as macOS 15+) · Swift 5.0 language mode · SwiftUI+Charts · MVVM + service singletons · no external deps (system frameworks only). No persistence beyond `UserDefaults` settings — sessions are live-only and discarded on stop.

## Project Structure

All under `src/ChinUp/`; one `<Type>.swift` per component below, in the folder of its section heading. `ChinUpApp.swift` sits at the root.

## Data Flow

```
CMHeadphoneMotionManager (CoreMotion) --poll 1s--> motionVM (HeadphoneMotionViewModel)
motionVM → ContentView (UI binding)
         → NotificationManager → VoiceAlertManager
ConnectionCoordinator → ContentView (connection state, start/stop/cancel)
WindowVisibilityMonitor → motionVM.setUIUpdateEnabled(_:)
```

## Key Components

`ChinUpApp` (root) — @main; registers UserDefaults defaults (thresholds, notification prefs); migrates legacy single-threshold → dual lower/upper; requests notification auth on launch.

### ViewModels/
- `HeadphoneMotionViewModel` — core hub; `ObservableObject`+`@Published`. 1s timer poll of CMHeadphoneMotionManager → pitch/roll/yaw; pitch vs configurable lower/upper thresholds → `PostureQuality` good/warning/poorLow/poorHigh; session duration + poor-posture time; SessionState machine; alert dispatch via NotificationManager; disconnect detect (3+ frozen readings); removal detect (flat/horizontal angle + low variance 5+ s) and wear detect (non-horizontal 5+ s) — both always on, no setting; background opt (see Design Decisions 1-2, 4).
- `ConnectionCoordinator` — `ConnectionState` enum, connection timeout, exponential retry backoff ladder (30s base, doubling, cap 600s), start/stop/cancel session, failure handling.
- `WindowVisibilityMonitor` — Mac Catalyst window-visibility polling (1s timer) + scene-phase handling; gates `motionVM.setUIUpdateEnabled(_:)`.
- `SessionState` — `.active`, `.pausedManual`, `.pausedRemoved`, `.pausedDisconnected`.

### Views/
- `ContentView` — view body, layout sections, SwiftUI wiring only. Connection states (from ConnectionCoordinator) `.disconnected`→`.connecting`→`.connected`/`.error(String)`. Connected: PostureVisualizationView, metrics card, PostureGraphView, pause controls. Disconnected: pulsing AirPods icon, start button. Top-right is a direct gear button to Settings; End Session lives on the Pause menu and (while paused) under Resume.

### Views/Components/
- `PostureRangeSlider` — dual-thumb range slider for the good-posture zone (neither SwiftUI nor UIKit ships one). Thumbs are confined to disjoint bounds (-25…-5, 5…25) so they cannot cross.
- `PostureVisualizationView` — custom wavy circle shape + current pitch angle + posture icon/message.
- `PostureGraphView` — real-time line chart, color-coded threshold zones (green/orange/red).
- `PostureMetricsView` — circular progress ring, poor-posture %.
- `SettingsView` — two sections only: Preferences (threshold sliders, notification/sound/haptic toggles, reminder interval) and Privacy (static on-device/no-collection notice).

### Utilities/ (services)
- `NotificationManager` — singleton, dispatches `UNUserNotification` alerts; rate-limited by configurable reminder interval; blocks alerts when pitch > ±40° (user likely lying down). Types: chin too low, chin too high, pause expired, AirPods removed/disconnected/reconnected.
- `VoiceAlertManager` — singleton on `AVSpeechSynthesizer`; pre-creates utterances for instant playback; activates audio session before speech, deactivates after.
- `Logging` — timestamped logs → `~/Library/Application Support/ChinUp/chinup.log`; thread-safe via `DispatchQueue`.

## Settings (`@AppStorage` / UserDefaults)

| Key | Default | Used By |
|---|---|---|
| `lowerPostureThreshold` | -10.0° (range -25…-5) | ViewModel, GraphView, Settings |
| `upperPostureThreshold` | 15.0° (range 5…25) | ViewModel, GraphView, Settings |
| `notificationsEnabled` | true | NotificationManager |
| `soundEnabled` | true | NotificationManager |
| `reminderInterval` | 30s | NotificationManager |
| `hapticFeedback` | true | Settings |

Auto-pause on removal and auto-resume on reconnect/re-wear are unconditional — no
setting gates them.

## Session State Machine

| From | Trigger | To |
|---|---|---|
| Active | user pauses | PausedManual |
| Active | removed | PausedRemoved |
| Active | disconnected | PausedDisconnected |
| PausedManual / PausedRemoved | user resumes | Active |
| PausedRemoved | worn again (pitch within ±75° for 5+ s) | Active |
| PausedDisconnected | reconnect (motion data resumes) | Active |

## Key Design Decisions

1. Polling over continuous callbacks — 1s timer, not continuous motion updates; large CPU/battery savings.
2. Dual state tracking — `internalPoorPostureDuration` always accumulates in background; `@Published poorPostureDuration` updates only when window/UI visible → no needless SwiftUI redraws.
3. AirPods-only voice — `VoiceAlertManager` checks `AVAudioSession.currentRoute` for Bluetooth output before speaking; never plays through laptop speakers.
4. Frozen motion = disconnect — no explicit disconnect events from CMHeadphoneMotionManager, so 3 consecutive identical readings (pitch/roll/yaw within 0.001°) = disconnected.
5. Threshold zones — dual thresholds (lower = chin-down, upper = chin-up) + warning zone between lower threshold and good-posture range → graduated feedback.

## System Frameworks

SwiftUI (UI) · CoreMotion (CMHeadphoneMotionManager) · Charts (live pitch graph in `PostureGraphView`) · UserNotifications (local alerts) · AVFoundation (speech synthesis, audio session) · AudioToolbox (haptics) · Combine (`@Published` in HeadphoneMotionViewModel)
