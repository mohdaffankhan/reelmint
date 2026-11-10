import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/recorder.dart';

import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late Recorder r;

  setUp(() async {
    native = FakeNative()..install();
    r = Recorder();
    await r.init();
    await pumpEventQueue();
  });

  tearDown(() {
    r.dispose();
    native.uninstall();
  });

  Future<void> flush() => pumpEventQueue();

  test('init loads capabilities and recordings dir', () {
    expect(r.caps.sdk, 34);
    expect(r.caps.quickTile, isTrue);
    expect(r.caps.hasCamera, isTrue);
    expect(r.caps.internalAudio, isTrue);
    expect(r.caps.pause, isTrue);
    expect(r.caps.floatingControls, isTrue);
    expect(r.caps.maxFps, 120);
    expect(r.recordingsDir, native.dir.path);
    expect(r.state, RecState.idle);
  });

  test('state events drive state, countdown and elapsed time', () async {
    native.emitState('countdown', countdown: 3);
    await flush();
    expect(r.state, RecState.countdown);
    expect(r.countdown, 3);
    expect(r.isActive, isTrue);
    expect(r.isRecording, isFalse);

    native.emitState('recording', elapsedMs: 1500);
    await flush();
    expect(r.state, RecState.recording);
    expect(r.isRecording, isTrue);
    expect(r.elapsed.inMilliseconds, greaterThanOrEqualTo(1500));

    native.emitState('paused', elapsedMs: 4000);
    await flush();
    expect(r.state, RecState.paused);
    final frozen = r.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(r.elapsed, frozen, reason: 'timer must freeze while paused');
    expect(frozen, const Duration(milliseconds: 4000));

    native.emitState('stopping', elapsedMs: 4000);
    await flush();
    expect(r.state, RecState.stopping);

    native.emitState('idle');
    await flush();
    expect(r.state, RecState.idle);
    expect(r.isActive, isFalse);
    expect(r.elapsed, Duration.zero);
  });

  test('elapsed ticks forward while recording', () async {
    native.emitState('recording', elapsedMs: 0);
    await flush();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(r.elapsed.inMilliseconds, greaterThanOrEqualTo(200));
  });

  test('saved / error / warning / open events are forwarded', () async {
    final got = <RecorderEvent>[];
    final sub = r.events.listen(got.add);
    native.emit({'type': 'saved', 'path': '/x/a.mp4', 'durationMs': 4200});
    native.emit({'type': 'error', 'message': 'boom'});
    native.emit({'type': 'warning', 'message': 'heads up'});
    native.emit({'type': 'open', 'path': '/x/b.mp4'});
    await flush();
    await sub.cancel();

    expect(got, hasLength(4));
    final saved = got[0] as RecordingSaved;
    expect(saved.path, '/x/a.mp4');
    expect(saved.duration, const Duration(milliseconds: 4200));
    expect((got[1] as RecorderMessage).isError, isTrue);
    expect((got[1] as RecorderMessage).message, 'boom');
    expect((got[2] as RecorderMessage).isError, isFalse);
    expect((got[3] as OpenRecording).path, '/x/b.mp4');
  });

  test('mic mute event updates state and resets on idle', () async {
    native.emitState('recording');
    native.emit({'type': 'mic', 'muted': true});
    await flush();
    expect(r.micMuted, isTrue);
    native.emitState('idle');
    await flush();
    expect(r.micMuted, isFalse);
  });

  test('control methods reach the native side', () async {
    final opts = <String, Object>{
      'resolution': 720,
      'fps': 30,
      'audio': 'none',
    };
    expect(await r.start(opts), isTrue);
    expect(native.callsTo('start').single.arguments, opts);
    await r.pause();
    await r.resume();
    await r.toggleMic();
    await r.stop();
    await r.moveToBackground();
    for (final m in [
      'pause',
      'resume',
      'toggleMic',
      'stop',
      'moveToBackground',
    ]) {
      expect(native.callsTo(m), hasLength(1), reason: m);
    }
  });

  test('start returning false (user dismissed capture prompt)', () async {
    native.startResult = false;
    expect(await r.start(const {}), isFalse);
  });

  test('start PlatformException becomes an error event', () async {
    native.overrides['start'] = (_) => throw PlatformException(
      code: 'busy',
      message: 'A recording is already in progress',
    );
    final first = r.events.first;
    expect(await r.start(const {}), isFalse);
    final e =
        await first.timeout(const Duration(seconds: 1)) as RecorderMessage;
    expect(e.isError, isTrue);
    expect(e.message, contains('already in progress'));
  });

  test('permission methods', () async {
    native.micGranted = true;
    expect(await r.micPermission(), isTrue);
    expect(await r.requestMicPermission(), isTrue);
    expect(await r.overlayPermission(), isFalse);
    await r.requestOverlayPermission();
    expect(native.callsTo('requestOverlayPermission'), hasLength(1));
    expect(await r.notificationPermission(), isFalse);
    await r.requestNotificationPermission();
    expect(native.callsTo('requestNotificationPermission'), hasLength(1));
  });

  test('media tools pass arguments and parse results', () async {
    final info = await r.info('/v.mp4');
    expect(info.duration, const Duration(seconds: 5));
    expect(info.width, 720);
    expect(info.height, 1600);
    expect(info.bitrate, 4000000);
    expect(info.hasAudio, isTrue);
    expect(info.frameCount, 150);

    await r.thumbnail('/v.mp4', atMs: 1200, maxWidth: 200);
    expect(native.callsTo('thumbnail').single.arguments, {
      'path': '/v.mp4',
      'atMs': 1200,
      'maxWidth': 200,
    });

    final out = await r.trim(
      '/v.mp4',
      const Duration(seconds: 1),
      const Duration(milliseconds: 3500),
    );
    expect(out, endsWith('trimmed.mp4'));
    expect(native.callsTo('trim').single.arguments, {
      'path': '/v.mp4',
      'startMs': 1000,
      'endMs': 3500,
    });

    await r.scan(['/v.mp4']);
    expect(native.callsTo('scan').single.arguments, {
      'paths': ['/v.mp4'],
    });
  });

  test('missing native info returns MediaInfo.empty', () async {
    native.overrides['info'] = (_) => null;
    final i = await r.info('/nope.mp4');
    expect(i.duration, Duration.zero);
    expect(i.width, 0);
  });

  test('notifies listeners on state change', () async {
    final c = Completer<void>();
    r.addListener(() {
      if (!c.isCompleted) c.complete();
    });
    native.emitState('recording');
    await c.future.timeout(const Duration(seconds: 1));
  });
}
