import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/app/scope.dart';
import 'package:reelmint/main.dart';
import 'package:reelmint/services/library.dart';
import 'package:reelmint/services/recorder.dart';
import 'package:reelmint/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the Android side of `reelmint/recorder` + `reelmint/events`.
class FakeNative {
  FakeNative({Directory? dir})
    : dir = dir ?? Directory.systemTemp.createTempSync('reelmint_test_');

  final Directory dir;
  final calls = <MethodCall>[];
  final overrides = <String, Object? Function(MethodCall)>{};
  final infos = <String, Map<String, Object>>{};
  MockStreamHandlerEventSink? _sink;

  bool micGranted = false;
  bool overlayGranted = false;
  bool notifyGranted = false;
  bool cameraGranted = false;
  bool startResult = true;
  bool canAuth = true;
  bool authResult = true;
  int addTileResult = 1;

  static const _methods = MethodChannel('reelmint/recorder');
  static const _events = EventChannel('reelmint/events');

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      final o = overrides[call.method];
      if (o != null) return o(call);
      return _default(call);
    });
    m.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          _sink = sink;
        },
      ),
    );
  }

  void uninstall() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_methods, null);
    m.setMockStreamHandler(_events, null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  Object? _default(MethodCall call) {
    final args = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'getCapabilities':
        return {
          'platform': 'android',
          'sdk': 34,
          'internalAudio': true,
          'pause': true,
          'floatingControls': true,
          'quickTile': true,
          'hasCamera': true,
          'maxFps': 120,
        };
      case 'getRecordingsDir':
        return dir.path;
      case 'getState':
        return {
          'type': 'state',
          'state': 'idle',
          'elapsedMs': 0,
          'countdown': 0,
        };
      case 'start':
        return startResult;
      case 'micPermission':
      case 'requestMicPermission':
        return micGranted;
      case 'overlayPermission':
        return overlayGranted;
      case 'cameraPermission':
      case 'requestCameraPermission':
        return cameraGranted;
      case 'canAuthenticate':
        return canAuth;
      case 'authenticate':
        return authResult;
      case 'requestAddTile':
        return addTileResult;
      case 'storage':
        return {
          'free': 20 * 1024 * 1024 * 1024,
          'total': 128 * 1024 * 1024 * 1024,
        };
      case 'rotate':
        return '${dir.path}/rotated.mp4';
      case 'removeAudio':
        return '${dir.path}/silent.mp4';
      case 'extractAudio':
        return {
          'path': '${dir.path}/audio.m4a',
          'uri': 'content://media/external/audio/media/1',
        };
      case 'saveFrame':
        return 'content://media/external/images/media/1';
      case 'transform':
        return '${dir.path}/${(args['paths'] as List).length > 1 ? 'merged' : 'export'}.mp4';
      case 'cancelJob':
        return true;
      case 'getOverlays':
        return {
          'type': 'overlays',
          'micMuted': false,
          'facecam': false,
          'draw': false,
        };
      case 'notificationPermission':
        return notifyGranted;
      case 'info':
        return infos[args['path']] ??
            {
              'durationMs': 5000,
              'width': 720,
              'height': 1600,
              'bitrate': 4000000,
              'hasAudio': true,
              'frameCount': 150,
            };
      case 'thumbnail':
        return null;
      case 'trim':
        return '${dir.path}/trimmed.mp4';
      case 'scan':
        return true;
      default:
        return null;
    }
  }

  void emit(Map<String, Object?> event) => _sink!.success(event);

  void emitState(String state, {int elapsedMs = 0, int countdown = 0}) => emit({
    'type': 'state',
    'state': state,
    'elapsedMs': elapsedMs,
    'countdown': countdown,
  });

  List<MethodCall> callsTo(String method) =>
      calls.where((c) => c.method == method).toList();

  /// Creates a fake recording file (> 1 KB so the library accepts it).
  File addRecording(
    String name, {
    int bytes = 4096,
    DateTime? modified,
    int durationMs = 5000,
  }) {
    final f = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(List.filled(bytes, 7));
    if (modified != null) f.setLastModifiedSync(modified);
    infos[f.path] = {
      'durationMs': durationMs,
      'width': 1080,
      'height': 2400,
      'bitrate': 8000000,
      'hasAudio': true,
      'frameCount': 300,
    };
    return f;
  }
}

class Harness {
  Harness(this.native, this.settings, this.recorder, this.library);
  final FakeNative native;
  final Settings settings;
  final Recorder recorder;
  final Library library;
}

/// Default prefs for widget tests: onboarding done, deterministic behaviour.
const testPrefs = <String, Object>{'onboarded': true, 'haptics': false};

/// Boots the full app against [FakeNative]. IO runs in `runAsync`.
Future<Harness> pumpReelmint(
  WidgetTester tester, {
  Map<String, Object> prefs = testPrefs,
  void Function(FakeNative n)? arrange,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final native = FakeNative();
  arrange?.call(native);
  native.install();
  addTearDown(native.uninstall);
  SharedPreferences.setMockInitialValues(prefs);

  late Harness h;
  await tester.runAsync(() async {
    final settings = await Settings.load();
    final recorder = Recorder();
    await recorder.init();
    Thumbs.instance.recorder = recorder;
    final library = Library(recorder, settings);
    await library.refresh();
    h = Harness(native, settings, recorder, library);
  });
  await tester.pumpWidget(
    AppScope(
      recorder: h.recorder,
      settings: h.settings,
      library: h.library,
      child: const ReelmintApp(),
    ),
  );
  await settle(tester);
  return h;
}

/// Like pumpAndSettle, but tolerates the app's endless ambient animations.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs real async work (file IO, event delivery), interleaving real time with
/// fake-time pumps so work hopping between the two zones can finish.
Future<void> real(
  WidgetTester tester, [
  Future<void> Function()? body,
  int rounds = 12,
]) async {
  if (body != null) await tester.runAsync(body);
  await pumpReal(tester, rounds);
}

Future<void> pumpReal(WidgetTester tester, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}
