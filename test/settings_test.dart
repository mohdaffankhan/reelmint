import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/app/theme.dart';
import 'package:reelmint/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Settings s;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    s = await Settings.load();
  });

  test('defaults', () {
    expect(s.resolution, 1080);
    expect(s.fps, 60);
    expect(s.bitrateMbps, 0);
    expect(s.bitrateLabel, 'Auto');
    expect(s.orientation, RecOrientation.auto);
    expect(s.audio, AudioSource.internal);
    expect(s.audioKbps, 192);
    expect(s.countdown, 3);
    expect(s.floatingControls, isFalse);
    expect(s.stopOnScreenOff, isTrue);
    expect(s.minimizeOnStart, isTrue);
    expect(s.themeMode, ThemeMode.dark);
    expect(s.haptics, isTrue);
    expect(s.onboarded, isFalse);
    expect(s.sort, LibrarySort.newest);
    expect(s.favorites, isEmpty);
    expect(s.facecam, isFalse);
    expect(s.facecamSize, 'm');
    expect(s.timeLimitMin, 0);
    expect(s.timeLimitLabel, 'Off');
    expect(s.shakeToStop, isFalse);
    expect(s.appLock, isFalse);
    expect(s.accent, Accent.aurora);
  });

  test('new feature settings persist and reach the native options', () async {
    s
      ..facecam = true
      ..facecamSize = 'l'
      ..timeLimitMin = 15
      ..shakeToStop = true
      ..appLock = true
      ..accent = Accent.ocean;
    final reloaded = await Settings.load();
    expect(reloaded.facecam, isTrue);
    expect(reloaded.facecamSize, 'l');
    expect(reloaded.timeLimitMin, 15);
    expect(reloaded.timeLimitLabel, '15 min');
    expect(reloaded.shakeToStop, isTrue);
    expect(reloaded.appLock, isTrue);
    expect(reloaded.accent, Accent.ocean);
    final n = reloaded.toNative();
    expect(n['facecam'], isTrue);
    expect(n['facecamSize'], 'l');
    expect(n['timeLimitSec'], 900);
    expect(n['shakeToStop'], isTrue);
  });

  test('size estimate follows resolution, fps, bitrate and audio', () {
    s
      ..resolution = 1080
      ..fps = 60
      ..bitrateMbps = 0
      ..audio = AudioSource.none;
    final auto1080 = s.estimateMbPerMinute(1080, 2400);
    // 1080×2400×60×0.11 ≈ 17.1 Mbps → ≈ 122 MB/min
    expect(auto1080, closeTo(122, 3));
    s.resolution = 720;
    expect(s.estimateMbPerMinute(1080, 2400), lessThan(auto1080));
    s.bitrateMbps = 8;
    expect(
      s.estimateMbPerMinute(1080, 2400),
      closeTo(57.2, 0.5),
    ); // 8 Mbps = 57.2 MB/min
    s.audio = AudioSource.mic;
    expect(s.estimateMbPerMinute(1080, 2400), greaterThan(57.2));
  });

  test('every setting persists and notifies', () async {
    var notified = 0;
    s.addListener(() => notified++);
    s
      ..resolution = 720
      ..fps = 120
      ..bitrateMbps = 24
      ..orientation = RecOrientation.landscape
      ..audio = AudioSource.both
      ..audioKbps = 256
      ..countdown = 10
      ..floatingControls = true
      ..stopOnScreenOff = false
      ..minimizeOnStart = false
      ..themeMode = ThemeMode.light
      ..haptics = false
      ..onboarded = true
      ..sort = LibrarySort.largest;
    expect(notified, 14);

    final reloaded = await Settings.load();
    expect(reloaded.resolution, 720);
    expect(reloaded.resolutionLabel, '720p');
    expect(reloaded.fps, 120);
    expect(reloaded.bitrateLabel, '24 Mbps');
    expect(reloaded.orientation, RecOrientation.landscape);
    expect(reloaded.audio, AudioSource.both);
    expect(reloaded.audioKbps, 256);
    expect(reloaded.countdown, 10);
    expect(reloaded.floatingControls, isTrue);
    expect(reloaded.stopOnScreenOff, isFalse);
    expect(reloaded.minimizeOnStart, isFalse);
    expect(reloaded.themeMode, ThemeMode.light);
    expect(reloaded.haptics, isFalse);
    expect(reloaded.onboarded, isTrue);
    expect(reloaded.sort, LibrarySort.largest);
  });

  test('native label for resolution 0', () {
    s.resolution = 0;
    expect(s.resolutionLabel, 'Native');
  });

  test('toNative maps every option the Android recorder reads', () {
    s
      ..resolution = 1440
      ..fps = 90
      ..bitrateMbps = 16
      ..audio = AudioSource.mic
      ..audioKbps = 128
      ..orientation = RecOrientation.portrait
      ..countdown = 5
      ..floatingControls = true
      ..stopOnScreenOff = false;
    expect(s.toNative(), {
      'resolution': 1440,
      'fps': 90,
      'bitrate': 16000000,
      'audio': 'mic',
      'audioBitrate': 128000,
      'orientation': 'portrait',
      'countdown': 5,
      'floatingControls': true,
      'stopOnScreenOff': false,
      'facecam': false,
      'facecamSize': 'm',
      'timeLimitSec': 0,
      'shakeToStop': false,
    });
  });

  test('presets apply and are detected', () {
    expect(s.activePreset, isNull);
    for (final p in QualityPreset.all) {
      s.applyPreset(p);
      expect(s.resolution, p.resolution);
      expect(s.fps, p.fps);
      expect(s.bitrateMbps, p.bitrateMbps);
      expect(s.audio, p.audio);
      expect(s.activePreset, same(p));
    }
    s.fps = 24;
    expect(s.activePreset, isNull);
  });

  test('favorites toggle and follow renames', () {
    s.toggleFavorite('a.mp4');
    s.toggleFavorite('b.mp4');
    expect(s.favorites, {'a.mp4', 'b.mp4'});
    s.toggleFavorite('a.mp4');
    expect(s.favorites, {'b.mp4'});
    s.renameFavorite('b.mp4', 'c.mp4');
    expect(s.favorites, {'c.mp4'});
    s.renameFavorite('zzz.mp4', 'y.mp4'); // not a favorite: no-op
    expect(s.favorites, {'c.mp4'});
  });
}
