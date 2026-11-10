import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/library.dart';
import 'package:reelmint/services/recorder.dart';
import 'package:reelmint/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late Recorder recorder;
  late Settings settings;
  late Library lib;

  setUp(() async {
    native = FakeNative()..install();
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    recorder = Recorder();
    await recorder.init();
    Thumbs.instance.recorder = recorder;
    lib = Library(recorder, settings);
  });

  tearDown(() {
    recorder.dispose();
    native.uninstall();
  });

  test('save location is shown the way people read it', () {
    recorder.recordingsDir = '/storage/emulated/0/Movies/Reelmint';
    expect(lib.locationPath, 'Internal storage › Movies › Reelmint');
    expect(lib.locationLabel, 'Movies › Reelmint');
    recorder.recordingsDir = '/storage/emulated/0/Android/data/io.github.mohdaffankhan.reelmint/files/Movies/recordings';
    expect(lib.locationLabel, 'App storage');
  });

  test('empty directory', () async {
    await lib.refresh();
    expect(lib.loading, isFalse);
    expect(lib.items, isEmpty);
    expect(lib.totalBytes, 0);
  });

  test('missing directory is handled', () async {
    recorder.recordingsDir = '${native.dir.path}/does-not-exist';
    await lib.refresh();
    expect(lib.items, isEmpty);
  });

  test('lists only mp4 files above 1 KB and loads media info', () async {
    native.addRecording('Reelmint_20260101_100000.mp4', durationMs: 3000);
    native.addRecording('Clip.MP4', durationMs: 7000);
    File('${native.dir.path}/notes.txt').writeAsStringSync('x' * 5000);
    File('${native.dir.path}/partial.mp4').writeAsBytesSync([1, 2, 3]);

    await lib.refresh();
    expect(lib.items.map((r) => r.fileName).toSet(), {
      'Reelmint_20260101_100000.mp4',
      'Clip.MP4',
    });
    expect(lib.items.every((r) => r.info != null), isTrue);
    expect(lib.totalBytes, 8192);
    expect(lib.totalDuration, const Duration(seconds: 10));
  });

  test('titles are humanised for Reelmint_ files', () async {
    native.addRecording('Reelmint_20260101_100000.mp4');
    native.addRecording('My demo.mp4');
    await lib.refresh();
    final titles = lib.items.map((r) => r.title).toSet();
    expect(titles, {'Recording 20260101 · 100000', 'My demo'});
  });

  test('sorting: newest, oldest, longest, largest', () async {
    native.addRecording(
      'a.mp4',
      bytes: 2000,
      modified: DateTime(2026, 1, 1),
      durationMs: 9000,
    );
    native.addRecording(
      'b.mp4',
      bytes: 9000,
      modified: DateTime(2026, 1, 3),
      durationMs: 1000,
    );
    native.addRecording(
      'c.mp4',
      bytes: 5000,
      modified: DateTime(2026, 1, 2),
      durationMs: 5000,
    );
    await lib.refresh();

    List<String> names() => lib.items.map((r) => r.fileName).toList();
    expect(names(), ['b.mp4', 'c.mp4', 'a.mp4']);
    settings.sort = LibrarySort.oldest;
    lib.resort();
    expect(names(), ['a.mp4', 'c.mp4', 'b.mp4']);
    settings.sort = LibrarySort.longest;
    lib.resort();
    expect(names(), ['a.mp4', 'c.mp4', 'b.mp4']);
    settings.sort = LibrarySort.largest;
    lib.resort();
    expect(names(), ['b.mp4', 'c.mp4', 'a.mp4']);
  });

  test('byPath', () async {
    final f = native.addRecording('a.mp4');
    await lib.refresh();
    expect(lib.byPath(f.path)?.fileName, 'a.mp4');
    expect(lib.byPath('/nope'), isNull);
  });

  test('delete removes files and items', () async {
    final a = native.addRecording('a.mp4');
    final b = native.addRecording('b.mp4');
    await lib.refresh();
    await lib.delete([lib.byPath(a.path)!]);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
    expect(lib.items, hasLength(1));
    await lib.delete(lib.items);
    expect(lib.items, isEmpty);
    expect(b.existsSync(), isFalse);
  });

  test(
    'rename moves the file, sanitises the name and keeps favorite',
    () async {
      native.addRecording('old.mp4');
      await lib.refresh();
      settings.toggleFavorite('old.mp4');
      final renamed = await lib.rename(lib.items.single, '  my: clip?  ');
      expect(renamed.fileName, 'my_ clip_.mp4');
      expect(File('${native.dir.path}/old.mp4').existsSync(), isFalse);
      expect(renamed.file.existsSync(), isTrue);
      expect(settings.favorites, {'my_ clip_.mp4'});
    },
  );

  test('delete works with a stale Recording from before a refresh', () async {
    native.addRecording('Reelmint_a.mp4');
    native.addRecording('Reelmint_b.mp4');
    await lib.refresh();
    final stale = lib.items.firstWhere((r) => r.fileName == 'Reelmint_a.mp4');
    settings.toggleFavorite('Reelmint_a.mp4');
    await lib
        .refresh(); // e.g. app resumed while the player was open: new objects
    expect(identical(lib.byPath(stale.path), stale), isFalse);

    expect(await lib.delete([stale]), 0);
    expect(lib.items.map((r) => r.fileName), ['Reelmint_b.mp4']);
    expect(File(stale.path).existsSync(), isFalse);
    expect(settings.favorites, isEmpty, reason: 'favorite forgotten');
    expect(native.callsTo('scan').single.arguments, {
      'paths': [stale.path],
    }, reason: 'Gallery is told the file is gone');
  });

  test(
    'a refresh that started before a delete cannot bring the file back',
    () async {
      native.addRecording('Reelmint_a.mp4');
      await lib.refresh();
      final r = lib.items.single;
      final pending = lib.refresh(); // listing in flight
      await lib.delete([r]);
      await pending;
      expect(lib.items, isEmpty);
    },
  );

  test('rename rejects empty and duplicate names', () async {
    native.addRecording('a.mp4');
    native.addRecording('b.mp4');
    await lib.refresh();
    final a = lib.items.firstWhere((r) => r.fileName == 'a.mp4');
    expect(() => lib.rename(a, '   '), throwsArgumentError);
    expect(() => lib.rename(a, 'b'), throwsStateError);
  });

  test('thumbnail cache de-duplicates and caches results', () async {
    var calls = 0;
    native.overrides['thumbnail'] = (_) {
      calls++;
      return null;
    };
    await Future.wait([
      Thumbs.instance.get('/x.mp4'),
      Thumbs.instance.get('/x.mp4'),
    ]);
    expect(calls, 1, reason: 'concurrent requests share one native call');

    native.overrides['thumbnail'] = (_) {
      calls++;
      return Uint8List.fromList([0xFF, 0xD8, 1]);
    };
    final b = await Thumbs.instance.get('/y.mp4', atMs: 5);
    expect(b, isNotNull);
    expect(Thumbs.instance.peek('/y.mp4', atMs: 5), b);
    await Thumbs.instance.get('/y.mp4', atMs: 5);
    expect(calls, 2, reason: 'second lookup is served from cache');
    Thumbs.instance.evict('/y.mp4');
    expect(Thumbs.instance.peek('/y.mp4', atMs: 5), isNull);
  });
}
