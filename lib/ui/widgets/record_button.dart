import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/recorder.dart';

/// The hero control: a breathing gradient orb that morphs into a stop
/// button with an orbiting light ring while recording.
class RecordButton extends StatefulWidget {
  const RecordButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 200,
  });
  final RecState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with TickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  ); // runs only while recording
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _down = false;

  bool get _active =>
      widget.state == RecState.recording ||
      widget.state == RecState.paused ||
      widget.state == RecState.stopping;

  @override
  void initState() {
    super.initState();
    _morph.value = _active ? 1 : 0;
    _syncSpin();
  }

  void _syncSpin() {
    final spinning = widget.state == RecState.recording;
    if (spinning && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spinning && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void didUpdateWidget(RecordButton old) {
    super.didUpdateWidget(old);
    _active ? _morph.forward() : _morph.reverse();
    _syncSpin();
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final paused = widget.state == RecState.paused;
    return Semantics(
      button: true,
      label: _active ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _spin, _morph]),
              builder: (context, _) {
                final m = Curves.easeInOutCubic.transform(_morph.value);
                final b = Curves.easeInOut.transform(_breath.value);
                return SizedBox(
                  width: s * 1.35,
                  height: s * 1.35,
                  child: CustomPaint(
                    painter: _OrbPainter(
                      morph: m,
                      breath: b,
                      spin: _spin.value,
                      paused: paused,
                      dark: context.isDark,
                      ringColor: context.c.stroke,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.morph,
    required this.breath,
    required this.spin,
    required this.paused,
    required this.dark,
    required this.ringColor,
  });

  final double morph, breath, spin;
  final bool paused, dark;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 1.35 / 2;

    // Outer glow — breathes when idle, steadier while recording.
    final glowR = r * (1.18 + 0.08 * breath * (1 - morph * 0.6));
    final glowColor = Color.lerp(L.primary, L.rose, morph)!;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: dark ? 0.45 : 0.30),
            glowColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );

    // Track ring.
    final ringR = r * 1.02;
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ringColor,
    );

    // Orbiting light while recording.
    if (morph > 0.01) {
      final sweep = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..shader = SweepGradient(
          colors: [
            L.rose.withValues(alpha: 0),
            (paused ? L.amber : L.rose).withValues(alpha: morph),
          ],
          transform: GradientRotation(spin * 2 * math.pi),
        ).createShader(Rect.fromCircle(center: c, radius: ringR));
      final start = spin * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: ringR),
        paused ? 0 : start,
        paused ? 2 * math.pi : math.pi * 1.6,
        false,
        sweep,
      );
    }

    // Main orb.
    final orbR = r * 0.86;
    final orbRect = Rect.fromCircle(center: c, radius: orbR);
    final orbGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(L.primary, const Color(0xFFFF5F7E), morph)!,
        Color.lerp(L.rose, const Color(0xFFFF2D55), morph)!,
        Color.lerp(L.amber, const Color(0xFFE0153F), morph)!,
      ],
    );
    canvas.drawCircle(
      c,
      orbR,
      Paint()..shader = orbGradient.createShader(orbRect),
    );
    // Glossy top highlight.
    canvas.drawCircle(
      c.translate(0, -orbR * 0.35),
      orbR * 0.75,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: c.translate(0, -orbR * 0.35),
                radius: orbR * 0.75,
              ),
            ),
    );

    // Center glyph: circle → rounded square.
    final glyph = orbR * (0.34 - 0.06 * morph);
    final radius = Radius.circular(glyph * (1 - morph * 0.72));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCircle(center: c, radius: glyph),
        radius,
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter o) =>
      o.morph != morph ||
      o.breath != breath ||
      o.spin != spin ||
      o.paused != paused ||
      o.dark != dark;
}
