import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';
import '../../utils/format.dart';
import '../widgets/common.dart';

/// Lossless trim editor. Pops with the new file path when saved.
class TrimScreen extends StatefulWidget {
  const TrimScreen({super.key, required this.recording});
  final Recording recording;

  static Route<String> route(Recording r) => MaterialPageRoute(
    builder: (_) => TrimScreen(recording: r),
    fullscreenDialog: true,
  );

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  late VideoPlayerController _vc = VideoPlayerController.file(
    widget.recording.file,
  );
  bool _ready = false;
  bool _previewFailed = false; // trimming still works without the preview
  bool _saving = false;
  double _start = 0, _end = 1; // fractions of duration
  static const _frames = 9;
  static const _minSpan = 0.02;

  Duration get _dur => _ready ? _vc.value.duration : widget.recording.duration;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Starts the preview. The hardware decoder can still be busy for a moment (e.g. just
  /// released by the player), so retry once before falling back to no preview.
  Future<void> _init({bool retry = true}) async {
    _vc.addListener(_loop);
    try {
      await _vc.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      _vc.play();
    } catch (_) {
      _vc.removeListener(_loop);
      await _vc.dispose();
      if (!mounted) return;
      if (retry) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        _vc = VideoPlayerController.file(widget.recording.file);
        return _init(retry: false);
      }
      _vc = VideoPlayerController.file(
        widget.recording.file,
      ); // never initialised; safe to dispose
      setState(() => _previewFailed = true);
    }
  }

  void _loop() {
    if (!_ready || !mounted) return;
    final pos = _vc.value.position;
    if (_vc.value.isPlaying && pos >= _dur * _end) {
      _vc.seekTo(_dur * _start);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _vc.removeListener(_loop);
    _vc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final path = await context.recorder.trim(
        widget.recording.path,
        _dur * _start,
        _dur * _end,
      );
      if (mounted) Navigator.pop(context, path);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, e.message ?? 'Trim failed', error: true);
      }
    }
  }

  void _drag(bool isStart, double dx, double width) {
    final delta = dx / width;
    setState(() {
      if (isStart) {
        _start = (_start + delta).clamp(0.0, _end - _minSpan);
        _vc.seekTo(_dur * _start);
      } else {
        _end = (_end + delta).clamp(_start + _minSpan, 1.0);
        _vc.seekTo(_dur * _end);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final selected = _dur * (_end - _start);
    final pos = _ready ? _vc.value.position : Duration.zero;
    final head = _dur.inMilliseconds == 0
        ? 0.0
        : pos.inMilliseconds / _dur.inMilliseconds;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trim'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: GestureDetector(
                  onTap: () {
                    if (!_ready) return;
                    _vc.value.isPlaying ? _vc.pause() : _vc.play();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: _ready
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                AspectRatio(
                                  aspectRatio: _vc.value.aspectRatio,
                                  child: VideoPlayer(_vc),
                                ),
                                if (!_vc.value.isPlaying)
                                  const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                              ],
                            )
                          : _previewFailed
                          ? const Text(
                              'Preview unavailable',
                              style: TextStyle(color: Colors.white70),
                            )
                          : CircularProgressIndicator(color: L.primary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              formatDuration(selected, showMs: true),
              style: context.t.headlineMedium?.copyWith(
                fontFeatures: L.tabular,
              ),
            ),
            Text(
              '${formatDuration(_dur * _start)}  →  ${formatDuration(_dur * _end)}',
              style: TextStyle(color: c.textDim, fontFeatures: L.tabular),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, box) {
                  const handle = 18.0;
                  final w = box.maxWidth - handle * 2;
                  return SizedBox(
                    height: 72,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Filmstrip
                        Positioned.fill(
                          left: handle,
                          right: handle,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Row(
                              children: [
                                for (var i = 0; i < _frames; i++)
                                  Expanded(
                                    child: ThumbImage(
                                      path: widget.recording.path,
                                      width: 160,
                                      atMs: _dur.inMilliseconds == 0
                                          ? 0
                                          : (_dur.inMilliseconds *
                                                    (i + 0.5) /
                                                    _frames)
                                                .round(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Dim outside selection
                        Positioned(
                          left: handle,
                          top: 0,
                          bottom: 0,
                          width: w * _start,
                          child: Container(color: Colors.black54),
                        ),
                        Positioned(
                          right: handle,
                          top: 0,
                          bottom: 0,
                          width: w * (1 - _end),
                          child: Container(color: Colors.black54),
                        ),
                        // Selection frame
                        Positioned(
                          left: handle + w * _start - handle,
                          width: w * (_end - _start) + handle * 2,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: const Border.symmetric(
                                  horizontal: BorderSide(
                                    color: L.amber,
                                    width: 3,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        // Playhead
                        if (_ready)
                          Positioned(
                            left: handle + w * head.clamp(0.0, 1.0) - 1,
                            top: -4,
                            bottom: -4,
                            child: IgnorePointer(
                              child: Container(
                                width: 2.5,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        _Handle(
                          key: const ValueKey('trim-start'),
                          left: w * _start,
                          width: handle,
                          isStart: true,
                          onDrag: (dx) => _drag(true, dx, w),
                        ),
                        _Handle(
                          key: const ValueKey('trim-end'),
                          left: handle + w * _end,
                          width: handle,
                          isStart: false,
                          onDrag: (dx) => _drag(false, dx, w),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Lossless trim — no re-encoding, no quality loss. Cuts snap to the nearest keyframe (≤1s).',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textFaint, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _saving
                  ? SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(color: L.primary),
                      ),
                    )
                  : GradientButton(
                      label: 'Save as new clip',
                      icon: Icons.check_rounded,
                      onTap:
                          (_ready || _previewFailed) &&
                              (_start > 0.001 || _end < 0.999)
                          ? _save
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    super.key,
    required this.left,
    required this.width,
    required this.isStart,
    required this.onDrag,
  });
  final double left, width;
  final bool isStart;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    top: 0,
    bottom: 0,
    width: width,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: Container(
        decoration: BoxDecoration(
          color: L.amber,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isStart ? 10 : 0),
            right: Radius.circular(isStart ? 0 : 10),
          ),
        ),
        child: Center(
          child: Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}
