# Testing

Reelmint has two layers of tests:

- **Unit and widget tests** (`test/`) run on any computer. The native side is replaced by a fake (`test/helpers/fake_native.dart`), so every screen and flow can be tested quickly.
- **On-device tests** (`integration_test/`) run on a real Android phone and exercise the actual recording engine, overlays, media tools and system integrations.

## Running the tests

```sh
flutter test                                        # unit and widget tests
dart run tool/device_test.dart                      # unit/widget tests, then all device suites
dart run tool/device_test.dart --skip-host          # device suites only
dart run tool/device_test.dart --only=app_flow_test # a single device suite
dart run tool/device_test.dart --device=<serial>    # choose a device when several are connected
```

Keep the phone unlocked and connected over USB while the device suites run.

## Device suites

| Suite | Covers |
|---|---|
| `recorder_engine_test` | Real recordings in every audio mode; pause and resume; countdown and cancel; resolutions, orientation, frame-rate and bitrate limits; thumbnails; trim; saving to Movies/Reelmint and Gallery sync |
| `features_test` | Facecam; drawing overlay; floating controls driven by real touch input (edge docking, staying within the screen, dragging from buttons without activating them); automatic stop; editor tools (rotate, remove and extract audio, save frame, compress, speed, merge, cancel); storage; Quick Settings tile; launcher shortcut |
| `app_flow_test` | A complete user journey through the UI: record, pause, resume, watch, playback speed, details, favourite, trim, rename, check the Gallery, delete (removed from Recent, Library and Gallery) |
| `perf_test` | Runs as a profile build. Checks that the app uses the display's top refresh rate, and measures frame times while scrolling Home, Library and Settings against the frame budget. |
| `screen_off_test` | Recording stops and saves when the screen locks |

## How the device runner works

`tool/device_test.dart` automates the steps that would otherwise need a person:

- It grants runtime permissions and pre-approves screen capture with `adb`, so no consent dialogs appear.
- It watches each suite's output for markers and performs actions with `adb`:

  | Marker | Action |
  |---|---|
  | `REELMINT_SCREEN_OFF_READY` | Turns the screen off, then wakes it |
  | `REELMINT_START_CAPTURE_ACTIVITY` | Launches the "Record" shortcut activity |
  | `REELMINT_TILE_CLICK` | Adds and clicks the Quick Settings tile |
  | `REELMINT_INPUT tap x y` / `REELMINT_INPUT swipe x1 y1 x2 y2 ms` | Injects real touch events |

- At the end it prints a pass or fail summary for every suite.

## Writing tests

- Prefer widget tests for UI behaviour. Use `pumpReelmint` and the `FakeNative` flags (permissions, start result, authentication and so on) to set up scenarios.
- Use a device test when the behaviour depends on Android itself (encoding, overlays, the media library, system UI).
- Clean up any files a device test creates, including when it fails (`addTearDown`).
