<div align="center">
  <h1>ChinUp</h1>
  <p>Posture monitoring for macOS, powered by AirPods motion sensors.</p>
</div>

You spend hours at a desk — hunched, slouched, craning forward without noticing.
ChinUp reads the motion sensors in your AirPods to track head pitch in real time,
nudges you when your posture slips, and keeps a history so you can see whether
you're actually improving.

## How it works

AirPods Pro contain a 9-axis IMU: a gyroscope (angular velocity), an
accelerometer (linear acceleration and gravity), and a magnetometer (heading
relative to magnetic north). Each is unreliable alone — gyroscopes drift,
accelerometers pick up vibration, magnetometers are disturbed by nearby metal.

CoreMotion fuses all three into a stable orientation estimate, represented
internally as quaternions to avoid gimbal lock, then converted to Euler angles:

- **Pitch** — nodding up and down
- **Roll** — tilting side to side
- **Yaw** — turning left and right

ChinUp watches **pitch**. Fall below your lower threshold (chin dropped toward
your chest) or rise above your upper threshold (chin tipped back) and it tells
you.

## Features

- Real-time pitch tracking with live visual feedback and a rolling timeline chart
- Independent lower and upper thresholds, with a graduated warning zone between
  good posture and a full alert
- Notification and spoken voice alerts, rate-limited to a configurable interval.
  Voice alerts play only through Bluetooth output, never your laptop speakers
- Automatic pause when AirPods are removed or disconnected, and automatic resume
  when you put them back in or they reconnect
- Suppressed alerts past ±40° pitch, on the assumption you're lying down rather
  than slouching

## Requirements

- macOS 15.0 or later
- AirPods Pro (1st generation or later), or any AirPods with motion sensors
- Xcode 16 or later to build from source (the project compiles in Swift 5 language mode)

## Building

The app is a Mac Catalyst target. `platform=macOS` alone is ambiguous — it
matches both the Catalyst and "Designed for iPad" destinations — so the variant
must be named explicitly:

```
xcodebuild -project src/ChinUp.xcodeproj -scheme ChinUp -configuration Release -destination 'platform=macOS,variant=Mac Catalyst'
```

Or use the build script, which also signs the app and installs it to
`/Applications`:

```
bash scripts/build-dmg.sh --install --no-dmg
```

Drop `--no-dmg` to produce a distributable `.dmg`. Pass `--login-item` to also
register ChinUp to launch at login. Override the signing identity with
`SIGNING_IDENTITY=...` if the auto-detected one isn't the one you want.

`DEVELOPMENT_TEAM` in the project is the placeholder `YOUR_TEAM_ID`, so the
first build will fail with a signing error. Replace it with your own Apple
Developer Team ID — in Xcode under Signing & Capabilities, or directly in
`src/ChinUp.xcodeproj/project.pbxproj` (it appears in both the Debug and
Release configs).

Because the target is Catalyst rather than native macOS, the UIKit APIs in the
source (`UIPasteboard`, `UIViewControllerRepresentable`, `Color(.secondarySystemBackground)`)
are correct and deliberate — they are not AppKit code awaiting conversion.
Conversely, macOS-only frameworks such as `ServiceManagement` are absent from
the Catalyst SDK and will not compile.

## Architecture

MVVM with SwiftUI. No persistence beyond `UserDefaults` settings — sessions are
live-only and discarded on stop. No external dependencies — system frameworks
only. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full breakdown of the data
flow, session state machine, and design decisions.

Motion is polled on a one-second interval rather than driven by continuous
CoreMotion callbacks, which cuts CPU and battery cost significantly. UI state
updates are suppressed while the window isn't visible.

## Privacy

Motion data is processed on-device and never leaves your machine. There is no
network code in this app, and no session data is stored — posture readings live
only in memory for the duration of a session. Diagnostic logs are written to `~/Library/Application Support/ChinUp/`.

## Credits

ChinUp is a derivative of [WorkWell](https://github.com/wizenheimer/workwell) by
[Nayan Kumar](https://github.com/wizenheimer), retargeted from iOS to macOS and
substantially reworked. See [NOTICE](NOTICE) for what changed.

## License

MIT — see [LICENSE](LICENSE). Copyright is held jointly by the original author
for the upstream work and by the ChinUp author for the modifications.
