// End-to-end UI journey on a real Android device: record from the home screen,
// watch, change speed, inspect details, favorite, trim, rename, export, delete.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelmint/main.dart' as app;
import 'package:reelmint/ui/screens/player_screen.dart';
import 'package:reelmint/ui/screens/trim_screen.dart';
import 'package:reelmint/ui/widgets/common.dart';
import 'package:reelmint/ui/widgets/record_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> idle(WidgetTester t, [int ms = 400]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await t.pump();
  }

  /// Waits until [f] is on screen and hit-testable, then lets entry animations finish.
  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (f.hitTestable().evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $f');
      await idle(t, 100);
    }
    await idle(t, 600);
  }

  /// Player controls auto-hide; tap the video to bring them back.
  Future<void> chrome(WidgetTester t) async {
    if (find.text('Share').hitTestable().evaluate().isNotEmpty) return;
    await t.tapAt(t.getCenter(find.byType(PlayerScreen)));
    await idle(t, 500);
  }

  Future<void> tapAction(WidgetTester t, String label) async {
    await chrome(t);
    await t.tap(find.text(label));
  }

  Future<void> waitGone(WidgetTester t, Finder f, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (f.evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end))
        fail('Timed out waiting for $f to disappear');
      await idle(t, 100);
    }
  }

  testWidgets(
    'full journey: record → watch → trim → rename → export → delete',
    (t) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setBool('onboarded', true);
      await prefs.setBool('haptics', false);
      await prefs.setBool('minimizeOnStart', false);
      await prefs.setBool('stopOnScreenOff', false);
      await prefs.setInt('countdown', 0);
      await prefs.setInt('resolution', 720);
      await prefs.setInt('fps', 30);
      await prefs.setString('audio', 'internal');

      // Remove anything this test records, even if it fails part-way.
      final recDirPath = (await _native.invokeMethod<String>(
        'getRecordingsDir',
      ))!;
      final before = Directory(recDirPath)
          .listSync()
          .map((e) => e.path)
          .toSet();
      addTearDown(() async {
        final made = Directory(recDirPath)
            .listSync()
            .whereType<File>()
            .where((f) => !before.contains(f.path))
            .toList();
        for (final f in made) {
          f.deleteSync();
        }
        await _native.invokeMethod('scan', {
          'paths': made.map((f) => f.path).toList(),
        });
      });

      await app.main();
      await waitFor(t, find.text('Ready to record'));
      expect(find.text('720p · 30 fps · Device audio'), findsOneWidget);

      // ---- record from the orb, pause/resume from the live controls, stop
      await t.tap(find.byType(RecordButton));
      await waitFor(t, find.text('REC'));
      await idle(t, 1500);
      await t.tap(find.text('Pause'));
      await waitFor(t, find.text('PAUSED'));
      await idle(t, 1000);
      await t.tap(find.text('Resume'));
      await waitFor(t, find.text('REC'));
      await idle(t, 1500);
      await t.tap(find.text('Stop'));

      // ---- saved sheet → Watch
      await waitFor(t, find.text('Recording saved'));
      await t.tap(find.text('Watch'));
      await waitFor(t, find.byType(VideoPlayer));
      await chrome(t);
      for (final a in ['Share', 'Trim', 'Tools', 'Rename', 'Delete', '1×']) {
        expect(find.text(a), findsOneWidget, reason: 'player action $a');
      }
      final player = t.state(find.byType(PlayerScreen));
      expect(player.mounted, isTrue);

      // ---- playback speed
      await t.tap(find.text('1×'));
      await waitFor(t, find.text('Playback speed'));
      await t.tap(find.text('2.0×'));
      await chrome(t);
      expect(find.text('2.0×'), findsOneWidget);

      // ---- details sheet
      await chrome(t);
      await t.tap(find.byIcon(Icons.info_outline_rounded));
      await waitFor(t, find.text('Details'));
      expect(find.textContaining('720 ×'), findsOneWidget);
      expect(find.text('AAC stereo'), findsOneWidget);
      expect(find.text('MP4 · H.264'), findsOneWidget);
      await t.tapAt(const Offset(30, 120));
      await waitGone(t, find.text('Details'));

      // ---- favorite
      await chrome(t);
      await t.tap(find.byIcon(Icons.favorite_border_rounded));
      // Controls may auto-hide right after the tap, so check existence rather than hit-testability.
      final favEnd = DateTime.now().add(const Duration(seconds: 10));
      while (find.byIcon(Icons.favorite_rounded).evaluate().isEmpty) {
        if (DateTime.now().isAfter(favEnd)) fail('favorite did not toggle');
        await idle(t, 100);
      }

      // ---- trim: drag the start handle right, save
      await tapAction(t, 'Trim');
      await waitFor(t, find.byType(TrimScreen));
      await waitFor(t, find.byType(VideoPlayer));
      await idle(t, 500);
      await t.drag(
        find.byKey(const ValueKey('trim-start')),
        const Offset(70, 0),
      );
      await idle(t, 300);
      await t.drag(
        find.byKey(const ValueKey('trim-end')),
        const Offset(-40, 0),
      );
      await idle(t, 300);
      await t.tap(find.text('Save as new clip'));
      await waitFor(t, find.text('Trimmed copy saved'));
      await waitFor(t, find.byType(VideoPlayer));
      expect(
        find.textContaining('trim'),
        findsOneWidget,
        reason: 'player now shows the trimmed clip',
      );

      // ---- rename
      final newName = 'Journey ${DateTime.now().millisecondsSinceEpoch}';
      await tapAction(t, 'Rename');
      await waitFor(t, find.byType(TextField));
      await t.enterText(find.byType(TextField), newName);
      await t.tap(find.text('Save'));
      await waitFor(t, find.text(newName));

      // ---- recordings live in Movies/Reelmint and show up in the Gallery
      final recDir = (await _native.invokeMethod<String>('getRecordingsDir'))!;
      expect(recDir, endsWith('/Movies/Reelmint'));
      Future<bool> inGallery(String name) async {
        // the media scan is asynchronous; give it a moment
        for (var i = 0; i < 30; i++) {
          final has = (await _native.invokeMethod<bool>('galleryHas', {
            'name': name,
          }))!;
          if (has) return true;
          await idle(t, 200);
        }
        return false;
      }

      expect(
        await inGallery('$newName.mp4'),
        isTrue,
        reason: 'renamed clip is in the Gallery',
      );

      // ---- delete the trimmed copy from the player
      await tapAction(t, 'Delete');
      await waitFor(t, find.text('Delete recording?'));
      await t.tap(find.text('Delete').last);
      await waitFor(t, find.text('Ready to record'));
      await idle(t, 800);
      expect(
        find.textContaining(newName),
        findsNothing,
        reason: 'deleted clip gone from Recent',
      );
      var galleryGone = false;
      for (var i = 0; i < 30 && !galleryGone; i++) {
        galleryGone = !(await _native.invokeMethod<bool>('galleryHas', {
          'name': '$newName.mp4',
        }))!;
        if (!galleryGone) await idle(t, 200);
      }
      expect(galleryGone, isTrue, reason: 'deleted clip gone from the Gallery');

      // ---- library: the original is still there; select & delete it
      await t.tap(find.byKey(const ValueKey('nav-1')));
      await waitFor(t, find.text('Library'));
      expect(
        find.text('Internal storage › Movies › Reelmint'),
        findsOneWidget,
        reason: 'Library shows where videos are saved',
      );
      final dir = Directory(
        (await _native.invokeMethod<String>('getRecordingsDir'))!,
      );
      expect(
        dir.listSync().whereType<File>().any((f) => f.path.contains(newName)),
        isFalse,
      );
      final cards = find.textContaining('Today,');
      await waitFor(t, cards);
      await t.longPress(cards.first);
      await waitFor(t, find.text('1 selected'));
      await t.tap(find.byTooltip('Delete'));
      await waitFor(t, find.text('Delete 1 recording?'));
      await t.tap(find.text('Delete').last);
      await waitFor(t, find.text('Deleted'));
      await idle(t, 600);
      expect(
        find.textContaining('Today,'),
        findsNothing,
        reason: 'library is empty after deleting',
      );
      await t.tap(find.byKey(const ValueKey('nav-0')));
      await idle(t, 800);
      expect(
        find.textContaining('Today,'),
        findsNothing,
        reason: 'nothing left in Recent',
      );
      expect(
        find.byType(ThumbImage),
        findsNothing,
        reason: 'no thumbnails left on home',
      );
    },
  );
}

const _native = MethodChannel('reelmint/recorder');
