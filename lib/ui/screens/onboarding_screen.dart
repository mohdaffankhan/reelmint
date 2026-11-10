import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.radio_button_checked_rounded,
      'Record anything',
      'Capture games, tutorials, calls and apps in stunning quality — with one tap.',
    ),
    (
      Icons.auto_awesome_rounded,
      'Studio-grade output',
      'Native resolution up to 120 fps, device audio + mic, facecam, draw on screen, and a built-in editor.',
    ),
    (
      Icons.shield_rounded,
      'Private by design',
      'Zero ads. Zero tracking. No watermark. Your recordings stay on your device.',
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pages.length) {
      _pc.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length;
    return Scaffold(
      body: AmbientBackground(
        intensity: 1.4,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedOpacity(
                  opacity: last ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: last
                        ? null
                        : () => _pc.animateToPage(
                            _pages.length,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Text(
                      'Skip',
                      style: TextStyle(color: context.c.textDim),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pc,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final p in _pages)
                      _Intro(icon: p.$1, title: p.$2, body: p.$3),
                    const _Permissions(),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i <= _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: i == _page ? L.brand : null,
                        color: i == _page ? null : context.c.surfaceHi,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: GradientButton(
                  label: last ? 'Get started' : 'Continue',
                  onTap: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                L.primary.withValues(alpha: 0.35),
                L.primary.withValues(alpha: 0),
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                gradient: L.brand,
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: L.rose.withValues(alpha: 0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 54),
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          title,
          textAlign: TextAlign.center,
          style: context.t.headlineLarge?.copyWith(fontSize: 34),
        ),
        const SizedBox(height: 14),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.c.textDim,
            fontSize: 16.5,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _Permissions extends StatefulWidget {
  const _Permissions();
  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions>
    with WidgetsBindingObserver {
  bool _mic = false, _notify = false, _overlay = false, _camera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final r = context.recorder;
    final mic = await r.micPermission();
    final n = await r.notificationPermission();
    final o = await r.overlayPermission();
    final cam = await r.cameraPermission();
    if (mounted) {
      setState(() {
        _mic = mic;
        _notify = n;
        _overlay = o;
        _camera = cam;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.recorder;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            Text(
              'A few permissions',
              style: context.t.headlineLarge?.copyWith(fontSize: 30),
            ),
            const SizedBox(height: 10),
            Text(
              'Grant these now so recording starts instantly. You can change them later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.textDim, fontSize: 15),
            ),
            const SizedBox(height: 28),
            _PermTile(
              icon: Icons.mic_rounded,
              color: L.rose,
              title: 'Microphone & audio',
              body: 'Record your voice and device sound',
              granted: _mic,
              onTap: () async {
                await r.requestMicPermission();
                _refresh();
              },
            ),
            const SizedBox(height: 10),
            _PermTile(
              icon: Icons.notifications_rounded,
              color: L.amber,
              title: 'Notifications',
              body: 'Pause & stop from the notification shade',
              granted: _notify,
              onTap: () async {
                await r.requestNotificationPermission();
                Future.delayed(const Duration(milliseconds: 600), _refresh);
              },
            ),
            const SizedBox(height: 10),
            _PermTile(
              icon: Icons.bubble_chart_rounded,
              color: L.primary,
              title: 'Floating controls',
              body: 'Optional bubble over other apps',
              granted: _overlay,
              optional: true,
              onTap: () {
                context.settings.floatingControls = true;
                r.requestOverlayPermission();
              },
            ),
            if (r.caps.hasCamera) ...[
              const SizedBox(height: 10),
              _PermTile(
                icon: Icons.face_retouching_natural_rounded,
                color: L.mint,
                title: 'Camera',
                body: 'Show yourself in a facecam bubble',
                granted: _camera,
                optional: true,
                onTap: () async {
                  await r.requestCameraPermission();
                  _refresh();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.granted,
    required this.onTap,
    this.optional = false,
  });

  final IconData icon;
  final Color color;
  final String title, body;
  final bool granted, optional;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: granted ? null : onTap,
    child: Glass(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    if (optional) ...[
                      const SizedBox(width: 6),
                      Text(
                        'optional',
                        style: TextStyle(
                          color: context.c.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(color: context.c.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: granted
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: L.mint,
                    key: ValueKey(1),
                  )
                : Container(
                    key: const ValueKey(0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: L.primary,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'Allow',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
