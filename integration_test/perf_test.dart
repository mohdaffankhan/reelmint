// Smoothness check on a real phone: the app must run at the panel's top refresh rate and
// scrolling Home / Library / Settings must stay within the frame budget.
// Run with:  dart run tool/device_test.dart --skip-host --only=perf_test
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelmint/main.dart' as app;
import 'package:reelmint/services/recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('scrolling is smooth at the display\'s top refresh rate', (
    t,
  ) async {
    // A library worth scrolling.
    final rec = Recorder();
    await rec.init();
    final created = <String>[];
    addTearDown(() {
      for (final p in created) {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      }
    });
    await t.pumpWidget(const Motion());
    for (var i = 0; i < 8; i++) {
      await record(
        rec,
        cleanup: created,
        length: const Duration(milliseconds: 1500),
      );
    }
    rec.dispose();
    await sleep(
      4000,
    ); // let the encoders wind down and the GPU settle before measuring

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('onboarded', true);
    await prefs.setBool('haptics', false);

    final caps = Recorder();
    await caps.init();
    final hz = PlatformDispatcher.instance.displays.first.refreshRate;
    // ignore: avoid_print
    print(
      'PERF display ${hz.toStringAsFixed(0)} Hz (panel max ${caps.caps.maxFps})',
    );
    expect(
      hz,
      greaterThanOrEqualTo(caps.caps.maxFps - 2),
      reason: 'app should run at the panel\'s fastest mode',
    );

    final timings = <FrameTiming>[];
    final results =
        <
          String,
          ({int frames, int rasterP90, double jankPct, double budget, int p50})
        >{};
    void collect(List<FrameTiming> f) => timings.addAll(f);

    Future<void> scrollTab(String? key, String name) async {
      if (key != null) await t.tap(find.byKey(ValueKey(key)));
      await sleep(700);
      await t.pump();
      final scrollable = find.byType(Scrollable).hitTestable().first;
      timings.clear();
      SchedulerBinding.instance.addTimingsCallback(collect);
      for (var i = 0; i < 3; i++) {
        await t.fling(scrollable, const Offset(0, -900), 2500);
        await sleep(900);
        await t.fling(scrollable, const Offset(0, 900), 2500);
        await sleep(900);
      }
      await sleep(400);
      SchedulerBinding.instance.removeTimingsCallback(collect);

      final budgetUs = 1e6 / hz;
      final total =
          timings
              .map(
                (f) =>
                    f.buildDuration.inMicroseconds +
                    f.rasterDuration.inMicroseconds,
              )
              .toList()
            ..sort();
      final raster =
          timings.map((f) => f.rasterDuration.inMicroseconds).toList()..sort();
      int pct(List<int> l, double p) =>
          l.isEmpty ? 0 : l[((l.length - 1) * p).round()];
      final janky = timings
          .where(
            (f) =>
                f.rasterDuration.inMicroseconds > budgetUs ||
                f.buildDuration.inMicroseconds > budgetUs,
          )
          .length;
      final jankPct = timings.isEmpty ? 0 : 100 * janky / timings.length;
      // ignore: avoid_print
      print(
        'PERF $name: ${timings.length} frames, p50 ${pct(total, .5) / 1000}ms, p90 ${pct(total, .9) / 1000}ms, '
        'raster p90 ${pct(raster, .9) / 1000}ms, over budget ${jankPct.toStringAsFixed(1)}% (budget ${(budgetUs / 1000).toStringAsFixed(1)}ms)',
      );
      results[name] = (
        frames: timings.length,
        rasterP90: pct(raster, .9),
        jankPct: jankPct.toDouble(),
        budget: budgetUs,
        p50: pct(total, .5),
      );
    }

    // Baseline: the cheapest possible screen (plain list, no styling) on this phone.
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 300,
            itemBuilder: (_, i) => ListTile(
              title: Text('Row $i'),
              subtitle: const Text('baseline'),
            ),
          ),
        ),
      ),
    );
    await scrollTab(null, 'Baseline');
    await app.main();
    await sleep(2000);
    await t.pump();

    await scrollTab('nav-0', 'Home');
    await scrollTab('nav-1', 'Library');
    await scrollTab('nav-2', 'Settings');

    // At the panel's 120 Hz every frame has 8.3 ms. Typical frames must fit easily and the
    // slow tail must stay small. (The bare-list baseline is printed for context.)
    results.remove('Baseline');
    for (final MapEntry(key: name, value: r) in results.entries) {
      expect(r.frames, greaterThan(30), reason: '$name: frames were produced');
      expect(
        r.p50,
        lessThan(r.budget * 0.8),
        reason: '$name: typical frame well within one refresh',
      );
      expect(
        r.rasterP90,
        lessThan(r.budget),
        reason: '$name: 90% of frames rasterise within one refresh',
      );
      expect(
        r.jankPct,
        lessThan(10),
        reason: '$name: fewer than 10% slow frames',
      );
    }

    await t.pumpWidget(const SizedBox());
    await sleep(300);
  });
}
