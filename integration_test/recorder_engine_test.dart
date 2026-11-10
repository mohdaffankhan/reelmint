// On-device tests for the native Android recording engine.
// Run with tool/run_device_tests.ps1 (grants permissions + capture consent first).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelmint/services/library.dart';
import 'package:reelmint/services/recorder.dart';
import 'package:reelmint/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final rec = Recorder();
  final created = <String>[];
  late int deviceShort, deviceLong;

  setUpAll(() async {
    await rec.init();
    Thumbs.instance.recorder = rec;
  });

  tearDownAll(() async {
    for (final p in created) {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
  });

  setUp(() async {
    final size = binding.platformDispatcher.views.first.physicalSize;
    deviceShort = math.min(size.width, size.height).round();
    deviceLong = math.max(size.width, size.height).round();
  });

  Future<void> busy(WidgetTester t) async {
    await t.pumpWidget(const Busy());
    await t.pump();
  }

  // ------------------------------------------------------------------ platform

  testWidgets('capabilities report Android features', (t) async {
    expect(rec.caps.sdk, greaterThanOrEqualTo(29));
    expect(
      rec.caps.internalAudio,
      isTrue,
      reason: 'Android 10+ supports device-audio capture',
    );
    expect(rec.caps.pause, isTrue);
    expect(rec.caps.floatingControls, isTrue);
    expect(rec.caps.maxFps, greaterThanOrEqualTo(60));
    expect(rec.recordingsDir, isNotNull);
    expect(Directory(rec.recordingsDir!).existsSync(), isTrue);
  });

  testWidgets('permissions are granted (mic, notifications, overlay)', (
    t,
  ) async {
    expect(await rec.micPermission(), isTrue, reason: 'grant RECORD_AUDIO');
    expect(
      await rec.notificationPermission(),
      isTrue,
      reason: 'grant POST_NOTIFICATIONS',
    );
    expect(
      await rec.overlayPermission(),
      isTrue,
      reason: 'allow SYSTEM_ALERT_WINDOW',
    );
  });

  // ------------------------------------------------------------------ basic capture

  testWidgets('records a video-only 720p clip', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      length: const Duration(seconds: 3),
    );
    expect(take.name, matches(RegExp(r'^Reelmint_\d{8}_\d{6}\.mp4$')));
    expect(take.info.duration.inMilliseconds, closeToMs(3000, 900));
    expect(take.shortSide, closeToMs(math.min(720, deviceShort), 16));
    expect(take.info.hasAudio, isFalse);
    expect(
      take.states,
      containsAllInOrder([
        RecState.recording,
        RecState.stopping,
        RecState.idle,
      ]),
    );
    expect(take.reportedDuration.inMilliseconds, closeToMs(3000, 900));
  });

  testWidgets('elapsed timer advances while recording', (t) async {
    await busy(t);
    late Duration a, b;
    await record(
      rec,
      cleanup: created,
      during: () async {
        await sleep(800);
        a = rec.elapsed;
        await sleep(1200);
        b = rec.elapsed;
      },
    );
    expect(a.inMilliseconds, greaterThan(400));
    expect((b - a).inMilliseconds, closeToMs(1200, 400));
  });

  testWidgets('two recordings back to back (projection re-acquired)', (
    t,
  ) async {
    await busy(t);
    final a = await record(
      rec,
      cleanup: created,
      length: const Duration(seconds: 2),
    );
    await sleep(1100); // file names have 1s resolution
    final b = await record(
      rec,
      cleanup: created,
      length: const Duration(seconds: 2),
    );
    expect(a.path, isNot(b.path));
  });

  testWidgets('starting while already recording is rejected', (t) async {
    await busy(t);
    String? err;
    final sub = rec.events.listen((e) {
      if (e is RecorderMessage && e.isError) err = e.message;
    });
    await record(
      rec,
      cleanup: created,
      during: () async {
        await sleep(500);
        expect(await rec.start(baseOptions), isFalse);
        await sleep(300);
      },
    );
    await sub.cancel();
    expect(err, contains('already in progress'));
  });

  // ------------------------------------------------------------------ audio

  for (final source in ['mic', 'internal', 'both']) {
    testWidgets('audio source "$source" produces an AAC track', (t) async {
      await busy(t);
      final take = await record(
        rec,
        cleanup: created,
        options: {'audio': source},
      );
      expect(
        take.info.hasAudio,
        isTrue,
        reason: '$source should add an audio track',
      );
      expect(take.info.duration.inMilliseconds, closeToMs(3000, 900));
    });
  }

  testWidgets('mic can be muted and unmuted mid-recording', (t) async {
    await busy(t);
    final seen = <bool>[];
    rec.addListener(() {
      if (seen.isEmpty || seen.last != rec.micMuted) seen.add(rec.micMuted);
    });
    final take = await record(
      rec,
      cleanup: created,
      options: {'audio': 'mic'},
      during: () async {
        await sleep(700);
        await rec.toggleMic();
        await waitUntil(() => rec.micMuted, what: 'mic muted event');
        await sleep(700);
        await rec.toggleMic();
        await waitUntil(() => !rec.micMuted, what: 'mic unmuted event');
        await sleep(500);
      },
    );
    expect(seen, containsAllInOrder([true, false]));
    expect(take.info.hasAudio, isTrue);
  });

  // ------------------------------------------------------------------ pause / resume

  testWidgets('pause and resume leave no gap in the video', (t) async {
    await busy(t);
    late Duration atPause, afterPause;
    final take = await record(
      rec,
      cleanup: created,
      options: {'audio': 'internal'},
      during: () async {
        await sleep(2000);
        await rec.pause();
        await waitUntil(
          () => rec.state == RecState.paused,
          what: 'paused state',
        );
        atPause = rec.elapsed;
        await sleep(3000);
        afterPause = rec.elapsed;
        await rec.resume();
        await waitUntil(
          () => rec.state == RecState.recording,
          what: 'resumed state',
        );
        await sleep(2000);
      },
    );
    expect(
      take.states,
      containsAllInOrder([
        RecState.recording,
        RecState.paused,
        RecState.recording,
      ]),
    );
    expect(afterPause, atPause, reason: 'timer frozen while paused');
    // 2s + 2s recorded; the 3s pause must not be in the file.
    expect(take.info.duration.inMilliseconds, closeToMs(4000, 1100));
    expect(take.reportedDuration.inMilliseconds, closeToMs(4000, 1100));
  });

  testWidgets('pause/resume are ignored when not applicable', (t) async {
    await rec.resume(); // idle: no-op
    await rec.pause();
    await sleep(300);
    expect(rec.state, RecState.idle);
  });

  // ------------------------------------------------------------------ countdown

  testWidgets('countdown ticks down before recording starts', (t) async {
    await busy(t);
    final counts = <int>[];
    void track() {
      if (rec.state == RecState.countdown &&
          (counts.isEmpty || counts.last != rec.countdown))
        counts.add(rec.countdown);
    }

    rec.addListener(track);
    final sw = Stopwatch()..start();
    late int startedAfterMs;
    await record(
      rec,
      cleanup: created,
      options: {'countdown': 2},
      during: () async {
        startedAfterMs = sw.elapsedMilliseconds;
        await sleep(1500);
      },
    );
    rec.removeListener(track);
    expect(counts, [2, 1]);
    expect(startedAfterMs, greaterThanOrEqualTo(1800));
  });

  testWidgets('cancelling during countdown saves nothing', (t) async {
    await busy(t);
    final before = Directory(rec.recordingsDir!).listSync().length;
    var saved = false;
    final sub = rec.events.listen((e) => saved |= e is RecordingSaved);
    expect(await rec.start({...baseOptions, 'countdown': 5}), isTrue);
    await waitUntil(() => rec.state == RecState.countdown, what: 'countdown');
    await sleep(1200);
    await rec.stop();
    await waitUntil(
      () => rec.state == RecState.idle,
      what: 'idle after cancel',
    );
    await sleep(1500);
    await sub.cancel();
    expect(saved, isFalse);
    expect(Directory(rec.recordingsDir!).listSync().length, before);
  });

  // ------------------------------------------------------------------ video options

  testWidgets('native resolution matches the screen', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'resolution': 0, 'fps': 30},
    );
    expect(
      take.shortSide,
      greaterThanOrEqualTo((deviceShort * 0.9).round()),
      reason:
          'got ${take.info.width}x${take.info.height}, screen ${deviceShort}x$deviceLong',
    );
  });

  for (final res in [1080, 480]) {
    testWidgets('${res}p resolution', (t) async {
      await busy(t);
      final take = await record(
        rec,
        cleanup: created,
        options: {'resolution': res},
      );
      expect(
        take.shortSide,
        closeToMs(math.min(res, deviceShort), 16),
        reason: '${take.info.width}x${take.info.height}',
      );
      final aspect = take.longSide / take.shortSide;
      expect(
        aspect,
        closeTo(deviceLong / deviceShort, 0.05),
        reason: 'keeps the screen aspect ratio',
      );
    });
  }

  testWidgets('landscape orientation produces a wide video', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'orientation': 'landscape'},
    );
    expect(take.info.width, greaterThan(take.info.height));
  });

  testWidgets('portrait orientation produces a tall video', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'orientation': 'portrait'},
    );
    expect(take.info.height, greaterThan(take.info.width));
  });

  testWidgets('30 fps cap is respected', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'fps': 30},
      length: const Duration(seconds: 4),
    );
    expect(take.info.frameCount, greaterThan(0));
    expect(
      take.fps,
      lessThanOrEqualTo(34),
      reason: 'measured ${take.fps.toStringAsFixed(1)} fps',
    );
    expect(
      take.fps,
      greaterThanOrEqualTo(20),
      reason: 'measured ${take.fps.toStringAsFixed(1)} fps',
    );
  });

  testWidgets('60 fps records smoothly', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'fps': 60},
      length: const Duration(seconds: 4),
    );
    expect(
      take.fps,
      greaterThanOrEqualTo(40),
      reason: 'measured ${take.fps.toStringAsFixed(1)} fps',
    );
    expect(
      take.fps,
      lessThanOrEqualTo(66),
      reason: 'measured ${take.fps.toStringAsFixed(1)} fps',
    );
  });

  testWidgets('manual bitrate limits file bitrate', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'bitrate': 2000000},
      length: const Duration(seconds: 4),
    );
    expect(
      take.info.bitrate,
      lessThanOrEqualTo(3500000),
      reason: 'measured ${take.info.bitrate} bps',
    );
  });

  testWidgets('floating controls option records normally', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'floatingControls': true},
    );
    expect(take.info.duration.inMilliseconds, closeToMs(3000, 900));
  });

  // ------------------------------------------------------------------ media tools

  testWidgets('thumbnails are JPEGs at different timestamps', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      length: const Duration(seconds: 3),
    );
    for (final at in [0, 1500, 2800]) {
      final bytes = await rec.thumbnail(take.path, atMs: at, maxWidth: 200);
      expect(bytes, isNotNull, reason: 'thumbnail at $at ms');
      expect(bytes!.sublist(0, 2), [0xFF, 0xD8], reason: 'JPEG magic');
      final img = await decodeImageFromList(bytes);
      expect(img.width, lessThanOrEqualTo(200));
    }
    expect(await rec.thumbnail('/does/not/exist.mp4'), isNull);
  });

  testWidgets('lossless trim creates a shorter copy', (t) async {
    await busy(t);
    final take = await record(
      rec,
      cleanup: created,
      options: {'audio': 'internal'},
      length: const Duration(seconds: 6),
    );
    final out = await rec.trim(
      take.path,
      const Duration(seconds: 2),
      const Duration(milliseconds: 4500),
    );
    created.add(out);
    expect(File(out).existsSync(), isTrue);
    expect(out, contains('_trim'));
    final info = await rec.info(out);
    // Cut snaps back to the previous keyframe (≤1s at 1 keyframe/s).
    expect(info.duration.inMilliseconds, inInclusiveRange(1800, 3700));
    expect(info.hasAudio, isTrue);
    expect(
      (await rec.info(take.path)).duration.inMilliseconds,
      take.info.duration.inMilliseconds,
      reason: 'original untouched',
    );
  });

  testWidgets(
    'recordings are saved in Movies/Reelmint and appear in the Gallery',
    (t) async {
      await busy(t);
      final take = await record(rec, cleanup: created);
      expect(take.path, contains('/Movies/Reelmint/'));
      var found = false;
      for (var i = 0; i < 30 && !found; i++) {
        found = await rec.galleryHas(take.name);
        if (!found) await sleep(200);
      }
      expect(found, isTrue, reason: 'media index knows the new recording');
      File(take.path).deleteSync();
      await rec.scan([take.path]);
      var gone = false;
      for (var i = 0; i < 30 && !gone; i++) {
        gone = !await rec.galleryHas(take.name);
        if (!gone) await sleep(200);
      }
      expect(gone, isTrue, reason: 'deleting removes it from the Gallery too');
    },
  );

  // ------------------------------------------------------------------ library on real files

  testWidgets('library lists, renames and deletes real recordings', (t) async {
    await busy(t);
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    final lib = Library(rec, settings);
    final take = await record(
      rec,
      cleanup: created,
      length: const Duration(seconds: 2),
    );
    await lib.refresh();
    final item = lib.byPath(take.path);
    expect(item, isNotNull);
    expect(item!.info!.duration.inMilliseconds, closeToMs(2000, 900));

    final renamed = await lib.rename(
      item,
      'Reelmint test ${DateTime.now().millisecondsSinceEpoch}',
    );
    created.add(renamed.path);
    expect(File(take.path).existsSync(), isFalse);
    expect(renamed.file.existsSync(), isTrue);

    await lib.delete([lib.byPath(renamed.path)!]);
    expect(renamed.file.existsSync(), isFalse);
    expect(lib.byPath(renamed.path), isNull);
  });
}
