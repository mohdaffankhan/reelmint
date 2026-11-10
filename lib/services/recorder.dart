import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RecState { idle, countdown, recording, paused, stopping }

sealed class RecorderEvent {}

class RecordingSaved extends RecorderEvent {
  RecordingSaved(this.path, this.duration);
  final String path;
  final Duration duration;
}

class RecorderMessage extends RecorderEvent {
  RecorderMessage(this.message, {this.isError = false});
  final String message;
  final bool isError;
}

class OpenRecording extends RecorderEvent {
  OpenRecording(this.path);
  final String path;
}

/// A recording was deleted outside the app (e.g. from the saved notification).
class RecordingDeleted extends RecorderEvent {
  RecordingDeleted(this.path);
  final String path;
}

/// A launcher shortcut asked for a tab ("library").
class OpenTab extends RecorderEvent {
  OpenTab(this.tab);
  final String tab;
}

class Capabilities {
  const Capabilities({
    required this.sdk,
    required this.internalAudio,
    required this.pause,
    required this.floatingControls,
    required this.maxFps,
    required this.quickTile,
    required this.hasCamera,
  });

  final int sdk, maxFps;
  final bool internalAudio, pause, floatingControls, quickTile, hasCamera;

  factory Capabilities.fromMap(Map m) => Capabilities(
    sdk: (m['sdk'] as num?)?.toInt() ?? 0,
    internalAudio: m['internalAudio'] as bool? ?? false,
    pause: m['pause'] as bool? ?? false,
    floatingControls: m['floatingControls'] as bool? ?? false,
    maxFps: (m['maxFps'] as num?)?.toInt() ?? 60,
    quickTile: m['quickTile'] as bool? ?? false,
    hasCamera: m['hasCamera'] as bool? ?? false,
  );

  static const fallback = Capabilities(
    sdk: 0,
    internalAudio: false,
    pause: false,
    floatingControls: false,
    maxFps: 60,
    quickTile: false,
    hasCamera: false,
  );
}

