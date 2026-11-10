import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/settings.dart';
import '../../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/gates.dart';
import 'home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _overlayGranted = false;
  bool _cameraGranted = false;
  String?
  _pending; // feature waiting for the user to come back from system settings

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final r = context.recorder;
    final overlay = await r.overlayPermission();
    final camera = await r.cameraPermission();
    if (!mounted) return;
    setState(() {
      _overlayGranted = overlay;
      _cameraGranted = camera;
    });
    // Back from system settings with the permission granted — finish turning the feature on.
    if (overlay && _pending != null) {
      final s = context.settings;
      switch (_pending) {
        case 'floating':
          s.floatingControls = true;
        case 'facecam':
          if (camera) s.facecam = true;
      }
      _pending = null;
    }
  }

  Future<void> _toggleFloating(bool v) async {
    final s = context.settings;
    if (!v) {
      s.floatingControls = false;
      return;
    }
    _pending = 'floating';
    if (await ensureOverlay(context, feature: 'floating controls')) {
      _pending = null;
      s.floatingControls = true;
    }
  }

  Future<void> _toggleFacecam(bool v) async {
    final s = context.settings;
    if (!v) {
      s.facecam = false;
      return;
    }
    _pending = 'facecam';
    if (await ensureFacecam(context)) {
      _pending = null;
      s.facecam = true;
    }
    _refreshPermissions();
  }

  Future<void> _toggleLock(bool v) async {
    final s = context.settings;
    final r = context.recorder;
    if (!v) {
      // Turning the lock off also needs the owner.
      if (await r.authenticate('Confirm it’s you to turn off App lock'))
        s.appLock = false;
      return;
    }
    if (!await r.canAuthenticate()) {
      if (mounted)
        toast(
          context,
          'Set up a fingerprint, face or screen lock first',
          error: true,
        );
      return;
    }
    if (await r.authenticate('Confirm to turn on App lock')) {
      s.appLock = true;
      if (mounted) toast(context, 'App lock is on', icon: Icons.lock_rounded);
    }
  }

  Future<void> _addTile() async {
    final code = await context.recorder.requestAddTile();
    if (!mounted) return;
    switch (code) {
      case 1 || 2: // added / already added
        toast(
          context,
          'Reelmint tile is in your Quick Settings',
          icon: Icons.check_circle_rounded,
        );
      case -1:
        toast(
          context,
          'Pull down Quick Settings → ✎ Edit → drag “Reelmint record” in',
          icon: Icons.info_outline_rounded,
        );
      default:
        break;
    }
  }

  Future<void> _pickBitrate() async {
    final s = context.settings;
    final v = await showOptionSheet<int>(
      context,
      title: 'Video bitrate',
      subtitle:
          'Auto picks the ideal bitrate for your resolution and frame rate.',
      selected: s.bitrateMbps,
      options: const [
        OptionItem(
          0,
          'Auto',
          hint: 'Recommended',
          icon: Icons.auto_awesome_rounded,
          badge: 'SMART',
        ),
        OptionItem(
          4,
          '4 Mbps',
          hint: 'Small files',
          icon: Icons.data_saver_on_rounded,
        ),
        OptionItem(8, '8 Mbps', hint: 'Good quality', icon: Icons.tune_rounded),
        OptionItem(
          16,
          '16 Mbps',
          hint: 'High quality',
          icon: Icons.tune_rounded,
        ),
        OptionItem(
          24,
          '24 Mbps',
          hint: 'Very high quality',
          icon: Icons.tune_rounded,
        ),
        OptionItem(
          40,
          '40 Mbps',
          hint: 'Near lossless — huge files',
          icon: Icons.diamond_rounded,
        ),
      ],
    );
    if (v != null) s.bitrateMbps = v;
  }

  Future<void> _pickOrientation() async {
    final s = context.settings;
    final v = await showOptionSheet<RecOrientation>(
      context,
      title: 'Orientation',
      subtitle: 'Auto follows the device when recording starts.',
      selected: s.orientation,
      options: const [
        OptionItem(
          RecOrientation.auto,
          'Auto',
          icon: Icons.screen_rotation_rounded,
        ),
        OptionItem(
          RecOrientation.portrait,
          'Portrait',
          icon: Icons.stay_current_portrait_rounded,
        ),
        OptionItem(
          RecOrientation.landscape,
          'Landscape',
          icon: Icons.stay_current_landscape_rounded,
        ),
      ],
    );
    if (v != null) s.orientation = v;
  }

  Future<void> _pickAudioQuality() async {
    final s = context.settings;
    final v = await showOptionSheet<int>(
      context,
      title: 'Audio quality',
      selected: s.audioKbps,
      options: const [
        OptionItem(
          96,
          '96 kbps',
          hint: 'Voice',
          icon: Icons.record_voice_over_rounded,
        ),
        OptionItem(
          128,
          '128 kbps',
          hint: 'Standard',
          icon: Icons.music_note_rounded,
        ),
        OptionItem(
          192,
          '192 kbps',
          hint: 'High — recommended',
          icon: Icons.music_note_rounded,
          badge: 'BEST',
        ),
        OptionItem(
          256,
          '256 kbps',
          hint: 'Studio',
          icon: Icons.graphic_eq_rounded,
        ),
      ],
    );
    if (v != null) s.audioKbps = v;
  }

  Future<void> _pickCountdown() async {
    final s = context.settings;
    final v = await showOptionSheet<int>(
      context,
      title: 'Countdown',
      selected: s.countdown,
      options: [
        for (final c in Settings.countdowns)
          OptionItem(
            c,
            c == 0 ? 'Off' : '$c seconds',
            icon: c == 0 ? Icons.timer_off_rounded : Icons.timer_rounded,
          ),
      ],
    );
    if (v != null) s.countdown = v;
  }

  Future<void> _pickFacecamSize() async {
    final s = context.settings;
    final v = await showOptionSheet<String>(
      context,
      title: 'Facecam size',
      subtitle: 'Tap the bubble while recording to cycle sizes.',
      selected: s.facecamSize,
      options: const [
        OptionItem('s', 'Small', icon: Icons.circle_outlined),
        OptionItem('m', 'Medium', icon: Icons.circle_outlined),
        OptionItem('l', 'Large', icon: Icons.circle_outlined),
      ],
    );
    if (v != null) s.facecamSize = v;
  }

  Future<void> _pickTheme() async {
    final s = context.settings;
    final v = await showOptionSheet<ThemeMode>(
      context,
      title: 'Appearance',
      selected: s.themeMode,
      options: const [
        OptionItem(ThemeMode.dark, 'Dark', icon: Icons.dark_mode_rounded),
        OptionItem(ThemeMode.light, 'Light', icon: Icons.light_mode_rounded),
        OptionItem(
          ThemeMode.system,
          'Match system',
          icon: Icons.brightness_auto_rounded,
        ),
      ],
    );
    if (v != null) s.themeMode = v;
  }

  Future<void> _clearAll() async {
    final lib = context.library;
    if (lib.items.isEmpty) return;
    final ok = await confirm(
      context,
      title: 'Delete all recordings?',
      message:
          'All ${lib.items.length} recordings (${formatBytes(lib.totalBytes)}) will be permanently removed from Reelmint. '
          'Copies you saved to your gallery are not affected.',
      action: 'Delete all',
    );
    if (!ok) return;
    await lib.delete(lib.items);
    if (mounted) toast(context, 'Library cleared');
  }

  static String _facecamSizeLabel(String v) => switch (v) {
    's' => 'Small',
    'l' => 'Large',
    _ => 'Medium',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    final caps = context.recorder.caps;
    final lib = context.library;
    final screen =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([s, lib]),
      builder: (context, _) {
        final mbPerMin = s.estimateMbPerMinute(
          math.min(screen.width, screen.height).round(),
          math.max(screen.width, screen.height).round(),
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.paddingOf(context).top + 12,
            20,
            140,
          ),
          children: [
            Text('Settings', style: context.t.headlineLarge),
            const SizedBox(height: 20),
            const _Insights(),
            const SizedBox(height: 24),

            const SectionLabel('Video'),
            _Group(
              children: [
                _Row(
                  icon: Icons.high_quality_rounded,
                  color: L.primary,
                  title: 'Resolution',
                  value: s.resolutionLabel,
                  onTap: () => pickResolution(context),
                ),
                _Row(
                  icon: Icons.speed_rounded,
                  color: L.amber,
                  title: 'Frame rate',
                  value: '${s.fps} fps',
                  onTap: () => pickFps(context),
                ),
                _Row(
                  icon: Icons.tune_rounded,
                  color: L.mint,
                  title: 'Bitrate',
                  value: s.bitrateLabel,
                  onTap: _pickBitrate,
                ),
                _Row(
                  icon: Icons.screen_rotation_rounded,
                  color: L.rose,
                  title: 'Orientation',
                  value: s.orientation.label,
                  onTap: _pickOrientation,
                ),
              ],
            ),
            _Footnote(
              'About ${mbPerMin.toStringAsFixed(mbPerMin >= 100 ? 0 : 1)} MB per minute with these settings.',
            ),
            const SizedBox(height: 24),

            const SectionLabel('Audio'),
            _Group(
              children: [
                _Row(
                  icon: s.audio.icon,
                  color: L.rose,
                  title: 'Source',
                  value: s.audio.label,
                  onTap: () => pickAudio(context),
                ),
                _Row(
                  icon: Icons.graphic_eq_rounded,
                  color: L.primary,
                  title: 'Quality',
                  value: '${s.audioKbps} kbps',
                  onTap: _pickAudioQuality,
                ),
              ],
            ),
            if (caps.internalAudio)
              const _Footnote(
                'Some apps (e.g. streaming services, calls) block device-audio capture for copyright or privacy.',
              ),
            const SizedBox(height: 24),

            if (caps.hasCamera) ...[
              const SectionLabel('Facecam'),
              _Group(
                children: [
                  _ToggleRow(
                    icon: Icons.face_retouching_natural_rounded,
                    color: L.mint,
                    title: 'Show facecam',
                    subtitle:
                        'Round front-camera bubble, recorded with your screen',
                    value: s.facecam && _cameraGranted && _overlayGranted,
                    onChanged: _toggleFacecam,
                  ),
                  _Row(
                    icon: Icons.photo_size_select_small_rounded,
                    color: L.sky,
                    title: 'Bubble size',
                    value: _facecamSizeLabel(s.facecamSize),
                    onTap: _pickFacecamSize,
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            const SectionLabel('Recording'),
            _Group(
              children: [
                _Row(
                  icon: Icons.timer_rounded,
                  color: L.amber,
                  title: 'Countdown',
                  value: s.countdown == 0 ? 'Off' : '${s.countdown}s',
                  onTap: _pickCountdown,
                ),
                _Row(
                  icon: Icons.av_timer_rounded,
                  color: L.rose,
                  title: 'Auto-stop',
                  value: s.timeLimitLabel,
                  onTap: () => pickTimeLimit(context),
                ),
                _ToggleRow(
                  icon: Icons.bubble_chart_rounded,
                  color: L.primary,
                  title: 'Floating controls',
                  subtitle:
                      'Bubble with timer, pause, stop, mic, facecam & draw',
                  value: s.floatingControls && _overlayGranted,
                  onChanged: _toggleFloating,
                ),
                _ToggleRow(
                  icon: Icons.vibration_rounded,
                  color: L.sky,
                  title: 'Shake to stop',
                  subtitle: 'Give your phone two quick shakes to stop & save',
                  value: s.shakeToStop,
                  onChanged: (v) => s.shakeToStop = v,
                ),
                _ToggleRow(
                  icon: Icons.open_in_new_rounded,
                  color: L.mint,
                  title: 'Minimize on start',
                  subtitle: 'Jump to your home screen when recording begins',
                  value: s.minimizeOnStart,
                  onChanged: (v) => s.minimizeOnStart = v,
                ),
                _ToggleRow(
                  icon: Icons.phonelink_lock_rounded,
                  color: L.rose,
                  title: 'Stop when screen locks',
                  value: s.stopOnScreenOff,
                  onChanged: (v) => s.stopOnScreenOff = v,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const SectionLabel('Shortcuts'),
            _Group(
              children: [
                _Row(
                  icon: Icons.grid_view_rounded,
                  color: L.primary,
                  title: 'Add Quick Settings tile',
                  value: caps.quickTile ? null : 'How to',
                  onTap: _addTile,
                ),
              ],
            ),
            const _Footnote(
              'Tip: long-press the Reelmint icon for “Record” and “Library” shortcuts.',
            ),
            const SizedBox(height: 24),

            const SectionLabel('Privacy'),
            _Group(
              children: [
                _ToggleRow(
                  icon: Icons.fingerprint_rounded,
                  color: L.mint,
                  title: 'App lock',
                  subtitle: 'Fingerprint, face or screen lock to open Reelmint',
                  value: s.appLock,
                  onChanged: _toggleLock,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const SectionLabel('Appearance'),
            _Group(
              children: [
                _Row(
                  icon: Icons.palette_rounded,
                  color: L.primary,
                  title: 'Theme',
                  value: switch (s.themeMode) {
                    ThemeMode.dark => 'Dark',
                    ThemeMode.light => 'Light',
                    ThemeMode.system => 'System',
                  },
                  onTap: _pickTheme,
                ),
                _AccentPicker(selected: s.accent, onPick: (a) => s.accent = a),
                _ToggleRow(
                  icon: Icons.vibration_rounded,
                  color: L.mint,
                  title: 'Haptic feedback',
                  value: s.haptics,
                  onChanged: (v) => s.haptics = v,
                ),
              ],
            ),
            const SizedBox(height: 24),

            const SectionLabel('Storage'),
            _Group(
              children: [
                _Row(
                  icon: Icons.folder_rounded,
                  color: L.primary,
                  title: 'Saved to',
                  value: lib.locationLabel,
                ),
                _Row(
                  icon: Icons.sd_storage_rounded,
                  color: L.amber,
                  title: 'Used by recordings',
                  value: '${formatBytes(lib.totalBytes)} · ${lib.items.length}',
                ),
                _Row(
                  icon: Icons.delete_sweep_rounded,
                  color: L.rose,
                  title: 'Delete all recordings',
                  onTap: _clearAll,
                  danger: true,
                ),
              ],
            ),
            const SizedBox(height: 28),

            const _PrivacyCard(),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Reelmint 1.0.0',
                style: TextStyle(color: context.c.textFaint, fontSize: 12.5),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights();

  @override
  Widget build(BuildContext context) {
    final lib = context.library;
    final longest = lib.items.fold(
      Duration.zero,
      (a, r) => r.duration > a ? r.duration : a,
    );
    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: L.tabular,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: L.brand,
        borderRadius: BorderRadius.circular(L.radius),
        boxShadow: [
          BoxShadow(
            color: L.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          stat('${lib.items.length}', 'recordings'),
          stat(formatDuration(lib.totalDuration), 'recorded'),
          stat(formatDuration(longest), 'longest'),
        ],
      ),
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.selected, required this.onPick});
  final Accent selected;
  final ValueChanged<Accent> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBadge(Icons.color_lens_rounded, size: 34),
            const SizedBox(width: 14),
            const Text(
              'Accent',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              selected.label,
              style: TextStyle(color: context.c.textDim, fontSize: 14.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final a in Accent.values)
              Pressable(
                key: ValueKey('accent-${a.name}'),
                onTap: () => onPick(a),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: a == selected
                          ? context.c.text
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: a.gradient,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Glass(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            Divider(height: 1, indent: 62, color: context.c.stroke),
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.value,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: danger ? L.rose : null,
              ),
            ),
          ),
          if (value != null)
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: context.c.textDim,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (onTap != null && !danger) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: context.c.textFaint),
          ],
        ],
      ),
    ),
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      haptic(context, HapticKind.select);
      onChanged(!value);
    },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.c.textDim,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
    child: Text(
      text,
      style: TextStyle(color: context.c.textFaint, fontSize: 12.5),
    ),
  );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(L.radius),
      gradient: LinearGradient(
        colors: [
          L.primary.withValues(alpha: 0.22),
          L.rose.withValues(alpha: 0.14),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: L.primary.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        const GradientIcon(Icons.shield_rounded, size: 38),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No ads. No tracking. No watermark.',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Recordings never leave your device unless you share them. Reelmint has no analytics or ad SDKs.',
                style: TextStyle(color: context.c.textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
