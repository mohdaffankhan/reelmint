# Contributing to Reelmint

Thank you for your interest in improving Reelmint. This guide explains how to set up the
project, the standards we follow, and how to submit changes.

## Ways to contribute

- **Report a bug.** Include your device model, Android version, Reelmint version (Settings, at the bottom), steps to reproduce, and what you expected to happen.
- **Suggest a feature.** Describe the problem it solves and how you would use it.
- **Submit a pull request.** For anything larger than a small fix, please open an issue first so we can agree on the approach.

## Development setup

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable channel) and the Android SDK.
2. Clone the repository and fetch dependencies:
   ```sh
   flutter pub get
   ```
3. Connect an Android 10+ device with USB debugging enabled and run:
   ```sh
   flutter run
   ```

The UI is written in Dart (`lib/`). Recording, overlays and media processing are native
Kotlin (`android/app/src/main/kotlin/io/github/mohdaffankhan/reelmint/`). The two sides communicate over
the `reelmint/recorder` method channel and the `reelmint/events` event channel. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Code standards

- Run `dart format .` and make sure `flutter analyze` reports no errors or warnings.
- Keep the UI responsive: avoid full-screen blurs, large gradients and per-item opacity layers in scrolling content. `integration_test/perf_test.dart` measures frame times on a real device.
- Keep Reelmint private: do not add network access, analytics or third-party SDKs that collect data.
- Prefer small, focused pull requests with a clear description of what changed and why.

## Tests

Every change should keep the test suites passing, and new behaviour should come with tests.

```sh
flutter test                      # unit and widget tests
dart run tool/device_test.dart    # full suite, including on-device tests
```

- UI and Dart logic: add widget or unit tests under `test/`. `test/helpers/fake_native.dart` simulates the native side.
- Native behaviour (recording, overlays, media tools): add an on-device test under `integration_test/`.

See [docs/TESTING.md](docs/TESTING.md) for details.

## Commit messages

Use the imperative mood and a short summary line, for example
`Add 1.25x playback speed` or `Keep floating controls within screen bounds`.
Explain the reasoning in the body if it is not obvious from the diff.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