class MediaInfo {
  const MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.hasAudio,
    this.frameCount = 0,
  });
  final Duration duration;
  final int width, height, bitrate, frameCount;
  final bool hasAudio;

  factory MediaInfo.fromMap(Map m) => MediaInfo(
    duration: Duration(milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
    width: (m['width'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    bitrate: (m['bitrate'] as num?)?.toInt() ?? 0,
    hasAudio: m['hasAudio'] as bool? ?? false,
    frameCount: (m['frameCount'] as num?)?.toInt() ?? 0,
  );

  static const empty = MediaInfo(
    duration: Duration.zero,
    width: 0,
    height: 0,
    bitrate: 0,
    hasAudio: false,
  );
}

class StorageInfo {
  const StorageInfo(this.free, this.total);
  final int free, total;
  double get usedFraction => total == 0 ? 0 : 1 - free / total;
}

/// Re-encode options for [Recorder.transform].
class TransformSpec {
  const TransformSpec({
    this.shortSide = 0,
    this.bitrate = 0,
    this.speed = 1,
    this.removeAudio = false,
  });
  final int shortSide, bitrate;
  final double speed;
  final bool removeAudio;
}

/// Dart façade over the native Android recorder (MediaProjection + MediaCodec).
class Recorder extends ChangeNotifier {
  static const _m = MethodChannel('reelmint/recorder');
  static const _e = EventChannel('reelmint/events');

  RecState state = RecState.idle;
  int countdown = 0;
  bool micMuted = false;
  bool facecamOn = false;
  bool drawOn = false;
  Capabilities caps = Capabilities.fallback;
  String? recordingsDir;

  /// Live progress (0–100) of running editor jobs, by job id.
  final jobProgress = <String, int>{};

  Duration _elapsedBase = Duration.zero;
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription? _sub;
  final _events = StreamController<RecorderEvent>.broadcast();

  Stream<RecorderEvent> get events => _events.stream;
  bool get isActive => state != RecState.idle;
  bool get isRecording =>
      state == RecState.recording || state == RecState.paused;

  Duration get elapsed =>
      _elapsedBase +
      (state == RecState.recording ? _stopwatch.elapsed : Duration.zero);

  Future<void> init() async {
    try {
      caps = Capabilities.fromMap(
        await _m.invokeMethod('getCapabilities') as Map,
      );
      recordingsDir = await _m.invokeMethod<String>('getRecordingsDir');
    } on MissingPluginException {
      recordingsDir = null;
    }
    _sub = _e.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  Future<String?> consumeLaunchRecording() =>
      _safe(() => _m.invokeMethod<String>('consumeLaunchRecording'));
  Future<String?> consumeLaunchTab() =>
      _safe(() => _m.invokeMethod<String>('consumeLaunchTab'));

  Future<T?> _safe<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  void _readOverlays(Map<String, dynamic> e) {
    micMuted = e['micMuted'] as bool? ?? micMuted;
    facecamOn = e['facecam'] as bool? ?? facecamOn;
    drawOn = e['draw'] as bool? ?? drawOn;
  }

  void _onEvent(dynamic raw) {
    final e = Map<String, dynamic>.from(raw as Map);
    switch (e['type']) {
      case 'state':
        final next = RecState.values.byName(e['state'] as String);
        countdown = (e['countdown'] as num?)?.toInt() ?? 0;
        _elapsedBase = Duration(
          milliseconds: (e['elapsedMs'] as num?)?.toInt() ?? 0,
        );
        _stopwatch
          ..reset()
          ..start();
        _readOverlays(e);
        if (next == RecState.idle) micMuted = facecamOn = drawOn = false;
        state = next;
        _syncTicker();
        notifyListeners();
      case 'overlays':
        _readOverlays(e);
        notifyListeners();
      case 'saved':
        _events.add(
          RecordingSaved(
            e['path'] as String,
            Duration(milliseconds: (e['durationMs'] as num?)?.toInt() ?? 0),
          ),
        );
      case 'error':
        _events.add(
          RecorderMessage(
            e['message'] as String? ?? 'Something went wrong',
            isError: true,
          ),
        );
      case 'warning':
        _events.add(RecorderMessage(e['message'] as String? ?? ''));
      case 'mic':
        micMuted = e['muted'] as bool? ?? false;
        notifyListeners();
      case 'open':
        _events.add(OpenRecording(e['path'] as String));
      case 'deleted':
        _events.add(RecordingDeleted(e['path'] as String));
      case 'tab':
        _events.add(OpenTab(e['tab'] as String));
      case 'progress':
        jobProgress[e['job'] as String] = (e['progress'] as num?)?.toInt() ?? 0;
        notifyListeners();
    }
  }

  void _syncTicker() {
    if (state == RecState.recording) {
      _ticker ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => notifyListeners(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Returns false if the user dismissed the system capture prompt.
  Future<bool> start(Map<String, Object> options) async {
    try {
      return await _m.invokeMethod<bool>('start', options) ?? false;
    } on PlatformException catch (e) {
      _events.add(
        RecorderMessage(
          e.message ?? 'Could not start recording',
          isError: true,
        ),
      );
      return false;
    }
  }

  Future<void> pause() => _m.invokeMethod('pause');
  Future<void> resume() => _m.invokeMethod('resume');
  Future<void> stop() => _m.invokeMethod('stop');
  Future<void> toggleMic() => _m.invokeMethod('toggleMic');
  Future<void> toggleFacecam() => _m.invokeMethod('toggleFacecam');
  Future<void> toggleDraw() => _m.invokeMethod('toggleDraw');
  Future<void> moveToBackground() => _m.invokeMethod('moveToBackground');

  // ---- permissions
  Future<bool> micPermission() async =>
      await _m.invokeMethod<bool>('micPermission') ?? false;
  Future<bool> requestMicPermission() async =>
      await _m.invokeMethod<bool>('requestMicPermission') ?? false;
  Future<bool> cameraPermission() async =>
      await _m.invokeMethod<bool>('cameraPermission') ?? false;
  Future<bool> requestCameraPermission() async =>
      await _m.invokeMethod<bool>('requestCameraPermission') ?? false;
  Future<bool> overlayPermission() async =>
      await _m.invokeMethod<bool>('overlayPermission') ?? false;
  Future<void> requestOverlayPermission() =>
      _m.invokeMethod('requestOverlayPermission');
  Future<bool> notificationPermission() async =>
      await _m.invokeMethod<bool>('notificationPermission') ?? true;
  Future<void> requestNotificationPermission() =>
      _m.invokeMethod('requestNotificationPermission');

  // ---- security & system
  Future<bool> canAuthenticate() async =>
      await _m.invokeMethod<bool>('canAuthenticate') ?? false;
  Future<bool> authenticate([
    String reason = 'Unlock to see your recordings',
  ]) async =>
      await _m.invokeMethod<bool>('authenticate', {'reason': reason}) ?? false;

  /// Android 13+: asks the system to add the Reelmint tile. Returns the system result code,
  /// or -1 when unsupported (user must add it manually).
  Future<int> requestAddTile() async =>
      await _m.invokeMethod<int>('requestAddTile') ?? -1;

  Future<StorageInfo> storage() async {
    final m = await _m.invokeMethod<Map>('storage');
    return StorageInfo(
      (m?['free'] as num?)?.toInt() ?? 0,
      (m?['total'] as num?)?.toInt() ?? 0,
    );
  }

  // ---- media tools
  Future<Uint8List?> thumbnail(
    String path, {
    int atMs = 0,
    int maxWidth = 360,
  }) => _m.invokeMethod<Uint8List>('thumbnail', {
    'path': path,
    'atMs': atMs,
    'maxWidth': maxWidth,
  });

  Future<MediaInfo> info(String path) async {
    final m = await _m.invokeMethod<Map>('info', {'path': path});
    return m == null ? MediaInfo.empty : MediaInfo.fromMap(m);
  }

  Future<String> trim(String path, Duration start, Duration end) async =>
      (await _m.invokeMethod<String>('trim', {
        'path': path,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
      }))!;

  /// Lossless: rotates the display orientation by [degrees] (90/180/270).
  Future<String> rotate(String path, int degrees) async => (await _m
      .invokeMethod<String>('rotate', {'path': path, 'degrees': degrees}))!;

  /// Lossless copy without the audio track.
  Future<String> removeAudio(String path) async =>
      (await _m.invokeMethod<String>('removeAudio', {'path': path}))!;

  /// Lossless .m4a of the soundtrack, also saved to Music/Reelmint. Returns the local file path.
  Future<String> extractAudio(String path) async {
    final m = await _m.invokeMethod<Map>('extractAudio', {'path': path});
    return m!['path'] as String;
  }

  /// Saves the frame at [at] as a full-resolution photo in Pictures/Reelmint. Returns its URI.
  Future<String> saveFrame(String path, Duration at) async =>
      (await _m.invokeMethod<String>('saveFrame', {
        'path': path,
        'atMs': at.inMilliseconds,
      }))!;

  /// Re-encodes (compress / speed) one clip, or merges several clips in order.
  /// Progress arrives in [jobProgress] under [id].
  Future<String> transform(
    List<String> paths,
    TransformSpec spec, {
    required String id,
  }) async {
    jobProgress[id] = 0;
    try {
      return (await _m.invokeMethod<String>('transform', {
        'id': id,
        'paths': paths,
        'shortSide': spec.shortSide,
        'bitrate': spec.bitrate,
        'speed': spec.speed,
        'removeAudio': spec.removeAudio,
      }))!;
    } finally {
      jobProgress.remove(id);
    }
  }

  Future<bool> cancelJob(String id) async =>
      await _m.invokeMethod<bool>('cancelJob', {'id': id}) ?? false;

  /// Returns the gallery URI.
  /// Tells Android's media index that these files were created, changed or deleted.
  Future<void> scan(List<String> paths) async {
    try {
      await _m.invokeMethod('scan', {'paths': paths});
    } catch (_) {}
  }

  /// Whether a file with [name] exists in the shared gallery (Movies/Reelmint).
  Future<bool> galleryHas(String name) async =>
      await _m.invokeMethod<bool>('galleryHas', {'name': name}) ?? false;

  /// Removes Reelmint's own gallery copy named [name].
  Future<int> galleryDelete(String name) async =>
      await _m.invokeMethod<int>('galleryDelete', {'name': name}) ?? 0;

  /// Removes one of Reelmint's shared files ([kind]: image | audio | video).
  Future<int> deleteShared(String kind, String name) async =>
      await _m.invokeMethod<int>('deleteShared', {
        'kind': kind,
        'name': name,
      }) ??
      0;

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _events.close();
    super.dispose();
  }
}
