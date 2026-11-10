import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/settings.dart';
import 'package:reelmint/ui/screens/settings_screen.dart';

import 'helpers/fake_native.dart';

void main() {
  Future<Harness> openSettings(
    WidgetTester t, {
    void Function(FakeNative)? arrange,
  }) async {
    final h = await pumpReelmint(t, arrange: arrange);
    await t.tap(find.byKey(const ValueKey('nav-2')));
    await settle(t);
    return h;
  }

  /// Scrolls the (lazily built) settings list until [f] exists.
  Future<void> reveal(WidgetTester t, Finder f) async {
    final list = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await t.scrollUntilVisible(f, 120, scrollable: list);
    await t.ensureVisible(f);
  }

  Future<void> tapRow(WidgetTester t, String title) async {
    await reveal(t, find.text(title));
    await settle(t, 3);
    await t.tap(find.text(title));
    await settle(t);
  }

  Future<void> choose(WidgetTester t, String option) async {
    await t.tap(find.text(option).last);
    await settle(t);
  }

  testWidgets('shows every Android setting', (t) async {
    await openSettings(t);
    for (final label in [
      'recordings',
      'Resolution',
      'Frame rate',
      'Bitrate',
      'Orientation',
      'Source',
      'Quality',
      'Show facecam',
      'Bubble size',
      'Countdown',
      'Auto-stop',
      'Floating controls',
      'Shake to stop',
      'Minimize on start',
      'Stop when screen locks',
      'Saved to',
      'Add Quick Settings tile',
      'App lock',
      'Theme',
      'Accent',
      'Haptic feedback',
      'Used by recordings',
      'Delete all recordings',
      'No ads. No tracking. No watermark.',
      'Reelmint 1.0.0',
    ]) {
      await reveal(t, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('video pickers: resolution, frame rate, bitrate, orientation', (
    t,
  ) async {
    final h = await openSettings(t);
    await tapRow(t, 'Resolution');
    await choose(t, '1440p');
    expect(h.settings.resolution, 1440);

    await tapRow(t, 'Frame rate');
    await choose(t, '90 fps');
    expect(h.settings.fps, 90);

    await tapRow(t, 'Bitrate');
    await choose(t, '16 Mbps');
    expect(h.settings.bitrateMbps, 16);
    expect(find.text('16 Mbps'), findsOneWidget);

    await tapRow(t, 'Orientation');
    await choose(t, 'Landscape');
    expect(h.settings.orientation, RecOrientation.landscape);
  });

  testWidgets('audio pickers: source and quality', (t) async {
    final h = await openSettings(t);
    await tapRow(t, 'Source');
    await choose(t, 'Microphone');
    expect(h.settings.audio, AudioSource.mic);
    await tapRow(t, 'Quality');
    await choose(t, '256 kbps');
    expect(h.settings.audioKbps, 256);
  });

  testWidgets('countdown picker', (t) async {
    final h = await openSettings(t);
    await tapRow(t, 'Countdown');
    await choose(t, '10 seconds');
    expect(h.settings.countdown, 10);
    await tapRow(t, 'Countdown');
    await choose(t, 'Off');
    expect(h.settings.countdown, 0);
  });

  testWidgets('toggles flip their settings', (t) async {
    final h = await openSettings(t);
    final s = h.settings;
    await tapRow(t, 'Minimize on start');
    expect(s.minimizeOnStart, isFalse);
    await tapRow(t, 'Stop when screen locks');
    expect(s.stopOnScreenOff, isFalse);
    await tapRow(t, 'Haptic feedback');
    expect(s.haptics, isTrue, reason: 'test prefs start with haptics off');
    await tapRow(t, 'Haptic feedback');
    expect(s.haptics, isFalse);
  });

  testWidgets('floating controls ask for overlay permission first', (t) async {
    final h = await openSettings(t);
    await tapRow(t, 'Floating controls');
    expect(find.text('Allow floating controls'), findsOneWidget);
    await t.tap(find.text('Open settings'));
    await pumpReal(t);
    expect(h.native.callsTo('requestOverlayPermission'), hasLength(1));
    expect(h.settings.floatingControls, isFalse);
  });

  testWidgets('floating controls toggle directly when permission is granted', (
    t,
  ) async {
    final h = await openSettings(t, arrange: (n) => n.overlayGranted = true);
    await pumpReal(t, 4);
    await tapRow(t, 'Floating controls');
    expect(find.text('Allow floating controls'), findsNothing);
    expect(h.settings.floatingControls, isTrue);
  });

  testWidgets('theme picker switches light / dark / system', (t) async {
    final h = await openSettings(t);
    BuildContext ctx() => t.element(find.byType(SettingsScreen));
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    await tapRow(t, 'Theme');
    await choose(t, 'Light');
    expect(h.settings.themeMode, ThemeMode.light);
    expect(Theme.of(ctx()).brightness, Brightness.light);
    await tapRow(t, 'Theme');
    await choose(t, 'Match system');
    expect(h.settings.themeMode, ThemeMode.system);
  });

  testWidgets('storage usage and delete all', (t) async {
    final h = await openSettings(
      t,
      arrange: (n) {
        n.addRecording('a.mp4', bytes: 2048);
        n.addRecording('b.mp4', bytes: 2048);
      },
    );
    await reveal(t, find.text('Used by recordings'));
    expect(find.text('4.0 KB · 2'), findsOneWidget);
    await tapRow(t, 'Delete all recordings');
    expect(find.text('Delete all recordings?'), findsOneWidget);
    await t.tap(find.text('Delete all'));
    await pumpReal(t);
    expect(h.library.items, isEmpty);
    expect(h.native.dir.listSync(), isEmpty);
    expect(find.text('Library cleared'), findsOneWidget);
  });
}
