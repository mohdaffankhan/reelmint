// Runs every Reelmint test: host unit/widget tests, then on-device integration tests.
//
//   dart run tool/device_test.dart                  # everything
//   dart run tool/device_test.dart --skip-host      # phone only
//   dart run tool/device_test.dart --only=app_flow_test
//   dart run tool/device_test.dart --device=RZCT41KK1AY
//
// While the device suites run, this script:
//  * keeps RECORD_AUDIO / POST_NOTIFICATIONS granted and SYSTEM_ALERT_WINDOW /
//    PROJECT_MEDIA (capture without the consent dialog) allowed — `flutter test`
//    may reinstall the app, so grants are re-applied every couple of seconds;
//  * taps the system screen-capture / permission dialog if one still appears;
//  * for screen_off_test, turns the screen off when the test logs its READY marker.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const pkg = 'io.github.mohdaffankhan.reelmint';
const suites = [
  'recorder_engine_test',
  'features_test',
  'app_flow_test',
  'perf_test',
  'screen_off_test',
];

late String device;
late int sdk;

Future<void> main(List<String> args) async {
  String? arg(String name) => args
      .where((a) => a.startsWith('--$name='))
      .map((a) => a.split('=').last)
      .firstOrNull;
  final skipHost = args.contains('--skip-host');
  final only = arg('only');
  final results = <String, bool>{};

  if (!skipHost && only == null) {
    _title('Host unit + widget tests');
    results['host (test/)'] = await _run('flutter', ['test']) == 0;
  }

  device =
      arg('device') ??
      await _firstDevice() ??
      _die('No Android device found (adb devices).');
  sdk = int.parse(
    (await _adbOut(['shell', 'getprop', 'ro.build.version.sdk'])).trim(),
  );
  final model = (await _adbOut(['shell', 'getprop', 'ro.product.model']))
      .trim();
  _title('Device: $model (API $sdk) [$device]');
  if (sdk < 29) _die('Reelmint needs Android 10 (API 29)+');

  await _adb(['shell', 'svc', 'power', 'stayon', 'usb']);
  await _wake();
  await _grant();
  final grantTimer = Timer.periodic(
    const Duration(seconds: 2),
    (_) => _grant(),
  );
  final tapTimer = Timer.periodic(
    const Duration(milliseconds: 900),
    (_) => _tapConsentDialog(),
  );

  try {
    for (final s in only == null ? suites : [only]) {
      if (!File('integration_test/$s.dart').existsSync()) continue;
      _title('integration_test/$s.dart');
      await _wake();
      // perf_test runs as a profile build (release-speed engine) so frame times are realistic.
      final args = s == 'perf_test'
          ? [
              'drive',
              '--profile',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/$s.dart',
              '-d',
              device,
            ]
          : [
              'test',
              'integration_test/$s.dart',
              '-d',
              device,
              '--reporter',
              'expanded',
            ];
      results[s] = await _run('flutter', args, onLine: _onTestOutput) == 0;
    }
  } finally {
    grantTimer.cancel();
    tapTimer.cancel();
    await _adb(['shell', 'svc', 'power', 'stayon', 'false']);
  }

  _title('Summary');
  for (final e in results.entries) {
    stdout.writeln(
      '  ${e.value ? '\x1B[32mPASS' : '\x1B[31mFAIL'}\x1B[0m  ${e.key}',
    );
  }
  exit(results.values.every((v) => v) ? 0 : 1);
}

// ---------------------------------------------------------------- helpers

Never _die(String msg) {
  stderr.writeln(msg);
  exit(2);
}

void _title(String t) => stdout.writeln('\n\x1B[36m=== $t ===\x1B[0m');

Future<int> _run(
  String exe,
  List<String> args, {
  void Function(String line)? onLine,
}) async {
  if (onLine == null) {
    final p = await Process.start(
      exe,
      args,
      runInShell: true,
      mode: ProcessStartMode.inheritStdio,
    );
    return p.exitCode;
  }
  final p = await Process.start(exe, args, runInShell: true);
  final done = [
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach((
      l,
    ) {
      stdout.writeln(l);
      onLine(l);
    }),
    p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(stderr.writeln),
  ];
  final code = await p.exitCode;
  await Future.wait(done);
  return code;
}

/// Device-side tests can ask the runner to do things by printing markers.
void _onTestOutput(String line) {
  if (line.contains('REELMINT_START_CAPTURE_ACTIVITY')) {
    stdout.writeln('[runner] launching the "Record" shortcut activity');
    _adb(['shell', 'am', 'start', '-n', '$pkg/.CaptureActivity']);
  }
  // REELMINT_INPUT swipe x1 y1 x2 y2 ms  |  REELMINT_INPUT tap x y  → real touch events
  final input = RegExp(r'REELMINT_INPUT ((?:swipe|tap)(?: \d+)+)')
      .firstMatch(line);
  if (input != null) {
    stdout.writeln('[runner] input ${input.group(1)}');
    _adb(['shell', 'input', ...input.group(1)!.split(' ')]);
  }
  if (line.contains('REELMINT_TILE_CLICK')) {
    stdout.writeln('[runner] clicking the Quick Settings tile');
    () async {
      const tile = '$pkg/.RecordTileService';
      await _adb(['shell', 'cmd', 'statusbar', 'add-tile', tile]);
      await _adb(['shell', 'cmd', 'statusbar', 'click-tile', tile]);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _adb(['shell', 'cmd', 'statusbar', 'collapse']);
    }();
  }
  if (line.contains('REELMINT_SCREEN_OFF_READY')) {
    stdout.writeln('[runner] READY marker seen — turning the screen off');
    () async {
      await _adb(['shell', 'input', 'keyevent', 'KEYCODE_SLEEP']);
      await Future<void>.delayed(const Duration(seconds: 4));
      await _wake();
    }();
  }
}

Future<String?> _firstDevice() async {
  final r = await Process.run('adb', ['devices'], runInShell: true);
  for (final line in LineSplitter.split(r.stdout as String)) {
    final m = RegExp(r'^(\S+)\s+device$').firstMatch(line.trim());
    if (m != null) return m.group(1);
  }
  return null;
}

Future<ProcessResult> _adb(List<String> args) =>
    Process.run('adb', ['-s', device, ...args], runInShell: true).timeout(
      const Duration(seconds: 20),
      onTimeout: () => ProcessResult(0, 1, '', 'timeout'),
    );

Future<String> _adbOut(List<String> args) async =>
    (await _adb(args)).stdout as String;

Future<void> _wake() async {
  await _adb(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
  await _adb(['shell', 'wm', 'dismiss-keyguard']);
}

var _granting = false;
Future<void> _grant() async {
  if (_granting) return;
  _granting = true;
  try {
    final perms = [
      'RECORD_AUDIO',
      'CAMERA',
      if (sdk >= 33) 'POST_NOTIFICATIONS',
    ];
    await _adb([
      'shell',
      [
        for (final p in perms)
          'pm grant $pkg android.permission.$p 2>/dev/null',
        'appops set $pkg SYSTEM_ALERT_WINDOW allow',
        'appops set $pkg PROJECT_MEDIA allow',
      ].join('; '),
    ]);
  } finally {
    _granting = false;
  }
}

var _tapping = false;
final _consentLabels = RegExp(
  r'text="(Start now|Start recording|Start|START NOW|Allow|While using the app|Only this time|Share screen|Entire screen|Next)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
);

/// Fallback when appops does not suppress the MediaProjection / permission dialog.
Future<void> _tapConsentDialog() async {
  if (_tapping) return;
  _tapping = true;
  try {
    final focus = await _adbOut([
      'shell',
      'dumpsys',
      'window',
      '|',
      'grep',
      'mCurrentFocus',
    ]);
    if (!RegExp(
      r'systemui|permissioncontroller|MediaProjection',
      caseSensitive: false,
    ).hasMatch(focus))
      return;
    final xml = await _adbOut(['exec-out', 'uiautomator', 'dump', '/dev/tty']);
    final matches = _consentLabels.allMatches(xml).toList();
    if (matches.isEmpty) return;
    final g = matches.last;
    final x = (int.parse(g.group(2)!) + int.parse(g.group(4)!)) ~/ 2;
    final y = (int.parse(g.group(3)!) + int.parse(g.group(5)!)) ~/ 2;
    stdout.writeln('[runner] tapping "${g.group(1)}" on system dialog');
    await _adb(['shell', 'input', 'tap', '$x', '$y']);
  } finally {
    _tapping = false;
  }
}
