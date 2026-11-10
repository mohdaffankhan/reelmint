// Widget tests for the Android-only feature set: facecam / draw / automation
// toggles, editor tools, merge, storage card, date groups, app lock, accents,
// Quick Settings tile, shortcut tabs and notification deletes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/app/scope.dart';
import 'package:reelmint/app/theme.dart';
import 'package:reelmint/services/recorder.dart';
import 'package:reelmint/ui/screens/settings_screen.dart';
import 'package:reelmint/ui/screens/shell.dart';
import 'package:reelmint/ui/widgets/tools.dart';

import 'helpers/fake_native.dart';

void main() {
  Future<void> emit(WidgetTester t, Harness h, Map<String, Object?> e) async {
    h.native.emit(e);
    await pumpReal(t, 4);
  }

  // ------------------------------------------------------------------ home toggles

  group('home quick toggles', () {
    testWidgets('facecam needs camera + overlay, then turns on', (t) async {
      final h = await pumpReelmint(
        t,
        arrange: (n) {
          n.cameraGranted = true;
          n.overlayGranted = true;
        },
      );
      await t.tap(find.text('Facecam'));
      await pumpReal(t);
      expect(h.settings.facecam, isTrue);
      expect(
        find.textContaining('Facecam'),
        findsWidgets,
        reason: 'subtitle mentions facecam',
      );
      await t.tap(find.text('Facecam'));
      await pumpReal(t);
      expect(h.settings.facecam, isFalse);
    });

    testWidgets('facecam without camera permission shows an error', (t) async {
      final h = await pumpReelmint(t);
      await t.tap(find.text('Facecam'));
      await pumpReal(t);
      expect(h.native.callsTo('requestCameraPermission'), hasLength(1));
      expect(h.settings.facecam, isFalse);
      expect(
        find.text('Camera access is needed for the facecam'),
        findsOneWidget,
      );
    });

    testWidgets('facecam with camera but no overlay asks to open settings', (
      t,
    ) async {
      final h = await pumpReelmint(t, arrange: (n) => n.cameraGranted = true);
      await t.tap(find.text('Facecam'));
      await pumpReal(t);
      expect(find.text('Allow facecam'), findsOneWidget);
      await t.tap(find.text('Open settings'));
      await pumpReal(t);
      expect(h.native.callsTo('requestOverlayPermission'), hasLength(1));
      expect(h.settings.facecam, isFalse);
    });

    testWidgets('bubble toggle', (t) async {
      final h = await pumpReelmint(t, arrange: (n) => n.overlayGranted = true);
      await t.tap(find.text('Bubble'));
      await pumpReal(t);
      expect(h.settings.floatingControls, isTrue);
    });

    testWidgets('auto-stop picker and shake toggle', (t) async {
      final h = await pumpReelmint(t);
      await t.tap(find.text('Auto-stop'));
      await settle(t);
      await t.tap(find.text('5 minutes'));
      await settle(t);
      expect(h.settings.timeLimitMin, 5);
      expect(find.text('Stop at 5m'), findsOneWidget);
      expect(h.settings.toNative()['timeLimitSec'], 300);

      await t.tap(find.text('Shake to stop'));
      await settle(t, 3);
      expect(h.settings.shakeToStop, isTrue);
    });
  });

  // ------------------------------------------------------------------ live controls

  testWidgets('live facecam & draw controls reflect overlay state', (t) async {
    final h = await pumpReelmint(
      t,
      prefs: {...testPrefs, 'minimizeOnStart': false},
      arrange: (n) {
        n.cameraGranted = true;
        n.overlayGranted = true;
      },
    );
    await emit(t, h, {
      'type': 'state',
      'state': 'recording',
      'elapsedMs': 1000,
      'countdown': 0,
    });
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);

    await t.tap(find.text('Facecam'));
    await pumpReal(t);
    expect(h.native.callsTo('toggleFacecam'), hasLength(1));
    await emit(t, h, {
      'type': 'overlays',
      'micMuted': false,
      'facecam': true,
      'draw': false,
    });
    expect(h.recorder.facecamOn, isTrue);
    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);

    await t.tap(find.text('Draw'));
    await pumpReal(t);
    expect(h.native.callsTo('toggleDraw'), hasLength(1));
    expect(
      h.native.callsTo('moveToBackground'),
      hasLength(1),
      reason: 'steps aside so you can draw over other apps',
    );
    await emit(t, h, {
      'type': 'overlays',
      'micMuted': false,
      'facecam': true,
      'draw': true,
    });
    expect(h.recorder.drawOn, isTrue);

    await emit(t, h, {
      'type': 'state',
      'state': 'idle',
      'elapsedMs': 0,
      'countdown': 0,
    });
    expect(h.recorder.facecamOn, isFalse);
    expect(h.recorder.drawOn, isFalse);
  });

  // ------------------------------------------------------------------ library

  group('library', () {
    Future<Harness> openLibrary(WidgetTester t) async {
      final now = DateTime.now();
      final h = await pumpReelmint(
        t,
        arrange: (n) {
          n.addRecording(
            'Today clip.mp4',
            modified: now.subtract(const Duration(minutes: 5)),
          );
          n.addRecording('Old clip.mp4', modified: DateTime(2024, 3, 9));
          n.addRecording('Older clip.mp4', modified: DateTime(2024, 3, 2));
        },
      );
      await t.tap(find.byKey(const ValueKey('nav-1')));
      await pumpReal(t);
      return h;
    }

    testWidgets('storage card shows free space and Reelmint usage', (t) async {
      await openLibrary(t);
      expect(find.text('20.0 GB free of 128 GB'), findsOneWidget);
      expect(find.text('Reelmint 12.0 KB'), findsOneWidget);
    });

    testWidgets(
      'storage card shows where videos are saved; tap copies the path',
      (t) async {
        final h = await openLibrary(t);
        expect(find.text('Saved to '), findsOneWidget);
        expect(find.textContaining('Reelmint'), findsWidgets);
        String? copied;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          },
        );
        await t.tap(find.byKey(const ValueKey('save-location')));
        await settle(t);
        expect(copied, h.recorder.recordingsDir);
        expect(find.text('Folder path copied'), findsOneWidget);
      },
    );

    testWidgets('recordings are grouped by date', (t) async {
      await openLibrary(t);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('MARCH 2024'), findsOneWidget);
    });

    testWidgets(
      'merge appears for 2+ selected and merges oldest-first with progress',
      (t) async {
        final h = await openLibrary(t);
        await t.ensureVisible(find.textContaining('Older clip'));
        await settle(t, 4);
        await t.longPress(find.textContaining('Old clip'));
        await settle(t);
        expect(find.byTooltip('Merge'), findsNothing);
        await t.tap(find.textContaining('Older clip'));
        await settle(t);
        expect(find.byTooltip('Merge'), findsOneWidget);

        await t.ensureVisible(find.byTooltip('Merge'));
        await settle(t, 4);
        await t.tap(find.byTooltip('Merge'));
        await pumpReal(t);
        final call = h.native.callsTo('transform').single;
        final args = call.arguments as Map;
        expect(
          (args['paths'] as List)
              .map((p) => p.toString().split(RegExp(r'[\\/]')).last)
              .toList(),
          ['Older clip.mp4', 'Old clip.mp4'],
        );
        expect(find.text('Merged into one video'), findsOneWidget);
        expect(find.textContaining('selected'), findsNothing);
      },
    );

    testWidgets('a recording deleted from the notification disappears', (
      t,
    ) async {
      final h = await openLibrary(t);
      final f = h.library.items
          .firstWhere((r) => r.fileName == 'Old clip.mp4')
          .file;
      await t.runAsync(() => f.delete());
      await emit(t, h, {'type': 'deleted', 'path': f.path});
      await pumpReal(t);
      expect(h.library.byPath(f.path), isNull);
      expect(find.textContaining('Old clip'), findsNothing);
    });
  });

  // ------------------------------------------------------------------ editor tools

  group('editor tools', () {
    Future<(Harness, BuildContext)> ready(WidgetTester t) async {
      final h = await pumpReelmint(
        t,
        arrange: (n) => n.addRecording('Clip.mp4', durationMs: 8000),
      );
      return (h, t.element(find.byType(Shell)));
    }

    Future<void> open(WidgetTester t, BuildContext ctx, Harness h) async {
      showTools(ctx, h.library.items.single, const Duration(seconds: 3));
      await settle(t);
      expect(find.text('Edit & export'), findsOneWidget);
    }

    testWidgets('sheet lists every tool', (t) async {
      final (h, ctx) = await ready(t);
      await open(t, ctx, h);
      for (final tool in Tool.values) {
        expect(find.text(tool.label), findsOneWidget);
      }
    });

    testWidgets('compress to 720p re-encodes with the right size and bitrate', (
      t,
    ) async {
      final (h, ctx) = await ready(t);
      await open(t, ctx, h);
      await t.tap(find.text('Compress'));
      await settle(t);
      await t.tap(find.text('720p'));
      await pumpReal(t);
      final a = h.native.callsTo('transform').single.arguments as Map;
      expect(a['shortSide'], 720);
      expect(a['bitrate'], 4000000);
      expect(a['speed'], 1.0);
    });

    testWidgets('speed export', (t) async {
      final (h, ctx) = await ready(t);
      await open(t, ctx, h);
      await t.tap(find.text('Change speed'));
      await settle(t);
      await t.tap(find.text('2× fast'));
      await pumpReal(t);
      expect(
        (h.native.callsTo('transform').single.arguments as Map)['speed'],
        2.0,
      );
    });

    testWidgets('rotate, remove audio and save frame call the lossless tools', (
      t,
    ) async {
      final (h, ctx) = await ready(t);
      await open(t, ctx, h);
      await t.tap(find.text('Rotate'));
      await settle(t);
      await t.tap(find.text('90° clockwise'));
      await pumpReal(t);
      expect(
        (h.native.callsTo('rotate').single.arguments as Map)['degrees'],
        90,
      );

      await open(t, ctx, h);
      await t.tap(find.text('Remove audio'));
      await pumpReal(t);
      expect(h.native.callsTo('removeAudio'), hasLength(1));

      await open(t, ctx, h);
      await t.tap(find.text('Save frame'));
      await pumpReal(t);
      expect(
        (h.native.callsTo('saveFrame').single.arguments as Map)['atMs'],
        3000,
      );
      expect(find.text('Frame saved to Pictures › Reelmint'), findsOneWidget);
    });

    testWidgets('export progress dialog shows percent and can cancel', (
      t,
    ) async {
      final (h, ctx) = await ready(t);
      // Hold the transform open so the dialog stays up.
      h.native.overrides['transform'] = (_) => Future<String>.delayed(
        const Duration(seconds: 2),
        () => throw PlatformException(code: 'cancelled'),
      );
      final r = h.recorder;
      runTransform(
        ctx,
        [h.library.items.single.path],
        const TransformSpec(shortSide: 720),
        title: 'Compressing to 720p',
      );
      await pumpReal(t, 3);
      expect(find.text('Compressing to 720p'), findsOneWidget);
      expect(find.text('Preparing…'), findsOneWidget);
      final id = r.jobProgress.keys.single;
      await emit(t, h, {'type': 'progress', 'job': id, 'progress': 42});
      expect(find.text('42%'), findsOneWidget);
      await t.tap(find.text('Cancel').last);
      await pumpReal(t);
      expect((h.native.callsTo('cancelJob').single.arguments as Map)['id'], id);
      await pumpReal(t, 40);
    });
  });

  // ------------------------------------------------------------------ settings

  group('settings', () {
    Future<Harness> openSettings(
      WidgetTester t, {
      void Function(FakeNative)? arrange,
      Map<String, Object> prefs = testPrefs,
    }) async {
      final h = await pumpReelmint(t, arrange: arrange, prefs: prefs);
      await t.tap(find.byKey(const ValueKey('nav-2')));
      await pumpReal(t);
      return h;
    }

    Future<void> reveal(WidgetTester t, Finder f) async {
      final list = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(f, 120, scrollable: list);
      await t.ensureVisible(f);
      await settle(t, 3);
    }

    testWidgets('insights card summarises the library', (t) async {
      await openSettings(
        t,
        arrange: (n) {
          n.addRecording('a.mp4', durationMs: 60000);
          n.addRecording('b.mp4', durationMs: 30000);
        },
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('01:00'), findsOneWidget);
    });

    testWidgets('size estimate footnote updates with quality', (t) async {
      final h = await openSettings(t);
      expect(find.textContaining('MB per minute'), findsOneWidget);
      final before =
          (t.widget(find.textContaining('MB per minute')) as Text).data;
      h.settings.resolution = 480;
      await settle(t, 3);
      expect(
        (t.widget(find.textContaining('MB per minute')) as Text).data,
        isNot(before),
      );
    });

    testWidgets('accent picker re-themes the app', (t) async {
      final h = await openSettings(t);
      await reveal(t, find.byKey(const ValueKey('accent-ocean')));
      await t.tap(find.byKey(const ValueKey('accent-ocean')));
      await settle(t, 5);
      expect(h.settings.accent, Accent.ocean);
      expect(L.accent, Accent.ocean);
      expect(L.primary, Accent.ocean.colors.first);
      expect(find.text('Ocean'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('accent-aurora')));
      await settle(t, 5);
      expect(L.accent, Accent.aurora);
    });

    testWidgets('app lock turns on after authenticating, off only with auth', (
      t,
    ) async {
      final h = await openSettings(t);
      await reveal(t, find.text('App lock'));
      await t.tap(find.text('App lock'));
      await pumpReal(t);
      expect(h.native.callsTo('authenticate'), hasLength(1));
      expect(h.settings.appLock, isTrue);

      h.native.authResult = false;
      await t.tap(find.text('App lock'));
      await pumpReal(t);
      expect(
        h.settings.appLock,
        isTrue,
        reason: 'failed auth must not disable the lock',
      );
    });

    testWidgets('app lock refuses without a device lock', (t) async {
      final h = await openSettings(t, arrange: (n) => n.canAuth = false);
      await reveal(t, find.text('App lock'));
      await t.tap(find.text('App lock'));
      await pumpReal(t);
      expect(h.settings.appLock, isFalse);
      expect(
        find.text('Set up a fingerprint, face or screen lock first'),
        findsOneWidget,
      );
    });

    testWidgets('add Quick Settings tile', (t) async {
      final h = await openSettings(t);
      await reveal(t, find.text('Add Quick Settings tile'));
      await t.tap(find.text('Add Quick Settings tile'));
      await pumpReal(t);
      expect(h.native.callsTo('requestAddTile'), hasLength(1));
      expect(
        find.text('Reelmint tile is in your Quick Settings'),
        findsOneWidget,
      );
    });

    testWidgets('facecam settings: toggle and size', (t) async {
      final h = await openSettings(
        t,
        arrange: (n) {
          n.cameraGranted = true;
          n.overlayGranted = true;
        },
      );
      await reveal(t, find.text('Show facecam'));
      await t.tap(find.text('Show facecam'));
      await pumpReal(t);
      expect(h.settings.facecam, isTrue);
      await t.tap(find.text('Bubble size'));
      await settle(t);
      await t.tap(find.text('Large'));
      await settle(t);
      expect(h.settings.facecamSize, 'l');
    });
  });

  // ------------------------------------------------------------------ app lock gate

  group('app lock gate', () {
    testWidgets('locked at launch, unlocks with biometrics', (t) async {
      final h = await pumpReelmint(t, prefs: {...testPrefs, 'appLock': true});
      await pumpReal(t);
      expect(h.native.callsTo('authenticate'), isNotEmpty);
      expect(
        find.text('Ready to record'),
        findsOneWidget,
        reason: 'auth succeeded',
      );
      expect(find.text('Reelmint is locked'), findsNothing);
    });

    testWidgets('stays locked when authentication fails; Unlock retries', (
      t,
    ) async {
      final h = await pumpReelmint(
        t,
        prefs: {...testPrefs, 'appLock': true},
        arrange: (n) => n.authResult = false,
      );
      await pumpReal(t);
      expect(find.text('Reelmint is locked'), findsOneWidget);
      expect(find.text('Ready to record'), findsNothing);
      h.native.authResult = true;
      await t.tap(find.text('Unlock'));
      await pumpReal(t);
      expect(find.text('Ready to record'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ shortcuts

  testWidgets('launcher "Library" shortcut opens the Library tab', (t) async {
    final h = await pumpReelmint(t);
    await emit(t, h, {'type': 'tab', 'tab': 'library'});
    expect(find.text('Your library is empty'), findsOneWidget);
    await emit(t, h, {'type': 'tab', 'tab': 'settings'});
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      AppScope.of(t.element(find.byType(Shell))).settings,
      same(h.settings),
    );
  });
}
