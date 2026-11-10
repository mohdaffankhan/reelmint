import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';

enum AudioSource {
  none('No audio', 'Silent video', Icons.volume_off_rounded),
  mic('Microphone', 'Your voice', Icons.mic_rounded),
  internal('Device audio', 'Apps & games', Icons.graphic_eq_rounded),
  both('Device + Mic', 'Commentary', Icons.surround_sound_rounded);

  const AudioSource(this.label, this.hint, this.icon);
  final String label, hint;
  final IconData icon;
}

enum RecOrientation {
  auto('Auto'),
  portrait('Portrait'),
  landscape('Landscape');

  const RecOrientation(this.label);
  final String label;
}

enum LibrarySort {
  newest('Newest first'),
  oldest('Oldest first'),
  longest('Longest'),
  largest('Largest');

  const LibrarySort(this.label);
  final String label;
}

class QualityPreset {
  const QualityPreset(
    this.name,
    this.icon,
    this.resolution,
    this.fps,
    this.bitrateMbps,
    this.audio,
  );
  final String name;
  final IconData icon;
  final int resolution, fps, bitrateMbps;
  final AudioSource audio;

  static const all = [
    QualityPreset(
      'Gaming',
      Icons.sports_esports_rounded,
      1080,
      60,
      16,
      AudioSource.internal,
    ),
    QualityPreset(
      'Tutorial',
      Icons.school_rounded,
      1080,
      30,
      8,
      AudioSource.mic,
    ),
    QualityPreset(
      'Cinematic',
      Icons.movie_filter_rounded,
      0,
      60,
      30,
      AudioSource.internal,
    ),
    QualityPreset(
      'Quick share',
      Icons.send_rounded,
      720,
      30,
      4,
      AudioSource.both,
    ),
  ];
}

