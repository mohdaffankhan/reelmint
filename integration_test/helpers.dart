import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelmint/services/recorder.dart';

/// Base options: small, fast, deterministic. Tests override what they verify.
const baseOptions = <String, Object>{
  'resolution': 720,
  'fps': 30,
  'bitrate': 0,
  'audio': 'none',
  'audioBitrate': 128000,
  'orientation': 'auto',
  'countdown': 0,
  'floatingControls': false,
  'stopOnScreenOff': false,
};

class Take {
  Take(this.path, this.info, this.states, this.reportedDuration);
  final String path;
  final MediaInfo info;
  final List<RecState> states;
  final Duration reportedDuration;
  String get name => path.split(Platform.pathSeparator).last;
  int get shortSide => math.min(info.width, info.height);
  int get longSide => math.max(info.width, info.height);
  double get fps => info.duration.inMilliseconds == 0
      ? 0
      : info.frameCount / (info.duration.inMilliseconds / 1000);
}

/// Something that keeps the screen changing (so the encoder always has new frames).
class Busy extends StatelessWidget {
  const Busy({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      backgroundColor: Color(0xFF101018),
      body: Center(
        child: SizedBox(
          width: 220,
          height: 220,
          child: CircularProgressIndicator(strokeWidth: 14),
        ),
      ),
    ),
  );
}

/// Full-screen, constantly changing content (like gameplay or video), so encoders
/// actually spend their bitrate. Use for editor tests that compare file sizes.
class Motion extends StatefulWidget {
  const Motion({super.key});
  @override
  State<Motion> createState() => _MotionState();
}

class _MotionState extends State<Motion> with SingleTickerProviderStateMixin {
  late final _ticker = createTicker((_) => setState(() => _frame++))..start();
  int _frame = 0;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: GridView.count(
        crossAxisCount: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 12 * 26; i++)
            ColoredBox(
              color: HSVColor.fromAHSV(
                1,
                ((i * 37 + _frame * (7 + i % 11)) % 360).toDouble(),
                0.8,
                0.5 + (i * 13 + _frame) % 50 / 100,
              ).toColor(),
              child: Center(
                child: Text(
                  '${(i * _frame) % 97}',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> waitUntil(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 20),
  required String what,
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout)
      fail('Timed out after ${timeout.inSeconds}s waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Records with [options] and returns the finished take.
/// [during] runs while recording (defaults to waiting [length]).
Future<Take> record(
  Recorder rec, {
  Map<String, Object> options = const {},
  Duration length = const Duration(seconds: 3),
  Future<void> Function()? during,
  List<String>? cleanup,
}) async {
  await waitUntil(
    () => rec.state == RecState.idle,
    what: 'recorder idle before start',
  );
  final states = <RecState>[];
  void track() {
    if (states.isEmpty || states.last != rec.state) states.add(rec.state);
  }

  rec.addListener(track);
  final errors = <String>[];
  final saved = Completer<RecordingSaved>();
  final sub = rec.events.listen((e) {
    if (e is RecordingSaved && !saved.isCompleted) saved.complete(e);
    if (e is RecorderMessage && e.isError) errors.add(e.message);
  });
  try {
    final ok = await rec.start({...baseOptions, ...options});
    expect(
      ok,
      isTrue,
      reason: 'capture consent was not granted — run tool/run_device_tests.ps1 so appops allow it',
    );
    await waitUntil(
      () => rec.state == RecState.recording || errors.isNotEmpty,
      what: 'recording to start',
    );
    if (errors.isNotEmpty) fail('Recorder error: ${errors.join('; ')}');
    if (during != null) {
      await during();
    } else {
      await Future<void>.delayed(length);
    }
    await rec.stop();
    final s = await saved.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        fail('No saved event. Errors: ${errors.join('; ')}');
      },
    );
    await waitUntil(
      () => rec.state == RecState.idle,
      what: 'recorder idle after stop',
    );
    cleanup?.add(s.path);
    expect(File(s.path).existsSync(), isTrue, reason: 'output file exists');
    expect(
      File(s.path).lengthSync(),
      greaterThan(10 * 1024),
      reason: 'output file has content',
    );
    final info = await rec.info(s.path);
    return Take(s.path, info, states, s.duration);
  } finally {
    rec.removeListener(track);
    await sub.cancel();
  }
}

Matcher closeToMs(int ms, int tolerance) =>
    inInclusiveRange(ms - tolerance, ms + tolerance);
