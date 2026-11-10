import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/settings.dart';
import 'package:reelmint/ui/widgets/record_button.dart';

import 'helpers/fake_native.dart';

void main() {
  Future<void> emit(
    WidgetTester t,
    Harness h,
    String state, {
    int elapsedMs = 0,
    int countdown = 0,
  }) async {
    h.native.emitState(state, elapsedMs: elapsedMs, countdown: countdown);
    await pumpReal(t, 4);
  }

  testWidgets(
    'idle home shows ready state, current settings and ad-free badge',
    (t) async {
      await pumpReelmint(t);
      expect(find.text('Ready to record'), findsOneWidget);
      expect(find.text('1080p · 60 fps · Device audio'), findsOneWidget);
      expect(find.text('Ad-free'), findsOneWidget);
      expect(find.text('Tap the orb to start'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('No recordings yet'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No recordings yet'), findsOneWidget);
    },
  );

  testWidgets('quality picker changes resolution', (t) async {
    final h = await pumpReelmint(t);
    await t.tap(find.text('Quality'));
    await settle(t);
    expect(find.text('Resolution'), findsOneWidget);
    await t.tap(find.text('720p'));
    await settle(t);
    expect(h.settings.resolution, 720);
    expect(find.text('720p · 60 fps · Device audio'), findsOneWidget);

    await t.tap(find.text('Quality'));
    await settle(t);
    await t.tap(find.text('Native'));
    await settle(t);
    expect(h.settings.resolution, 0);
  });

  testWidgets('frame-rate picker changes fps', (t) async {
    final h = await pumpReelmint(t);
    await t.tap(find.text('Frame rate'));
    await settle(t);
    await t.tap(find.text('30 fps'));
    await settle(t);
    expect(h.settings.fps, 30);
    await t.tap(find.text('Frame rate'));
    await settle(t);
    await t.tap(find.text('120 fps'));
    await settle(t);
    expect(h.settings.fps, 120);
  });

  testWidgets('audio picker changes source and requests mic permission', (
    t,
  ) async {
    final h = await pumpReelmint(t);
    for (final a in [
      AudioSource.mic,
      AudioSource.both,
      AudioSource.none,
      AudioSource.internal,
    ]) {
      await t.tap(find.text('Audio'));
      await settle(t);
      await t.tap(find.text(a.label).last);
      await settle(t);
      expect(h.settings.audio, a);
    }
    // mic, both and internal all need RECORD_AUDIO on Android; none does not.
    expect(h.native.callsTo('requestMicPermission'), hasLength(3));
  });

  testWidgets('presets apply their settings', (t) async {
    final h = await pumpReelmint(t);
    for (final p in QualityPreset.all) {
      await t.ensureVisible(find.text(p.name));
      await settle(t, 3);
      await t.tap(find.text(p.name));
      await settle(t, 3);
      expect(h.settings.activePreset?.name, p.name);
    }
  });

  testWidgets('tapping the orb starts recording with the saved options', (
    t,
  ) async {
    final h = await pumpReelmint(
      t,
      prefs: {
        ...testPrefs,
        'resolution': 720,
        'fps': 30,
        'audio': 'mic',
        'countdown': 0,
      },
    );
    await t.tap(find.byType(RecordButton));
    await settle(t);
    final args = Map<String, Object?>.from(
      h.native.callsTo('start').single.arguments as Map,
    );
    expect(args, h.settings.toNative());
    expect(args['resolution'], 720);
    expect(args['audio'], 'mic');
  });

  testWidgets('cancelled capture prompt shows a toast', (t) async {
    await pumpReelmint(t, arrange: (n) => n.startResult = false);
    await t.tap(find.byType(RecordButton));
    await settle(t);
    expect(find.text('Recording cancelled'), findsOneWidget);
  });

  testWidgets('live controls: timer, pause, resume, mute and stop', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'audio': 'both', 'minimizeOnStart': false},
    );
    await emit(t, h, 'recording', elapsedMs: 65000);
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('Recording your screen'), findsOneWidget);
    expect(
      find.text('Quality'),
      findsNothing,
      reason: 'quick settings hide while recording',
    );

    await t.tap(find.text('Pause'));
    await settle(t, 2);
    expect(h.native.callsTo('pause'), hasLength(1));

    await emit(t, h, 'paused', elapsedMs: 70000);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('01:10'), findsOneWidget);
    await t.tap(find.text('Resume'));
    await settle(t, 2);
    expect(h.native.callsTo('resume'), hasLength(1));

    await t.tap(find.text('Mute'));
    await settle(t, 2);
    expect(h.native.callsTo('toggleMic'), hasLength(1));
    h.native.emit({'type': 'mic', 'muted': true});
    await pumpReal(t, 3);
    expect(find.text('Unmute'), findsOneWidget);

    await t.tap(find.text('Stop'));
    await settle(t, 2);
    expect(h.native.callsTo('stop'), hasLength(1));

    await emit(t, h, 'stopping', elapsedMs: 70000);
    expect(find.text('Saving…'), findsOneWidget);
    await emit(t, h, 'idle');
    expect(find.text('Ready to record'), findsOneWidget);
  });

  testWidgets('mute control hidden when not recording the mic', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'audio': 'internal', 'minimizeOnStart': false},
    );
    await emit(t, h, 'recording');
    expect(find.text('Mute'), findsNothing);
    expect(find.text('Pause'), findsOneWidget);
    await emit(t, h, 'idle');
  });

  testWidgets('tapping the orb while recording stops', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'minimizeOnStart': false},
    );
    await emit(t, h, 'recording');
    await t.tap(find.byType(RecordButton));
    await settle(t, 2);
    expect(h.native.callsTo('stop'), hasLength(1));
    await emit(t, h, 'idle');
  });

  testWidgets('countdown overlay counts down and can be cancelled', (t) async {
    final h = await pumpReelmint(t);
    await emit(t, h, 'countdown', countdown: 3);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Recording starts soon'), findsOneWidget);
    await emit(t, h, 'countdown', countdown: 2);
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t, 2);
    expect(h.native.callsTo('stop'), hasLength(1));
    await emit(t, h, 'idle');
    expect(find.text('Recording starts soon').hitTestable(), findsNothing);
  });

  testWidgets('minimize on start sends the app to background', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'minimizeOnStart': true},
    );
    await emit(t, h, 'countdown', countdown: 1);
    await emit(t, h, 'recording');
    expect(h.native.callsTo('moveToBackground'), hasLength(1));
    await emit(t, h, 'paused');
    await emit(t, h, 'recording');
    expect(
      h.native.callsTo('moveToBackground'),
      hasLength(1),
      reason: 'resume must not minimize',
    );
    await emit(t, h, 'idle');
  });

  testWidgets('minimize disabled keeps the app open', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'minimizeOnStart': false},
    );
    await emit(t, h, 'recording');
    expect(h.native.callsTo('moveToBackground'), isEmpty);
    await emit(t, h, 'idle');
  });

  testWidgets('native errors and warnings appear as toasts', (t) async {
    final h = await pumpReelmint(t);
    h.native.emit({'type': 'error', 'message': 'Encoder exploded'});
    await pumpReal(t, 4);
    expect(find.text('Encoder exploded'), findsOneWidget);
    h.native.emit({
      'type': 'warning',
      'message': 'Audio unavailable — recording video only.',
    });
    await pumpReal(t, 4);
    await settle(t, 10); // previous snackbar animates out first
    expect(
      find.text('Audio unavailable — recording video only.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'saved recording shows a sheet with Watch and Share; recent strip fills',
    (t) async {
      final h = await pumpReelmint(t);
      final f = h.native.addRecording(
        'Reelmint_20260101_120000.mp4',
        durationMs: 4000,
        bytes: 3 * 1024 * 1024,
      );
      h.native.emit({'type': 'saved', 'path': f.path, 'durationMs': 4000});
      await pumpReal(t, 20);
      expect(find.text('Recording saved'), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.textContaining('3.0 MB'), findsWidgets);
      // close sheet
      await t.tapAt(const Offset(20, 100));
      await settle(t);
      await t.scrollUntilVisible(
        find.text('See all'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('See all'), findsOneWidget);
      expect(find.textContaining('1 recording ·'), findsOneWidget);
    },
  );
}
