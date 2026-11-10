// On-device tests for the Android feature set: facecam, draw overlay, auto-stop,
// shake listener, editor (rotate / remove+extract audio / save frame / compress /
// speed / merge / cancel), storage, Quick Settings tile and launcher shortcut.
// Run with:  dart run tool/device_test.dart --skip-host --only=features_test
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelmint/services/recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final rec = Recorder();
  final created = <String>[];
  late Take sample; // 6s clip with audio, shared by the editor tests

  Future<void> busy(WidgetTester t) async {
    await t.pumpWidget(const Busy());
    await t.pump();
  }

  /// Asks the host runner (tool/device_test.dart) to do something over adb.
  void hostDo(String marker) {
    // ignore: avoid_print
    print(marker);
  }

  setUpAll(() async {
    await rec.init();
  });

  tearDownAll(() async {
    for (final p in created) {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
  });

  testWidgets('capabilities: camera + Quick Settings tile support', (t) async {
    expect(rec.caps.hasCamera, isTrue);
    expect(rec.caps.quickTile, rec.caps.sdk >= 33);
    expect(
      await rec.cameraPermission(),
      isTrue,
      reason: 'runner grants CAMERA',
    );
    expect(await rec.canAuthenticate(), isA<bool>());
  });

  testWidgets('storage info', (t) async {
    final s = await rec.storage();
    expect(s.total, greaterThan(1024 * 1024 * 1024));
    expect(s.free, inInclusiveRange(1, s.total));
  });

  // ------------------------------------------------------------------ overlays

  testWidgets('facecam starts with the recording and toggles live', (t) async {
    await busy(t);
    final seen = <bool>[];
    void track() {
      if (seen.isEmpty || seen.last != rec.facecamOn) seen.add(rec.facecamOn);
    }

    rec.addListener(track);
    await record(
      rec,
      cleanup: created,
      options: {'facecam': true, 'facecamSize': 's'},
      during: () async {
        await waitUntil(() => rec.facecamOn, what: 'facecam bubble shown');
        await sleep(1500); // let the camera stream
        await rec.toggleFacecam();
        await waitUntil(() => !rec.facecamOn, what: 'facecam hidden');
        await sleep(500);
        await rec.toggleFacecam();
        await waitUntil(() => rec.facecamOn, what: 'facecam shown again');
        await sleep(800);
      },
    );
    rec.removeListener(track);
    expect(seen, containsAllInOrder([true, false, true]));
    expect(rec.facecamOn, isFalse, reason: 'cleared after stop');
  });

  testWidgets('draw-on-screen overlay toggles during recording', (t) async {
    await busy(t);
    await record(
      rec,
      cleanup: created,
      during: () async {
        await sleep(500);
        await rec.toggleDraw();
        await waitUntil(() => rec.drawOn, what: 'draw overlay shown');
        await sleep(800);
        await rec.toggleDraw();
        await waitUntil(() => !rec.drawOn, what: 'draw overlay closed');
      },
    );
  });

  testWidgets(
    'floating bubble: stays on screen on both edges, drags from buttons without clicking them',
    (t) async {
      await busy(t);
      const ch = MethodChannel('reelmint/recorder');
      Future<Map<String, dynamic>> geo() async => Map<String, dynamic>.from(
        (await ch.invokeMethod<Map>('bubbleGeometry'))!,
      );
      Future<Map<String, dynamic>> settled(
        bool Function(Map<String, dynamic>) cond,
        String what,
      ) async {
        final end = DateTime.now().add(const Duration(seconds: 10));
        while (true) {
          final g = await ch.invokeMethod<Map>('bubbleGeometry');
          if (g != null) {
            final m = Map<String, dynamic>.from(g);
            if (m['animating'] != true && cond(m)) {
              await sleep(150);
              return geo();
            }
          }
          if (DateTime.now().isAfter(end))
            fail('bubble: timed out waiting for $what (last: $g)');
          await sleep(100);
        }
      }

      void onScreen(Map<String, dynamic> g, String when) {
        expect(
          g['left'] as int,
          greaterThanOrEqualTo(0),
          reason: '$when: left edge on screen ($g)',
        );
        expect(
          g['right'] as int,
          lessThanOrEqualTo(g['screenWidth'] as int),
          reason: '$when: right edge on screen ($g)',
        );
      }

      List<int> pt(Map<String, dynamic> g, String k) =>
          List<int>.from(g[k] as List);
      void input(String args) => hostDo('REELMINT_INPUT $args');

      await record(
        rec,
        cleanup: created,
        options: {'floatingControls': true},
        during: () async {
          var g = await settled((g) => g['pause'] != null, 'bubble shown');
          expect(g['dockRight'], isFalse);
          onScreen(g, 'start');

          // Open the ⋮ menu with a real tap.
          var p = pt(g, 'more');
          input('tap ${p[0]} ${p[1]}');
          g = await settled(
            (g) => g['expanded'] == true && g['pen'] != null,
            'menu expanded',
          );
          onScreen(g, 'expanded on the left');
          final w = g['screenWidth'] as int;

          // Drag to the right edge starting ON the pause button: must move, must not pause.
          p = pt(g, 'pause');
          input('swipe ${p[0]} ${p[1]} ${w - 40} ${p[1] + 300} 500');
          g = await settled((g) => g['dockRight'] == true, 'docked right');
          onScreen(g, 'expanded on the right');
          expect(
            w - (g['right'] as int),
            lessThan(80),
            reason: 'hugs the right edge',
          );
          expect(
            g['expanded'],
            isTrue,
            reason: 'menu stays open while dragging',
          );
          expect(
            rec.state,
            RecState.recording,
            reason: 'drag from the pause button did not click it',
          );

          // Collapse and re-open via the dot while on the right; still on screen.
          p = pt(g, 'dot');
          input('tap ${p[0]} ${p[1]}');
          g = await settled((g) => g['collapsed'] == true, 'collapsed');
          onScreen(g, 'collapsed on the right');
          p = pt(g, 'dot');
          input('tap ${p[0]} ${p[1]}');
          g = await settled(
            (g) => g['collapsed'] == false && g['pen'] != null,
            'expanded again',
          );
          onScreen(g, 'reopened on the right');
          expect(w - (g['right'] as int), lessThan(80));

          // Drag back to the left starting ON the stop button: must not stop.
          p = pt(g, 'stop');
          input('swipe ${p[0]} ${p[1]} 40 ${p[1] - 200} 500');
          g = await settled(
            (g) => g['dockRight'] == false,
            'docked left again',
          );
          onScreen(g, 'back on the left');
          expect(g['left'] as int, lessThan(80));
          expect(
            rec.state,
            RecState.recording,
            reason: 'drag from the stop button did not click it',
          );

          // A plain tap on a button still works.
          p = pt(g, 'pause');
          input('tap ${p[0]} ${p[1]}');
          await waitUntil(
            () => rec.state == RecState.paused,
            what: 'bubble pause tap',
          );
          g = await geo();
          p = pt(g, 'pause');
          input('tap ${p[0]} ${p[1]}');
          await waitUntil(
            () => rec.state == RecState.recording,
            what: 'bubble resume tap',
          );
        },
      );
    },
  );

  testWidgets('overlay toggles are ignored when not recording', (t) async {
    await rec.toggleFacecam();
    await rec.toggleDraw();
    await sleep(400);
    expect(rec.facecamOn, isFalse);
    expect(rec.drawOn, isFalse);
  });

  // ------------------------------------------------------------------ automation

  testWidgets('auto-stop ends the recording at the time limit', (t) async {
    await busy(t);
    final msgs = <String>[];
    final saved = Completer<RecordingSaved>();
    final sub = rec.events.listen((e) {
      if (e is RecorderMessage) msgs.add(e.message);
      if (e is RecordingSaved && !saved.isCompleted) saved.complete(e);
    });
    expect(await rec.start({...baseOptions, 'timeLimitSec': 3}), isTrue);
    final s = await saved.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => fail('did not auto-stop'),
    );
    await sub.cancel();
    created.add(s.path);
    await waitUntil(() => rec.state == RecState.idle, what: 'idle');
    expect(msgs, contains('Time limit reached — recording stopped.'));
    expect(
      (await rec.info(s.path)).duration.inMilliseconds,
      closeToMs(3000, 900),
    );
  });

  testWidgets(
    'shake-to-stop listener records normally (no false triggers when still)',
    (t) async {
      await busy(t);
      final take = await record(
        rec,
        cleanup: created,
        options: {'shakeToStop': true},
        length: const Duration(seconds: 3),
      );
      expect(take.info.duration.inMilliseconds, closeToMs(3000, 900));
    },
  );

  // ------------------------------------------------------------------ editor

  testWidgets('record sample clip for the editor', (t) async {
    await t.pumpWidget(
      const Motion(),
    ); // real motion, like a typical screen recording
    await t.pump();
    sample = await record(
      rec,
      cleanup: created,
      options: {'audio': 'internal', 'resolution': 720},
      length: const Duration(seconds: 6),
    );
    expect(sample.info.hasAudio, isTrue);
  });

  testWidgets('rotate 90° swaps the displayed width and height (lossless)', (
    t,
  ) async {
    final out = await rec.rotate(sample.path, 90);
    created.add(out);
    final i = await rec.info(out);
    expect(i.width, sample.info.height);
    expect(i.height, sample.info.width);
    expect(
      i.duration.inMilliseconds,
      closeToMs(sample.info.duration.inMilliseconds, 150),
    );
    expect(
      File(out).lengthSync(),
      closeToMs(File(sample.path).lengthSync(), 64 * 1024),
      reason: 'no re-encode',
    );
  });

  testWidgets('remove audio keeps video only', (t) async {
    final out = await rec.removeAudio(sample.path);
    created.add(out);
    final i = await rec.info(out);
    expect(i.hasAudio, isFalse);
    expect(i.width, sample.info.width);
    expect(
      i.duration.inMilliseconds,
      closeToMs(sample.info.duration.inMilliseconds, 150),
    );
  });

  testWidgets('extract audio produces an .m4a and saves it to Music/Reelmint', (
    t,
  ) async {
    final out = await rec.extractAudio(sample.path);
    expect(out, endsWith('.m4a'));
    expect(File(out).lengthSync(), greaterThan(1024));
    expect(
      await rec.deleteShared('audio', out.split('/').last),
      greaterThan(0),
      reason: 'copy existed in Music',
    );
    File(out).deleteSync();
  });

  testWidgets('save frame writes a photo to Pictures/Reelmint', (t) async {
    final uri = await rec.saveFrame(sample.path, const Duration(seconds: 2));
    expect(uri, startsWith('content://media/'));
    final name = '${sample.name.replaceAll('.mp4', '')}_2000.jpg';
    expect(await rec.deleteShared('image', name), greaterThan(0));
  });

  testWidgets('compress to 480p re-encodes smaller with progress events', (
    t,
  ) async {
    final progress = <int>[];
    void track() {
      final p = rec.jobProgress['compress'];
      if (p != null && (progress.isEmpty || progress.last != p))
        progress.add(p);
    }

    rec.addListener(track);
    final out = await rec.transform(
      [sample.path],
      const TransformSpec(shortSide: 480, bitrate: 1000000),
      id: 'compress',
    );
    rec.removeListener(track);
    created.add(out);
    expect(out, contains('_480p'));
    final i = await rec.info(out);
    // ignore: avoid_print
    print(
      'COMPRESS src ${sample.info.width}x${sample.info.height} ${sample.info.bitrate}bps '
      '${sample.info.frameCount}f ${File(sample.path).lengthSync()}B -> '
      '${i.width}x${i.height} ${i.bitrate}bps ${i.frameCount}f ${File(out).lengthSync()}B',
    );
    expect(math.min(i.width, i.height), closeToMs(480, 16));
    expect(i.hasAudio, isTrue);
    expect(
      i.duration.inMilliseconds,
      closeToMs(sample.info.duration.inMilliseconds, 400),
    );
    expect(File(out).lengthSync(), lessThan(File(sample.path).lengthSync()));
    expect(progress, isNotEmpty);
    expect(progress.last, 100);
  });

  testWidgets('compress never returns a bigger file (near-static clip)', (
    t,
  ) async {
    await busy(t);
    final still = await record(
      rec,
      cleanup: created,
      options: {'resolution': 720},
      length: const Duration(seconds: 4),
    );
    final before = File(still.path).lengthSync();
    try {
      final out = await rec.transform(
        [still.path],
        const TransformSpec(shortSide: 480, bitrate: 1000000),
        id: 'compact',
      );
      created.add(out);
      expect(File(out).lengthSync(), lessThan(before));
    } on PlatformException catch (e) {
      expect(
        e.code,
        'compact',
        reason: 'only the "already compact" outcome may skip the output',
      );
    }
    expect(File(still.path).lengthSync(), before, reason: 'original untouched');
  });

  testWidgets('2× speed halves the duration', (t) async {
    final out = await rec.transform(
      [sample.path],
      const TransformSpec(speed: 2),
      id: 'speed',
    );
    created.add(out);
    expect(out, contains('_2x'));
    final i = await rec.info(out);
    expect(
      i.duration.inMilliseconds,
      closeToMs(sample.info.duration.inMilliseconds ~/ 2, 500),
    );
  });

  testWidgets('merge joins clips end to end', (t) async {
    await busy(t);
    final second = await record(
      rec,
      cleanup: created,
      options: {'audio': 'none'},
      length: const Duration(seconds: 3),
    );
    final out = await rec.transform(
      [sample.path, second.path],
      const TransformSpec(),
      id: 'merge',
    );
    created.add(out);
    expect(out, contains('_merged'));
    final i = await rec.info(out);
    final expected =
        sample.info.duration.inMilliseconds +
        second.info.duration.inMilliseconds;
    expect(i.duration.inMilliseconds, closeToMs(expected, 800));
    expect(
      i.hasAudio,
      isTrue,
      reason: 'silent clip gets a silent track so the whole video has sound',
    );
  });

  testWidgets('a running export can be cancelled', (t) async {
    final job = rec.transform(
      [sample.path],
      const TransformSpec(shortSide: 720, speed: 0.5),
      id: 'cancel-me',
    );
    await sleep(400);
    expect(await rec.cancelJob('cancel-me'), isTrue);
    var failed = false;
    try {
      final out = await job.timeout(const Duration(seconds: 10));
      created.add(out);
    } on PlatformException {
      failed = true;
    } on TimeoutException {
      failed = true; // cancelled jobs never complete
    }
    expect(failed, isTrue);
    expect(await rec.cancelJob('cancel-me'), isFalse, reason: 'already gone');
    await sleep(500);
    final partial = File(sample.path).parent
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('_0.5x'));
    expect(
      partial,
      isEmpty,
      reason: 'cancelled export leaves no partial file in Movies/Reelmint',
    );
  });

  // ------------------------------------------------------------------ outside-the-app entry points

  testWidgets('launcher "Record" shortcut records with the saved settings', (
    t,
  ) async {
    await busy(t);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('resolution', 480);
    await prefs.setInt('fps', 30);
    await prefs.setString('audio', 'none');
    await prefs.setInt('countdown', 0);
    await prefs.setBool('floatingControls', false);
    await prefs.setBool('stopOnScreenOff', false);
    await prefs.setBool('facecam', false);
    await prefs.setInt('timeLimitMin', 0);

    final saved = Completer<RecordingSaved>();
    final sub = rec.events.listen((e) {
      if (e is RecordingSaved && !saved.isCompleted) saved.complete(e);
    });
    hostDo('REELMINT_START_CAPTURE_ACTIVITY');
    await waitUntil(
      () => rec.state == RecState.recording,
      what: 'shortcut started a recording',
      timeout: const Duration(seconds: 30),
    );
    await sleep(2500);
    await rec.stop();
    final s = await saved.future.timeout(const Duration(seconds: 20));
    await sub.cancel();
    created.add(s.path);
    final i = await rec.info(s.path);
    expect(
      math.min(i.width, i.height),
      closeToMs(480, 16),
      reason: 'used resolution from saved settings',
    );
    expect(i.hasAudio, isFalse, reason: 'used audio=none from saved settings');
    await waitUntil(() => rec.state == RecState.idle, what: 'idle');
  });

  testWidgets('Quick Settings tile starts and stops a recording', (t) async {
    await busy(t);
    final saved = Completer<RecordingSaved>();
    final sub = rec.events.listen((e) {
      if (e is RecordingSaved && !saved.isCompleted) saved.complete(e);
    });
    hostDo('REELMINT_TILE_CLICK');
    await waitUntil(
      () => rec.state == RecState.recording,
      what: 'tile started a recording',
      timeout: const Duration(seconds: 30),
    );
    await sleep(2500);
    hostDo('REELMINT_TILE_CLICK');
    final s = await saved.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('tile did not stop the recording'),
    );
    await sub.cancel();
    created.add(s.path);
    await waitUntil(() => rec.state == RecState.idle, what: 'idle');
    expect(File(s.path).existsSync(), isTrue);
  });
}
