import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/settings.dart';

import 'helpers/fake_native.dart';

void main() {
  Future<Harness> openLibrary(
    WidgetTester t, {
    Map<String, Object> prefs = testPrefs,
    bool withFiles = true,
  }) async {
    final h = await pumpReelmint(
      t,
      prefs: prefs,
      arrange: (n) {
        if (!withFiles) return;
        n.addRecording(
          'Alpha demo.mp4',
          bytes: 2000,
          modified: DateTime(2026, 1, 1),
          durationMs: 9000,
        );
        n.addRecording(
          'Bravo.mp4',
          bytes: 9000,
          modified: DateTime(2026, 1, 3),
          durationMs: 1000,
        );
        n.addRecording(
          'Charlie demo.mp4',
          bytes: 5000,
          modified: DateTime(2026, 1, 2),
          durationMs: 5000,
        );
      },
    );
    await t.tap(find.byKey(const ValueKey('nav-1')));
    await settle(t);
    return h;
  }

  double y(WidgetTester t, String text) =>
      t.getTopLeft(find.textContaining(text)).dy;
  double x(WidgetTester t, String text) =>
      t.getTopLeft(find.textContaining(text)).dx;

  /// Reading order in the 2-column grid.
  List<String> order(WidgetTester t, List<String> names) => [...names]
    ..sort(
      (a, b) => y(t, a) != y(t, b)
          ? y(t, a).compareTo(y(t, b))
          : x(t, a).compareTo(x(t, b)),
    );

  testWidgets('empty library offers to start recording', (t) async {
    final h = await openLibrary(t, withFiles: false);
    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    await t.tap(find.text('Start recording'));
    await settle(t);
    expect(
      find.text('Ready to record'),
      findsOneWidget,
      reason: 'switches to the Record tab',
    );
    expect(h.native.callsTo('start'), hasLength(1));
  });

  testWidgets('grid lists recordings with totals, durations and resolution', (
    t,
  ) async {
    await openLibrary(t);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('3 videos · 00:15 · 15.6 KB'), findsOneWidget);
    expect(find.textContaining('Alpha demo'), findsOneWidget);
    expect(find.textContaining('Bravo'), findsOneWidget);
    expect(find.text('00:09'), findsOneWidget);
    expect(find.text('1080p'), findsNWidgets(3));
  });

  testWidgets('search filters by name', (t) async {
    await openLibrary(t);
    await t.enterText(find.byType(TextField), 'demo');
    await settle(t);
    expect(find.textContaining('Alpha demo'), findsOneWidget);
    expect(find.textContaining('Charlie demo'), findsOneWidget);
    expect(find.textContaining('Bravo'), findsNothing);

    await t.enterText(find.byType(TextField), 'zzz');
    await settle(t);
    expect(find.text('No matches'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close_rounded));
    await settle(t);
    expect(find.textContaining('Bravo'), findsOneWidget);
  });

  testWidgets('favorites filter', (t) async {
    await openLibrary(
      t,
      prefs: {
        ...testPrefs,
        'favorites': ['Bravo.mp4'],
      },
    );
    expect(
      find.byIcon(Icons.favorite_rounded),
      findsOneWidget,
      reason: 'heart badge on the favorite card',
    );
    await t.tap(find.byIcon(Icons.favorite_border_rounded));
    await settle(t);
    expect(find.textContaining('Bravo'), findsOneWidget);
    expect(find.textContaining('Alpha'), findsNothing);
  });

  testWidgets('favorites filter empty state', (t) async {
    await openLibrary(t);
    await t.tap(find.byIcon(Icons.favorite_border_rounded));
    await settle(t);
    expect(find.textContaining('No favorites yet'), findsOneWidget);
  });

  testWidgets('sort options reorder the grid', (t) async {
    final h = await openLibrary(t);
    const names = ['Alpha', 'Bravo', 'Charlie'];
    expect(order(t, names), [
      'Bravo',
      'Charlie',
      'Alpha',
    ], reason: 'newest first by default');

    Future<void> sortBy(String label, LibrarySort expected) async {
      await t.tap(find.byIcon(Icons.sort_rounded));
      await settle(t);
      expect(find.text('Sort by'), findsOneWidget);
      await t.tap(find.text(label));
      await settle(t);
      expect(h.settings.sort, expected);
    }

    await sortBy('Oldest first', LibrarySort.oldest);
    expect(order(t, names), ['Alpha', 'Charlie', 'Bravo']);
    await sortBy('Longest', LibrarySort.longest);
    expect(order(t, names), ['Alpha', 'Charlie', 'Bravo']);
    await sortBy('Largest', LibrarySort.largest);
    expect(order(t, names), ['Bravo', 'Charlie', 'Alpha']);
    await sortBy('Newest first', LibrarySort.newest);
    expect(order(t, names), ['Bravo', 'Charlie', 'Alpha']);
  });

  testWidgets('long-press selects; select all; cancel selection', (t) async {
    await openLibrary(t);
    await t.longPress(find.textContaining('Bravo'));
    await settle(t);
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(find.textContaining('Alpha'));
    await settle(t);
    expect(find.text('2 selected'), findsOneWidget);
    await t.tap(find.textContaining('Alpha'));
    await settle(t);
    expect(find.text('1 selected'), findsOneWidget);
    await t.tap(find.byTooltip('Select all'));
    await settle(t);
    expect(find.text('3 selected'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close_rounded).first);
    await settle(t);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('bulk delete asks for confirmation and removes files', (t) async {
    final h = await openLibrary(t);
    await t.longPress(find.textContaining('Bravo'));
    await settle(t);
    await t.tap(find.textContaining('Charlie'));
    await settle(t);
    await t.tap(find.byTooltip('Delete'));
    await settle(t);
    expect(find.text('Delete 2 recordings?'), findsOneWidget);
    expect(find.textContaining('frees 13.7 KB'), findsOneWidget);

    // Cancel keeps everything.
    await t.tap(find.text('Cancel').last); // dialog is topmost
    await settle(t);
    expect(h.library.items, hasLength(3));

    await t.tap(find.byTooltip('Delete'));
    await settle(t);
    await t.tap(find.text('Delete'));
    await pumpReal(t);
    expect(h.library.items.map((r) => r.fileName), ['Alpha demo.mp4']);
    expect(h.native.dir.listSync().length, 1);
    expect(find.text('Deleted'), findsOneWidget);
  });
}
