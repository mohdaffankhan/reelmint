// "Stop when screen locks". The runner script watches logcat for the READY
// marker, then turns the screen off with `adb shell input keyevent KEYCODE_SLEEP`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelmint/services/recorder.dart';

import 'helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('recording stops and saves when the screen turns off', (t) async {
    final rec = Recorder();
    await rec.init();
    await t.pumpWidget(const Busy());

    final saved = Completer<RecordingSaved>();
    final sub = rec.events.listen((e) {
      if (e is RecordingSaved && !saved.isCompleted) saved.complete(e);
    });
    expect(await rec.start({...baseOptions, 'stopOnScreenOff': true}), isTrue);
    await waitUntil(() => rec.state == RecState.recording, what: 'recording');
    await sleep(1500);
    // ignore: avoid_print
    print('REELMINT_SCREEN_OFF_READY');

    final s = await saved.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () =>
          fail('recording did not stop after the screen turned off'),
    );
    await sub.cancel();
    expect(File(s.path).existsSync(), isTrue);
    expect(rec.state, isNot(RecState.recording));
    File(s.path).deleteSync();
    await t.pumpWidget(const SizedBox()); // stop the spinner before teardown
  });
}
