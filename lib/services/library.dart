import 'dart:io';

import 'package:flutter/foundation.dart';

import 'recorder.dart';
import 'settings.dart';

class Recording {
  Recording(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;
  MediaInfo? info;

  String get path => file.path;
  String get fileName => file.uri.pathSegments.last;
  String get title {
    final n = fileName.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '');
    return n.startsWith('Reelmint_')
        ? 'Recording ${n.substring('Reelmint_'.length).replaceAll('_', ' · ')}'
        : n;
  }

  Duration get duration => info?.duration ?? Duration.zero;
}

/// Lists, caches and mutates recordings on disk.
class Library extends ChangeNotifier {
  Library(this._recorder, this._settings);
  final Recorder _recorder;
  final Settings _settings;

  List<Recording> _items = [];
  bool loading = true;
  final _infoCache = <String, MediaInfo>{};

  List<Recording> get items => _items;
  int get totalBytes => _items.fold(0, (a, r) => a + r.size);
  Duration get totalDuration =>
      _items.fold(Duration.zero, (a, r) => a + r.duration);

  /// Human-friendly folder name, e.g. "Movies › Reelmint" (visible in Gallery and Files).
  String get locationLabel {
    final d = _recorder.recordingsDir;
    if (d == null) return '—';
    if (d.contains('/Android/data/')) return 'App storage';
    final parts = d.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
    return parts.length >= 2 ? '${parts[parts.length - 2]} › ${parts.last}' : d;
  }

  /// Full folder path as a person would read it, e.g. "Internal storage › Movies › Reelmint".
  String get locationPath {
    final d = _recorder.recordingsDir;
    if (d == null) return '—';
    final shown = d.replaceFirst(
      RegExp(r'^/storage/emulated/\d+'),
      'Internal storage',
    );
    return shown.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).join(' › ');
  }

  Directory? get _dir => _recorder.recordingsDir == null
      ? null
      : Directory(_recorder.recordingsDir!);

  int _generation =
      0; // bumped by deletes so an in-flight refresh can't resurrect a file

  Future<void> refresh() async {
    final gen = ++_generation;
    final dir = _dir;
    if (dir == null || !await dir.exists()) {
      _items = [];
      loading = false;
      notifyListeners();
      return;
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.mp4'))
        .cast<File>()
        .toList();
    final next = <Recording>[];
    for (final f in files) {
      final FileStat st;
      try {
        st = await f.stat();
      } catch (_) {
        continue;
      }
      if (st.type == FileSystemEntityType.notFound || st.size < 1024)
        continue; // gone / still being written
      final r = Recording(f, st.size, st.modified);
      final key = '${f.path}@${st.modified.millisecondsSinceEpoch}';
      r.info = _infoCache[key];
      next.add(r);
    }
    if (gen != _generation)
      return; // a newer refresh (or a delete) superseded this one
    _items = next;
    _sort();
    loading = false;
    notifyListeners();

    // Lazily fill media info (duration / resolution).
    for (final r in next.where((r) => r.info == null)) {
      try {
        r.info = await _recorder.info(r.path);
        _infoCache['${r.path}@${r.modified.millisecondsSinceEpoch}'] = r.info!;
      } catch (_) {
        r.info = MediaInfo.empty;
      }
    }
    _sort();
    notifyListeners();
  }

  void _sort() {
    switch (_settings.sort) {
      case LibrarySort.newest:
        _items.sort((a, b) => b.modified.compareTo(a.modified));
      case LibrarySort.oldest:
        _items.sort((a, b) => a.modified.compareTo(b.modified));
      case LibrarySort.longest:
        _items.sort((a, b) => b.duration.compareTo(a.duration));
      case LibrarySort.largest:
        _items.sort((a, b) => b.size.compareTo(a.size));
    }
  }

  void resort() {
    _sort();
    notifyListeners();
  }

  Recording? byPath(String path) {
    for (final r in _items) {
      if (r.path == path) return r;
    }
    return null;
  }

  /// Deletes recordings by path (callers may hold stale [Recording] objects from before a
  /// refresh). Returns how many could not be deleted.
  Future<int> delete(Iterable<Recording> recs) async {
    final paths = {for (final r in recs) r.path};
    if (paths.isEmpty) return 0;
    _generation++; // drop any refresh already in flight
    final gone = <String>{};
    for (final p in paths) {
      try {
        await File(p).delete();
      } on PathNotFoundException {
        // already gone
      } catch (_) {}
      if (!File(p).existsSync()) {
        gone.add(p);
        Thumbs.instance.evict(p);
        _settings.forgetFavorite(p.split(Platform.pathSeparator).last);
      }
    }
    _items = _items.where((r) => !gone.contains(r.path)).toList();
    notifyListeners();
    await _recorder.scan(gone.toList()); // update Gallery / Photos
    return paths.length - gone.length;
  }

  /// Renames a recording. Returns the new recording, or throws if the name is taken.
  Future<Recording> rename(Recording r, String newTitle) async {
    final safe = newTitle.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safe.isEmpty) throw ArgumentError('Name cannot be empty');
    final target = File(
      '${r.file.parent.path}${Platform.pathSeparator}$safe.mp4',
    );
    if (await target.exists())
      throw StateError('A recording with that name already exists');
    final moved = await r.file.rename(target.path);
    _settings.renameFavorite(r.fileName, '$safe.mp4');
    Thumbs.instance.evict(r.path);
    await _recorder.scan([r.path, moved.path]);
    await refresh();
    return byPath(moved.path) ?? Recording(moved, r.size, r.modified);
  }
}

/// Small LRU of decoded thumbnail bytes with in-flight de-duplication.
class Thumbs {
  Thumbs._();
  static final instance = Thumbs._();
  late Recorder recorder;

  final _cache = <String, Uint8List>{}; // insertion-ordered: oldest first
  final _inflight = <String, Future<Uint8List?>>{};
  static const _max = 120;

  Future<Uint8List?> get(String path, {int atMs = 0, int width = 360}) {
    final key = '$path#$atMs#$width';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return SynchronousFuture(hit);
    }
    return _inflight[key] ??= recorder
        .thumbnail(path, atMs: atMs, maxWidth: width)
        .then((b) {
          _inflight.remove(key);
          if (b != null) {
            _cache[key] = b;
            if (_cache.length > _max) _cache.remove(_cache.keys.first);
          }
          return b;
        })
        .catchError((_) {
          _inflight.remove(key);
          return null;
        });
  }

  Uint8List? peek(String path, {int atMs = 0, int width = 360}) =>
      _cache['$path#$atMs#$width'];

  void evict(String path) =>
      _cache.removeWhere((k, _) => k.startsWith('$path#'));
}
