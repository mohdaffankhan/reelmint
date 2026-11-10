import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/recorder.dart';
import '../../utils/format.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<RecorderEvent>? _sub;
  RecState _lastState = RecState.idle;
  late final Recorder _recorder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rec = _recorder = context.recorder;
    _lastState = rec.state;
    _sub = rec.events.listen(_onEvent);
    rec.addListener(_onRecorderChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final path = await rec.consumeLaunchRecording();
      if (path != null) _openPath(path);
      final tab = await rec.consumeLaunchTab();
      if (tab != null) _openTab(tab);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _recorder.removeListener(_onRecorderChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recordings can be made/deleted while we're away (Quick Settings tile, notification).
    if (state == AppLifecycleState.resumed) context.library.refresh();
  }

  void _onRecorderChange() {
    final rec = context.recorder;
    final s = context.settings;
    final justStarted =
        (_lastState == RecState.countdown || _lastState == RecState.idle) &&
        rec.state == RecState.recording;
    if (justStarted && s.minimizeOnStart) {
      rec.moveToBackground();
    }
    _lastState = rec.state;
  }

  Future<void> _onEvent(RecorderEvent e) async {
    if (!mounted) return;
    switch (e) {
      case RecordingSaved(:final path, :final duration):
        haptic(context, HapticKind.medium);
        await context.library.refresh();
        if (mounted) _showSaved(path, duration);
      case RecorderMessage(:final message, :final isError):
        toast(
          context,
          message,
          error: isError,
          icon: isError ? null : Icons.info_outline_rounded,
        );
      case OpenRecording(:final path):
        await context.library.refresh();
        _openPath(path);
      case RecordingDeleted():
        await context.library.refresh();
      case OpenTab(:final tab):
        _openTab(tab);
    }
  }

  void _openTab(String tab) {
    final i = switch (tab) {
      'library' => 1,
      'settings' => 2,
      _ => 0,
    };
    if (mounted) setState(() => _tab = i);
  }

  void _openPath(String path) {
    if (!mounted) return;
    final r = context.library.byPath(path);
    if (r != null) Navigator.of(context).push(PlayerScreen.route(r));
  }

  void _showSaved(String path, Duration duration) {
    final r = context.library.byPath(path);
    if (r == null) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 64,
                      height: 96,
                      child: ThumbImage(path: path),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: L.mint,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Recording saved',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${formatDuration(r.duration > Duration.zero ? r.duration : duration)} · ${formatBytes(r.size)}',
                          style: TextStyle(color: ctx.c.textDim),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'In Gallery · ${context.library.locationLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ctx.c.textFaint,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SoftButton(
                      label: 'Share',
                      icon: Icons.ios_share_rounded,
                      onTap: () {
                        Navigator.pop(ctx);
                        shareRecordings(context, [r]);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'Watch',
                      icon: Icons.play_arrow_rounded,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(PlayerScreen.route(r));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _go(int i) {
    if (i == _tab) return;
    haptic(context, HapticKind.select);
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final rec = context.recorder;
    return Scaffold(
      extendBody: true,
      backgroundColor:
          Colors.transparent, // AmbientBackground paints the (single) backdrop
      body: AmbientBackground(
        child: Stack(
          children: [
            IndexedStack(
              index: _tab,
              children: [
                // Hidden tabs stay alive (scroll position etc.) but stop animating.
                TickerMode(
                  enabled: _tab == 0,
                  child: HomeScreen(onOpenLibrary: () => _go(1)),
                ),
                TickerMode(
                  enabled: _tab == 1,
                  child: LibraryScreen(
                    onRecord: () {
                      _go(0);
                      startRecording(context);
                    },
                  ),
                ),
                TickerMode(enabled: _tab == 2, child: const SettingsScreen()),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _NavBar(index: _tab, onTap: _go),
            ),
            ListenableBuilder(
              listenable: rec,
              builder: (context, _) => _CountdownOverlay(recorder: rec),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.radio_button_checked_rounded, 'Record'),
    (Icons.video_library_rounded, 'Library'),
    (Icons.tune_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 12),
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xF21A1724)
                : const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c.stroke),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: context.isDark ? 0.35 : 0.08,
                ),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _items.length; i++)
                GestureDetector(
                  key: ValueKey('nav-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: i == index ? 18 : 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: i == index ? L.brand : null,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _items[i].$1,
                          size: 22,
                          color: i == index ? Colors.white : c.textDim,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: i == index
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    _items[i].$2,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.recorder});
  final Recorder recorder;

  @override
  Widget build(BuildContext context) {
    final visible =
        recorder.state == RecState.countdown && recorder.countdown > 0;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: _Scrim(
          visible: visible,
          child: Container(
            color: Colors.black.withValues(alpha: 0.82),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: Tween(begin: 1.8, end: 1.0).animate(
                      CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                    ),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: GradientText(
                    '${recorder.countdown}',
                    key: ValueKey(recorder.countdown),
                    style: const TextStyle(
                      fontSize: 160,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      fontFeatures: L.tabular,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Recording starts soon',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 36),
                Pressable(
                  onTap: recorder.stop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the overlay out of the tree entirely once it has faded out.
class _Scrim extends StatefulWidget {
  const _Scrim({required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  State<_Scrim> createState() => _ScrimState();
}

class _ScrimState extends State<_Scrim> {
  late bool _mounted = widget.visible;
  Timer? _t;

  @override
  void didUpdateWidget(_Scrim old) {
    super.didUpdateWidget(old);
    _t?.cancel();
    if (widget.visible) {
      _mounted = true;
    } else if (_mounted) {
      _t = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _mounted = false);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _mounted ? widget.child : const SizedBox.shrink();
}
