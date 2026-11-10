# Reelmint

**A private, ad-free screen recorder for Android.**

Reelmint records your screen in high quality with device audio, microphone and an optional
facecam, and includes a built-in editor for trimming, compressing, merging and more.
There are no ads, no accounts, no analytics and no watermark. The release build does
not request internet access, so your recordings never leave your phone unless you share them.

- **Platform:** Android 10 (API 29) and newer
- **Built with:** Flutter (UI) and Kotlin (recording engine, overlays, media tools)
- **License:** [MIT](LICENSE)

## Download

Get the latest APK from the [Releases](https://github.com/mohdaffankhan/reelmint/releases) page.

| File | Use it for |
|---|---|
| `Reelmint-<version>-arm64-v8a.apk` | Most phones made in the last several years (recommended) |
| `Reelmint-<version>-armeabi-v7a.apk` | Older 32-bit phones |
| `Reelmint-<version>-x86_64.apk` | Emulators and x86 devices |
| `Reelmint-<version>-universal.apk` | Any device (larger download) |

Not sure which one to pick? Use the universal APK. Checksums are in `SHA256SUMS.txt` on each release.

## Features

### Recording
- Hardware H.264 capture at native, 1440p, 1080p, 720p or 480p, from 24 to 120 fps (capped to the display), with automatic or manual bitrate
- Device audio, microphone, or both, mixed into a single AAC track. The microphone can be muted and unmuted mid-recording.
- Seamless pause and resume
- Countdown, and portrait or landscape lock
- **Facecam:** a round front-camera bubble you can drag and resize, and turn on or off during a recording
- **Draw on screen:** annotate live with six colours, undo and clear
- **Floating controls:** a compact bubble with a timer, pause, stop and quick actions (mic, facecam, draw). It docks to either screen edge and always opens toward the centre.
- **Automatic stop:** after a time limit, when you shake the phone, or when the screen locks
- **Start from anywhere:** the in-app record button, a Quick Settings tile or launcher shortcuts (long-press the app icon). Pause and stop are also available in the notification.

### Library and editor
- Recordings are saved to **Movies › Reelmint** and appear in Gallery, Google Photos and file managers. Deleting or renaming in Reelmint updates them there too.
- Library grouped by date, with search, sort, favourites, multi-select and a storage overview that shows the save location
- Player with scrubbing, double-tap to seek, variable playback speed (0.25×–2×) and file details
- **Instant (lossless):** trim, rotate, remove audio, extract audio (.m4a to Music › Reelmint)
- **Exports:** compress to 1080p, 720p or 480p, change speed (0.5×–4×), and merge clips. Exports show progress and can be cancelled. Compression always keeps the smaller file.
- Save any frame as a full-resolution photo (Pictures › Reelmint)
- A "Recording saved" notification with a preview and Share and Delete actions

### Experience
- **App lock** with fingerprint, face or screen lock
- Six accent themes; dark, light or system appearance; haptic feedback
- Runs at the display's highest refresh rate (for example, 120 Hz)
- Insights (number of recordings, total and longest duration) and an estimate of file size per minute for your current settings

## Getting started

### Requirements
- [Flutter](https://docs.flutter.dev/get-started/install) 3.x (stable channel) with the Android toolchain
- An Android device with [USB debugging](https://developer.android.com/studio/debug/dev-options) enabled, running Android 10 or newer

### Run
```sh
flutter pub get
flutter run                 # debug build on a connected device
```

### Build
```sh
flutter build apk --release          # single universal APK
flutter build apk --split-per-abi    # smaller APK per CPU architecture
flutter build appbundle              # Android App Bundle for Google Play
```

To sign release builds with your own key, copy `android/key.properties.example` to
`android/key.properties` and fill in your keystore details. Without that file, release
builds use the debug key, which is fine for local testing
([Android signing guide](https://developer.android.com/studio/publish/app-signing)).

## Testing

Reelmint has a fast test suite that runs on any computer and an on-device suite that
exercises the real recording engine.

```sh
flutter test                                       # unit and widget tests (no device needed)
dart run tool/device_test.dart                     # everything, including on-device suites
dart run tool/device_test.dart --skip-host --only=features_test
```

See [docs/TESTING.md](docs/TESTING.md) for what each suite covers and how the device
runner works.

## Project structure

```
lib/
  app/          theme, accents and service scope
  services/     recorder bridge, settings, library
  ui/screens/   home, library, player, trim, settings, onboarding, lock, shell
  ui/widgets/   shared widgets, record button, editor tools, permission gates
android/app/src/main/kotlin/io/github/mohdaffankhan/reelmint/
  RecorderService, ScreenEncoder     foreground service and capture pipeline
  FloatingControls, FacecamOverlay,  overlays shown above other apps
  DrawOverlay
  Editor, MediaTools                 Media3 exports, lossless edits, thumbnails
  Storage                            save location and media index sync
  CaptureActivity, RecordTileService start flows for shortcuts and the Quick Settings tile
integration_test/                    on-device suites
test/                                unit and widget tests
tool/device_test.dart                device test runner
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit together.

## Privacy

Reelmint works entirely offline and collects nothing. See [PRIVACY.md](PRIVACY.md) for the
permissions it uses and why.

## Known limitations

- Some apps (for example DRM-protected video players and calls) block device-audio capture. Android enforces this, and the recording continues with whatever audio those apps allow.
- The facecam, floating controls and drawings appear in the recording, because they are drawn on screen.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening
a pull request.

## License

Reelmint is released under the [MIT License](LICENSE). Copyright © 2026 Affan.
