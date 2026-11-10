# Architecture

Reelmint is a Flutter app with a native Kotlin core. Flutter renders the interface, and
Kotlin handles everything that needs Android system APIs: screen capture, audio,
encoding, overlays and media processing.

```
┌──────────────────────── Flutter (lib/) ────────────────────────┐
│ ui/screens  ──►  services/recorder.dart  ◄──  services/library │
│                       │  MethodChannel "reelmint/recorder"        │
│                       │  EventChannel  "reelmint/events"          │
└───────────────────────┼────────────────────────────────────────┘
┌───────────────────────▼─────── Kotlin (android/…/reelmint/) ──────┐
│ MainActivity ──► RecorderService ──► ScreenEncoder             │
│      │                │  ├─ FloatingControls / FacecamOverlay  │
│      │                │  └─ DrawOverlay                        │
│      ├─► Editor (Media3 Transformer)   MediaTools              │
│      └─► Storage                       RecorderBus (events)    │
└────────────────────────────────────────────────────────────────┘
```

## Recording pipeline

1. `MainActivity` (or `CaptureActivity` for the tile and shortcuts) requests the screen-capture consent and any needed permissions, then starts `RecorderService` with the recording options.
2. `RecorderService` runs as a foreground service (types `mediaProjection`, `microphone` and `camera`). It handles the countdown, notifications, overlays and automatic stop conditions (time limit, shake, screen off).
3. `ScreenEncoder` mirrors the display into a `VirtualDisplay` backed by a hardware H.264 encoder surface. Audio comes from `AudioRecord`: the microphone, device playback capture, or both mixed into one AAC track. `MediaMuxer` writes the MP4. Pausing shifts timestamps, so resumed recordings have no gap.
4. When the recording finishes, the file is registered with the media library and a `saved` event is sent to Flutter.

## Events

`RecorderBus` is the single source of truth for recording state (idle, countdown,
recording, paused, stopping) and overlay state (mic muted, facecam, drawing). It forwards
events to Flutter, the floating controls, the notification and the Quick Settings tile,
so every surface stays in sync.

## Storage

`Storage` stores recordings in the public `Movies/Reelmint` folder through the regular file
API, which Android 11+ allows for an app's own media files. Android 10 uses legacy storage
with `WRITE_EXTERNAL_STORAGE`. If neither is available, Reelmint falls back to its private
folder. After every create, edit, rename or delete, `MediaScannerConnection` updates the
media index, so Gallery reflects the change immediately.

## Editing

- **Lossless** operations (trim, rotate, remove audio, extract audio) remux samples with `MediaExtractor` and `MediaMuxer`, without re-encoding.
- **Exports** (compress, speed, merge) use Media3 Transformer. Progress is polled and sent as `progress` events, and jobs can be cancelled, which removes any partial output. Compression caps the target bitrate at the source's own rate and keeps the original if the result would not be smaller.

## Settings shared with native code

Settings are stored with `shared_preferences`. Entry points outside the Flutter UI (the
Quick Settings tile and launcher shortcuts) read the same values natively through
`ReelmintPrefs`, so every way of starting a recording uses the same configuration.

## Rendering

The interface is tuned for high-refresh-rate displays. `MainActivity` requests the
panel's fastest display mode. The UI avoids backdrop blurs, full-screen gradients and
per-item opacity layers, and gives continuously animating widgets (such as the record
button) their own repaint boundary.
