import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';
import '../../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/tools.dart';
import 'trim_screen.dart';

Future<void> shareRecordings(BuildContext context, List<Recording> recs) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [for (final r in recs) XFile(r.path, mimeType: 'video/mp4')],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.recording, this.heroTag});
  final Recording recording;

  /// Hero tag of the thumbnail we opened from (unique per screen).
  final String? heroTag;

  static Route<void> route(Recording r, {String? heroTag}) => PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => PlayerScreen(recording: r, heroTag: heroTag),
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Recording rec = widget.recording;
  late VideoPlayerController _vc;
  bool _ready = false;
  bool _chrome = true;
  bool _scrubbing = false;
  double _scrubValue = 0;
  double _speed = 1;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _vc = VideoPlayerController.file(rec.file);
    _vc.addListener(_onTick);
    try {
      await _vc.initialize();
      await _vc.setLooping(true);
      await _vc.play();
      if (mounted) setState(() => _ready = true);
      _scheduleHide();
    } catch (e) {
      if (mounted) toast(context, 'This video can’t be played', error: true);
    }
  }

  void _onTick() {
    if (mounted && !_scrubbing) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _vc.value.isPlaying) setState(() => _chrome = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  void _togglePlay() {
    haptic(context, HapticKind.select);
    _vc.value.isPlaying ? _vc.pause() : _vc.play();
    setState(() {});
    _scheduleHide();
  }

  void _seekBy(int seconds) {
    final target = _vc.value.position + Duration(seconds: seconds);
    _vc.seekTo(target < Duration.zero ? Duration.zero : target);
    haptic(context, HapticKind.select);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _vc.removeListener(_onTick);
    _vc.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions

  Future<void> _share() => shareRecordings(context, [rec]);

  Future<void> _trim() async {
    // Hand the hardware decoder to the trim screen: many phones only allow a couple of
    // video decoders at once.
    final pos = _ready ? _vc.value.position : Duration.zero;
    _hide?.cancel();
    _vc.removeListener(_onTick);
    await _vc.dispose();
    if (!mounted) return;
    setState(() => _ready = false);
    final newPath = await Navigator.of(context)
        .push<String>(TrimScreen.route(rec));
    if (!mounted) return;
    if (newPath == null) {
      await _load(); // back to where we were
      if (mounted && _ready) await _vc.seekTo(pos);
      return;
    }
    await context.library.refresh();
    if (!mounted) return;
    toast(context, 'Trimmed copy saved', icon: Icons.content_cut_rounded);
    final r = context.library.byPath(newPath);
    if (r != null) Navigator.of(context).pushReplacement(PlayerScreen.route(r));
  }

  Future<void> _openNew(String path, String message, IconData icon) async {
    await context.library.refresh();
    if (!mounted) return;
    toast(context, message, icon: icon);
    final r = context.library.byPath(path);
    if (r != null) Navigator.of(context).pushReplacement(PlayerScreen.route(r));
  }

  Future<void> _tools() async {
    final pos = _ready ? _vc.value.position : Duration.zero;
    await _vc.pause();
    if (!mounted) return;
    final outcome = await showTools(context, rec, pos);
    if (outcome is NewVideo && mounted)
      await _openNew(
        outcome.path,
        'New clip saved',
        Icons.auto_awesome_rounded,
      );
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(
      text: rec.fileName.replaceAll('.mp4', ''),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename', style: ctx.t.titleLarge),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          decoration: const InputDecoration(
            hintText: 'Recording name',
            suffixText: '.mp4',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ctx.c.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(
              'Save',
              style: TextStyle(color: L.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final pos = _vc.value.position;
    try {
      final library = context.library;
      await _vc.pause();
      final renamed = await library.rename(rec, name);
      _vc.removeListener(_onTick);
      await _vc.dispose();
      setState(() {
        rec = renamed;
        _ready = false;
      });
      await _load();
      await _vc.seekTo(pos);
      if (mounted) toast(context, 'Renamed');
    } catch (e) {
      if (mounted)
        toast(
          context,
          e is StateError ? e.message : 'Couldn’t rename',
          error: true,
        );
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete recording?',
      message: 'This can’t be undone.',
    );
    if (!ok || !mounted) return;
    await _vc.pause();
    if (!mounted) return;
    final failed = await context.library.delete([rec]);
    if (!mounted) return;
    if (failed > 0) {
      toast(context, 'Couldn’t delete this recording', error: true);
      return;
    }
    Navigator.pop(context);
    toast(context, 'Recording deleted', icon: Icons.delete_outline_rounded);
  }

  void _info() {
    final i = rec.info;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Details', style: ctx.t.titleLarge),
              const SizedBox(height: 16),
              _InfoRow('Name', rec.fileName),
              _InfoRow('Recorded', formatRelativeDate(rec.modified)),
              _InfoRow('Duration', formatDuration(rec.duration)),
              if (i != null && i.width > 0)
                _InfoRow(
                  'Resolution',
                  '${i.width} × ${i.height}  (${resolutionLabel(i.width, i.height)})',
                ),
              if (i != null && i.bitrate > 0)
                _InfoRow(
                  'Bitrate',
                  '${(i.bitrate / 1e6).toStringAsFixed(1)} Mbps',
                ),
              _InfoRow('Audio', i?.hasAudio == true ? 'AAC stereo' : 'None'),
              _InfoRow('Size', formatBytes(rec.size)),
              _InfoRow('Saved in', context.library.locationLabel),
              _InfoRow('Format', 'MP4 · H.264'),
            ],
          ),
        ),
      ),
    );
  }

  void _pickSpeed() async {
    final v = await showOptionSheet<double>(
      context,
      title: 'Playback speed',
      selected: _speed,
      options: [
        for (final s in const [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          OptionItem(s, s == 1 ? 'Normal' : '$s×'),
      ],
    );
    if (v == null) return;
    setState(() => _speed = v);
    _vc.setPlaybackSpeed(v);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final fav = context.settings.favorites.contains(rec.fileName);
    final v = _ready ? _vc.value : null;
    final dur = v?.duration ?? rec.duration;
    final pos = v?.position ?? Duration.zero;
    final progress = dur.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            GestureDetector(
              onTap: _toggleChrome,
              onDoubleTapDown: (d) => _seekBy(
                d.localPosition.dx < MediaQuery.sizeOf(context).width / 2
                    ? -10
                    : 10,
              ),
              onDoubleTap: () {},
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: _ready
                    ? AspectRatio(
                        aspectRatio: _vc.value.aspectRatio,
                        child: VideoPlayer(_vc),
                      )
                    : Hero(
                        tag: widget.heroTag ?? 'player-${rec.path}',
                        child: ThumbImage(
                          path: rec.path,
                          fit: BoxFit.contain,
                          width: 720,
                        ),
                      ),
              ),
            ),

            // Top bar
            _Fade(
              visible: _chrome,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                      child: Row(
                        children: [
                          _CircleIcon(
                            Icons.arrow_back_ios_new_rounded,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rec.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '${formatRelativeDate(rec.modified)} · ${formatBytes(rec.size)}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _CircleIcon(
                            fav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: fav ? L.rose : Colors.white,
                            onTap: () {
                              context.settings.toggleFavorite(rec.fileName);
                              setState(() {});
                            },
                          ),
                          _SpeedChip(speed: _speed, onTap: _pickSpeed),
                          _CircleIcon(Icons.info_outline_rounded, onTap: _info),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Center play/pause
            if (_ready)
              _Fade(
                visible: _chrome || !_vc.value.isPlaying,
                child: Center(
                  child: Pressable(
                    onTap: _togglePlay,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        _vc.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom controls
            _Fade(
              visible: _chrome,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xE6000000), Color(0x00000000)],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 40, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                formatDuration(
                                  _scrubbing ? dur * _scrubValue : pos,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFeatures: L.tabular,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 7,
                                    ),
                                    trackHeight: 3,
                                  ),
                                  child: Slider(
                                    value: _scrubbing ? _scrubValue : progress,
                                    onChangeStart: (x) {
                                      _hide?.cancel();
                                      setState(() {
                                        _scrubbing = true;
                                        _scrubValue = x;
                                      });
                                    },
                                    onChanged: (x) =>
                                        setState(() => _scrubValue = x),
                                    onChangeEnd: (x) async {
                                      await _vc.seekTo(dur * x);
                                      setState(() => _scrubbing = false);
                                      _scheduleHide();
                                    },
                                  ),
                                ),
                              ),
                              Text(
                                formatDuration(dur),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontFeatures: L.tabular,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _Action(Icons.ios_share_rounded, 'Share', _share),
                              _Action(Icons.content_cut_rounded, 'Trim', _trim),
                              _Action(
                                Icons.auto_fix_high_rounded,
                                'Tools',
                                _tools,
                              ),
                              _Action(Icons.edit_rounded, 'Rename', _rename),
                              _Action(
                                Icons.delete_outline_rounded,
                                'Delete',
                                _delete,
                                color: L.rose,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: child,
    ),
  );
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon(
    this.icon, {
    required this.onTap,
    this.color = Colors.white,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap, {this.color = Colors.white});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.k, this.v);
  final String k, v;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: TextStyle(color: context.c.textDim)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.speed, required this.onTap});
  final double speed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Text(
        speed == 1 ? '1×' : '$speed×',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontFeatures: L.tabular,
        ),
      ),
    ),
  );
}