/// Persistent user preferences.
class Settings extends ChangeNotifier {
  Settings._(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  static const resolutions = [0, 1440, 1080, 720, 480];
  static const frameRates = [24, 30, 60, 90, 120];
  static const countdowns = [0, 3, 5, 10];
  static const timeLimits = [0, 1, 5, 10, 15, 30, 60];

  T _get<T>(String k, T fallback) => (_p.get(k) as T?) ?? fallback;

  void _set(String k, Object v) {
    switch (v) {
      case bool b:
        _p.setBool(k, b);
      case int i:
        _p.setInt(k, i);
      case String s:
        _p.setString(k, s);
      case List<String> l:
        _p.setStringList(k, l);
    }
    notifyListeners();
  }

  // ---- video
  int get resolution => _get('resolution', 1080);
  set resolution(int v) => _set('resolution', v);

  int get fps => _get('fps', 60);
  set fps(int v) => _set('fps', v);

  /// 0 = automatic (scaled to resolution & frame rate).
  int get bitrateMbps => _get('bitrateMbps', 0);
  set bitrateMbps(int v) => _set('bitrateMbps', v);

  RecOrientation get orientation =>
      RecOrientation.values.byName(_get('orientation', 'auto'));
  set orientation(RecOrientation v) => _set('orientation', v.name);

  // ---- audio
  AudioSource get audio => AudioSource.values.byName(_get('audio', 'internal'));
  set audio(AudioSource v) => _set('audio', v.name);

  int get audioKbps => _get('audioKbps', 192);
  set audioKbps(int v) => _set('audioKbps', v);

  // ---- behaviour
  int get countdown => _get('countdown', 3);
  set countdown(int v) => _set('countdown', v);

  bool get floatingControls => _get('floatingControls', false);
  set floatingControls(bool v) => _set('floatingControls', v);

  bool get stopOnScreenOff => _get('stopOnScreenOff', true);
  set stopOnScreenOff(bool v) => _set('stopOnScreenOff', v);

  bool get minimizeOnStart => _get('minimizeOnStart', true);
  set minimizeOnStart(bool v) => _set('minimizeOnStart', v);

  // ---- facecam & automation
  bool get facecam => _get('facecam', false);
  set facecam(bool v) => _set('facecam', v);

  /// 's' | 'm' | 'l'
  String get facecamSize => _get('facecamSize', 'm');
  set facecamSize(String v) => _set('facecamSize', v);

  /// Auto-stop after this many minutes (0 = off).
  int get timeLimitMin => _get('timeLimitMin', 0);
  set timeLimitMin(int v) => _set('timeLimitMin', v);

  bool get shakeToStop => _get('shakeToStop', false);
  set shakeToStop(bool v) => _set('shakeToStop', v);

  // ---- privacy
  bool get appLock => _get('appLock', false);
  set appLock(bool v) => _set('appLock', v);

  // ---- appearance
  Accent get accent => Accent.values.byName(_get('accent', 'aurora'));
  set accent(Accent v) => _set('accent', v.name);

  ThemeMode get themeMode => ThemeMode.values.byName(_get('themeMode', 'dark'));
  set themeMode(ThemeMode v) => _set('themeMode', v.name);

  bool get haptics => _get('haptics', true);
  set haptics(bool v) => _set('haptics', v);

  // ---- app state
  bool get onboarded => _get('onboarded', false);
  set onboarded(bool v) => _set('onboarded', v);

  LibrarySort get sort => LibrarySort.values.byName(_get('sort', 'newest'));
  set sort(LibrarySort v) => _set('sort', v.name);

  Set<String> get favorites =>
      (_p.getStringList('favorites') ?? const []).toSet();
  void toggleFavorite(String name) {
    final f = favorites;
    f.contains(name) ? f.remove(name) : f.add(name);
    _set('favorites', f.toList());
  }

  void forgetFavorite(String name) {
    final f = favorites;
    if (f.remove(name)) _set('favorites', f.toList());
  }

  void renameFavorite(String from, String to) {
    final f = favorites;
    if (f.remove(from)) {
      f.add(to);
      _set('favorites', f.toList());
    }
  }

  void applyPreset(QualityPreset p) {
    _p.setInt('resolution', p.resolution);
    _p.setInt('fps', p.fps);
    _p.setInt('bitrateMbps', p.bitrateMbps);
    _p.setString('audio', p.audio.name);
    notifyListeners();
  }

  QualityPreset? get activePreset {
    for (final p in QualityPreset.all) {
      if (p.resolution == resolution &&
          p.fps == fps &&
          p.bitrateMbps == bitrateMbps &&
          p.audio == audio)
        return p;
    }
    return null;
  }

  String get resolutionLabel => resolution == 0 ? 'Native' : '${resolution}p';
  String get timeLimitLabel => timeLimitMin == 0 ? 'Off' : '$timeLimitMin min';

  /// Rough output size in MB per minute for a screen of [screenShort]×[screenLong] px,
  /// mirroring the Android encoder's automatic bitrate formula.
  double estimateMbPerMinute(int screenShort, int screenLong) {
    var short = screenShort.toDouble(), long = screenLong.toDouble();
    if (resolution > 0 && resolution < short) {
      long = long * resolution / short;
      short = resolution.toDouble();
    }
    final videoBps = bitrateMbps > 0
        ? bitrateMbps * 1e6
        : (short * long * fps * 0.11).clamp(2e6, 40e6);
    final audioBps = audio == AudioSource.none ? 0 : audioKbps * 1000;
    return (videoBps + audioBps) * 60 / 8 / (1024 * 1024);
  }

  String get bitrateLabel => bitrateMbps == 0 ? 'Auto' : '$bitrateMbps Mbps';

  /// Options map sent to the native recorder.
  Map<String, Object> toNative() => {
    'resolution': resolution,
    'fps': fps,
    'bitrate': bitrateMbps * 1000000,
    'audio': audio.name,
    'audioBitrate': audioKbps * 1000,
    'orientation': orientation.name,
    'countdown': countdown,
    'floatingControls': floatingControls,
    'stopOnScreenOff': stopOnScreenOff,
    'facecam': facecam,
    'facecamSize': facecamSize,
    'timeLimitSec': timeLimitMin * 60,
    'shakeToStop': shakeToStop,
  };
}
