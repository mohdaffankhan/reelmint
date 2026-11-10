# Privacy

Reelmint is designed to keep your recordings on your device.

- **No data collection.** Reelmint has no analytics, crash reporting, advertising or accounts.
- **No internet access.** The release build does not request Android's `INTERNET` permission, so it cannot send data off the device. (Media3, the video library Reelmint uses, requests `ACCESS_NETWORK_STATE`, which only lets it read whether the device is connected.)
- **Your files stay where you put them.** Recordings are saved to `Movies/Reelmint` on your device. Nothing is uploaded. Sharing happens only when you choose Share, through Android's share sheet.

## Permissions

| Permission | Why Reelmint needs it | When it is requested |
|---|---|---|
| Screen capture (MediaProjection) | To record the screen | Each time a recording starts (an Android system prompt) |
| Microphone (`RECORD_AUDIO`) | To record your voice and device audio | During onboarding, or when you choose an audio source that needs it |
| Notifications (`POST_NOTIFICATIONS`) | To show recording controls and the "Recording saved" notification | During onboarding |
| Display over other apps (`SYSTEM_ALERT_WINDOW`) | For the floating controls, facecam and drawing overlay | During onboarding (optional), or when you turn on one of those features |
| Camera (`CAMERA`) | For the facecam | During onboarding (optional), or when you turn on the facecam |
| Biometrics (`USE_BIOMETRIC`) | For the optional app lock | When you turn on the app lock |
| Storage (`WRITE_EXTERNAL_STORAGE`, Android 10 only) | To save recordings to `Movies/Reelmint` | When recording with audio for the first time on Android 10 |
| Foreground service types | Required by Android to keep recording while Reelmint is in the background | Not shown to the user |

All permissions are optional except screen capture. Features that need a permission you
have not granted are simply unavailable until you allow it.

## Contact

Please report privacy concerns by opening an issue in the project repository.
