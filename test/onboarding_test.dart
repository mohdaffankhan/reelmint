import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_native.dart';

void main() {
  const fresh = <String, Object>{'haptics': false};

  testWidgets('walks through intro pages, grants permissions, lands on home', (
    t,
  ) async {
    final h = await pumpReelmint(t, prefs: fresh);
    expect(find.text('Record anything'), findsOneWidget);

    await t.tap(find.text('Continue'));
    await settle(t);
    expect(find.text('Studio-grade output'), findsOneWidget);

    await t.tap(find.text('Continue'));
    await settle(t);
    expect(find.text('Private by design'), findsOneWidget);

    await t.tap(find.text('Continue'));
    await pumpReal(t);
    expect(find.text('A few permissions'), findsOneWidget);
    expect(find.text('Allow'), findsNWidgets(4));

    // Microphone
    h.native.micGranted = true;
    await t.tap(find.text('Microphone & audio'));
    await pumpReal(t);
    expect(h.native.callsTo('requestMicPermission'), hasLength(1));
    expect(find.text('Allow'), findsNWidgets(3));

    // Notifications
    await t.tap(find.text('Notifications'));
    await pumpReal(t);
    expect(h.native.callsTo('requestNotificationPermission'), hasLength(1));

    // Floating controls (optional) — opens system settings and opts in.
    await t.tap(find.text('Floating controls'));
    await pumpReal(t);
    expect(h.native.callsTo('requestOverlayPermission'), hasLength(1));
    expect(h.settings.floatingControls, isTrue);

    // Camera (optional) — for the facecam.
    h.native.cameraGranted = true;
    await t.ensureVisible(find.text('Camera'));
    await t.tap(find.text('Camera'));
    await pumpReal(t);
    expect(h.native.callsTo('requestCameraPermission'), hasLength(1));

    await t.tap(find.text('Get started'));
    await settle(t, 15);
    expect(h.settings.onboarded, isTrue);
    expect(find.text('Ready to record'), findsOneWidget);
  });

  testWidgets('skip jumps to the permissions page', (t) async {
    await pumpReelmint(t, prefs: fresh);
    await t.tap(find.text('Skip'));
    await pumpReal(t);
    expect(find.text('A few permissions'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('granted permissions show check marks', (t) async {
    await pumpReelmint(
      t,
      prefs: fresh,
      arrange: (n) {
        n.micGranted = true;
        n.notifyGranted = true;
        n.overlayGranted = true;
        n.cameraGranted = true;
      },
    );
    await t.tap(find.text('Skip'));
    await pumpReal(t);
    expect(find.text('Allow'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(4));
  });
}
