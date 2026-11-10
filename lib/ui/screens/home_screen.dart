import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';
import '../../services/recorder.dart';
import '../../services/settings.dart';
import '../../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import '../widgets/record_button.dart';
import 'player_screen.dart';

Future<void> startRecording(BuildContext context) async {
  final r = context.recorder;
  final s = context.settings;
  haptic(context, HapticKind.heavy);
  final ok = await r.start(s.toNative());
  if (!ok && context.mounted) {
    toast(context, 'Recording cancelled', icon: Icons.info_outline_rounded);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenLibrary});
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final rec = context.recorder;
    return ListenableBuilder(
      listenable: Listenable.merge([rec, context.settings]),
      builder: (context, _) {
        final active = rec.isActive;
        return CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: RepaintBoundary(child: _Header(active: active)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: RepaintBoundary(child: _Hero(recorder: rec)),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: active
                      ? const SizedBox(width: double.infinity)
                      : const RepaintBoundary(child: _QuickSettings()),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 140),
              sliver: SliverToBoxAdapter(
                child: RepaintBoundary(child: _Recent(onSeeAll: onOpenLibrary)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(gradient: L.brand, shape: BoxShape.circle),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Reelmint',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.t.titleLarge?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: active
              ? _LiveBadge(
                  key: const ValueKey('live'),
                  paused: context.recorder.state == RecState.paused,
                )
              : Container(
                  key: const ValueKey('free'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: L.mint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, color: L.mint, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Ad-free',
                        style: TextStyle(
                          color: L.mint,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge({super.key, required this.paused});
  final bool paused;
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paused = widget.paused;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (paused ? L.amber : L.rose).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: paused ? const AlwaysStoppedAnimation(1) : _c,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: paused ? L.amber : L.rose,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            paused ? 'PAUSED' : 'REC',
            style: TextStyle(
              color: paused ? L.amber : L.rose,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.recorder});
  final Recorder recorder;

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final state = recorder.state;
    final active = recorder.isRecording || state == RecState.stopping;
    final c = context.c;

    final extras = [
      if (s.facecam) 'Facecam',
      if (s.timeLimitMin > 0) 'Stops at ${s.timeLimitMin}m',
    ];
    final subtitle = switch (state) {
      RecState.idle => [
        '${s.resolutionLabel} · ${s.fps} fps · ${s.audio.label}',
        ...extras,
      ].join(' · '),
      RecState.countdown => 'Starting in ${recorder.countdown}…',
      RecState.recording => 'Recording your screen',
      RecState.paused => 'Paused — tap resume to continue',
      RecState.stopping => 'Saving…',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: active
                ? Text(
                    formatDuration(recorder.elapsed),
                    key: const ValueKey('timer'),
                    style: context.t.displayLarge?.copyWith(
                      fontSize: 64,
                      fontFeatures: L.tabular,
                      height: 1,
                    ),
                  )
                : Text(
                    'Ready to record',
                    key: const ValueKey('ready'),
                    style: context.t.headlineMedium?.copyWith(fontSize: 30),
                  ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                subtitle,
                key: ValueKey(subtitle),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textDim, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 4),
          RecordButton(
            state: state,
            size: 190,
            onTap: () async {
              switch (state) {
                case RecState.idle:
                  await startRecording(context);
                case RecState.countdown:
                case RecState.recording:
                case RecState.paused:
                  haptic(context, HapticKind.heavy);
                  await recorder.stop();
                case RecState.stopping:
                  break;
              }
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: recorder.isRecording
                ? _LiveControls(recorder: recorder)
                : const _IdleHint(),
          ),
        ],
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      'Tap the orb to start',
      style: TextStyle(color: context.c.textFaint, fontSize: 13),
    ),
  );
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({required this.recorder});
  final Recorder recorder;

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final paused = recorder.state == RecState.paused;
    final usesMic = s.audio == AudioSource.mic || s.audio == AudioSource.both;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 12,
        children: [
          if (usesMic)
            _RoundControl(
              icon: recorder.micMuted
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              label: recorder.micMuted ? 'Unmute' : 'Mute',
              highlight: recorder.micMuted,
              onTap: recorder.toggleMic,
            ),
          if (recorder.caps.pause)
            _RoundControl(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: paused ? 'Resume' : 'Pause',
              highlight: paused,
              onTap: paused ? recorder.resume : recorder.pause,
            ),
          _RoundControl(
            icon: Icons.stop_rounded,
            label: 'Stop',
            danger: true,
            onTap: recorder.stop,
          ),
          if (recorder.caps.hasCamera)
            _RoundControl(
              icon: recorder.facecamOn
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: 'Facecam',
              highlight: recorder.facecamOn,
              highlightColor: L.mint,
              onTap: () async {
                if (recorder.facecamOn || await ensureFacecam(context))
                  await recorder.toggleFacecam();
              },
            ),
          _RoundControl(
            icon: Icons.draw_rounded,
            label: 'Draw',
            highlight: recorder.drawOn,
            highlightColor: L.sky,
            onTap: () async {
              final wasOn = recorder.drawOn;
              if (wasOn ||
                  await ensureOverlay(context, feature: 'drawing tools')) {
                await recorder.toggleDraw();
                // Drawing happens over other apps — step out of the way.
                if (!wasOn) await recorder.moveToBackground();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
    this.danger = false,
    this.highlightColor = L.amber,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight, danger;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = danger ? L.rose : (highlight ? highlightColor : c.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Pressable(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: danger || highlight ? 0.16 : 0.08,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: c.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSettings extends StatelessWidget {
  const _QuickSettings();

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final caps = context.recorder.caps;
    final preset = s.activePreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickTile(
                icon: Icons.high_quality_rounded,
                color: L.primary,
                label: 'Quality',
                value: s.resolutionLabel,
                onTap: () => pickResolution(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickTile(
                icon: Icons.speed_rounded,
                color: L.amber,
                label: 'Frame rate',
                value: '${s.fps} fps',
                onTap: () => pickFps(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickTile(
                icon: s.audio.icon,
                color: L.rose,
                label: 'Audio',
                value: s.audio.label,
                onTap: () => pickAudio(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (caps.hasCamera)
              _Toggle(
                icon: Icons.face_retouching_natural_rounded,
                label: 'Facecam',
                on: s.facecam,
                onTap: () async {
                  if (s.facecam) {
                    s.facecam = false;
                  } else if (await ensureFacecam(context)) {
                    s.facecam = true;
                  }
                },
              ),
            _Toggle(
              icon: Icons.bubble_chart_rounded,
              label: 'Bubble',
              on: s.floatingControls,
              onTap: () async {
                if (s.floatingControls) {
                  s.floatingControls = false;
                } else if (await ensureOverlay(
                  context,
                  feature: 'floating controls',
                )) {
                  s.floatingControls = true;
                }
              },
            ),
            _Toggle(
              icon: Icons.timer_outlined,
              label: s.timeLimitMin == 0
                  ? 'Auto-stop'
                  : 'Stop at ${s.timeLimitMin}m',
              on: s.timeLimitMin > 0,
              onTap: () => pickTimeLimit(context),
            ),
            _Toggle(
              icon: Icons.vibration_rounded,
              label: 'Shake to stop',
              on: s.shakeToStop,
              onTap: () => s.shakeToStop = !s.shakeToStop,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SectionLabel('Presets'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,

            clipBehavior: Clip.none,
            itemCount: QualityPreset.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = QualityPreset.all[i];
              final on = preset == p;
              return Pressable(
                onTap: () {
                  final audio =
                      (!caps.internalAudio &&
                          (p.audio == AudioSource.internal ||
                              p.audio == AudioSource.both))
                      ? AudioSource.mic
                      : p.audio;
                  s.applyPreset(
                    QualityPreset(
                      p.name,
                      p.icon,
                      p.resolution,
                      p.fps.clamp(24, caps.maxFps),
                      p.bitrateMbps,
                      audio,
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: on ? L.brand : null,
                    color: on ? null : context.c.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: on ? Colors.transparent : context.c.stroke,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        p.icon,
                        size: 18,
                        color: on ? Colors.white : context.c.textDim,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: on ? Colors.white : context.c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? L.primary.withValues(alpha: 0.16) : c.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: on ? L.primary.withValues(alpha: 0.6) : c.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: on ? L.primary : c.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on ? c.text : c.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Glass(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, color: color, size: 34),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: context.c.textFaint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _Recent extends StatelessWidget {
  const _Recent({required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final lib = context.library;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final items = [...lib.items]
          ..sort((a, b) => b.modified.compareTo(a.modified));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(
              'Recent',
              trailing: items.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: onSeeAll,
                      child: Text(
                        'See all',
                        style: TextStyle(
                          color: L.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
            ),
            if (items.isEmpty)
              Glass(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const IconBadge(Icons.video_library_rounded, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No recordings yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your captures will appear here.',
                            style: TextStyle(
                              color: context.c.textDim,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,

                  clipBehavior: Clip.none,
                  itemCount: items.length.clamp(0, 10),
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _RecentCard(rec: items[i]),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${lib.items.length} recording${lib.items.length == 1 ? '' : 's'} · ${formatBytes(lib.totalBytes)} on device',
                style: TextStyle(color: context.c.textFaint, fontSize: 12.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.rec});
  final Recording rec;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: () =>
        Navigator.of(context)
            .push(PlayerScreen.route(rec, heroTag: 'recent-${rec.path}')),
    child: SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'recent-${rec.path}',
                    child: ThumbImage(path: rec.path),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Pill(child: Text(formatDuration(rec.duration))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatRelativeDate(rec.modified),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          Text(
            formatBytes(rec.size),
            style: TextStyle(color: context.c.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- pickers (shared with Settings)

Future<void> pickResolution(BuildContext context) async {
  final s = context.settings;
  final v = await showOptionSheet<int>(
    context,
    title: 'Resolution',
    subtitle: 'Higher resolution means sharper video and larger files.',
    selected: s.resolution,
    options: const [
      OptionItem(
        0,
        'Native',
        hint: 'Your screen’s full resolution',
        icon: Icons.fullscreen_rounded,
        badge: 'MAX',
      ),
      OptionItem(
        1440,
        '1440p',
        hint: 'QHD — crisp on big screens',
        icon: Icons.hd_rounded,
      ),
      OptionItem(
        1080,
        '1080p',
        hint: 'Full HD — best balance',
        icon: Icons.hd_rounded,
      ),
      OptionItem(
        720,
        '720p',
        hint: 'HD — great for sharing',
        icon: Icons.sd_rounded,
      ),
      OptionItem(480, '480p', hint: 'Smallest files', icon: Icons.sd_rounded),
    ],
  );
  if (v != null) s.resolution = v;
}

Future<void> pickFps(BuildContext context) async {
  final s = context.settings;
  final max = context.recorder.caps.maxFps;
  final v = await showOptionSheet<int>(
    context,
    title: 'Frame rate',
    subtitle: 'Smoother motion for games and scrolling at higher frame rates.',
    selected: s.fps,
    options: [
      for (final f in Settings.frameRates)
        OptionItem(
          f,
          '$f fps',
          hint: switch (f) {
            24 => 'Cinematic look',
            30 => 'Tutorials & presentations',
            60 => 'Smooth — recommended',
            _ =>
              f <= max
                  ? 'Ultra-smooth gameplay'
                  : 'Your display tops out at $max Hz',
          },
          icon: Icons.speed_rounded,
          enabled: f <= max || f <= 60,
          badge: f == 60 ? 'BEST' : null,
        ),
    ],
  );
  if (v != null) s.fps = v;
}

Future<void> pickAudio(BuildContext context) async {
  final s = context.settings;
  final r = context.recorder;
  final v = await showOptionSheet<AudioSource>(
    context,
    title: 'Audio source',
    subtitle: 'Device audio captures sound from apps that allow it.',
    selected: s.audio,
    options: [
      for (final a in AudioSource.values)
        OptionItem(
          a,
          a.label,
          hint: a.hint,
          icon: a.icon,
          enabled:
              r.caps.internalAudio ||
              !(a == AudioSource.internal || a == AudioSource.both),
        ),
    ],
  );
  if (v == null) return;
  s.audio = v;
  // Android needs RECORD_AUDIO for both mic and system-audio capture.
  if (v != AudioSource.none) await r.requestMicPermission();
}

Future<void> pickTimeLimit(BuildContext context) async {
  final s = context.settings;
  final v = await showOptionSheet<int>(
    context,
    title: 'Auto-stop',
    subtitle:
        'Stop and save automatically after a set time (pauses don’t count).',
    selected: s.timeLimitMin,
    options: [
      for (final m in Settings.timeLimits)
        OptionItem(
          m,
          m == 0 ? 'Off' : '$m minute${m == 1 ? '' : 's'}',
          icon: m == 0 ? Icons.timer_off_rounded : Icons.timer_rounded,
        ),
    ],
  );
  if (v != null) s.timeLimitMin = v;
}
