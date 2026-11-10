import 'package:flutter/material.dart';

import '../../app/scope.dart';
import 'common.dart';

/// Makes sure "Display over other apps" is granted. Returns true if it already is;
/// otherwise explains, opens system settings and returns false (the user comes back later).
Future<bool> ensureOverlay(
  BuildContext context, {
  required String feature,
}) async {
  final r = context.recorder;
  if (await r.overlayPermission()) return true;
  if (!context.mounted) return false;
  final go = await confirm(
    context,
    title: 'Allow $feature',
    message:
        'Reelmint needs “Display over other apps” to show the $feature on top of other apps. '
        'You’ll be taken to system settings — enable it for Reelmint, then come back.',
    action: 'Open settings',
    destructive: false,
  );
  if (go && context.mounted) await r.requestOverlayPermission();
  return false;
}

/// Camera + overlay permission for the facecam bubble.
Future<bool> ensureFacecam(BuildContext context) async {
  final r = context.recorder;
  if (!r.caps.hasCamera) {
    toast(context, 'This device has no camera', error: true);
    return false;
  }
  if (!await r.cameraPermission() && !await r.requestCameraPermission()) {
    if (context.mounted)
      toast(context, 'Camera access is needed for the facecam', error: true);
    return false;
  }
  if (!context.mounted) return false;
  return ensureOverlay(context, feature: 'facecam');
}
