import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';
import '../../services/recorder.dart';
import 'common.dart';

/// What a tool produced.
sealed class ToolOutcome {}

/// A new video was created in the library.
class NewVideo extends ToolOutcome {
  NewVideo(this.path);
  final String path;
}

/// Something was exported elsewhere (photo / audio); nothing new in the library.
class Exported extends ToolOutcome {}

enum Tool {
  compress('Compress', 'Smaller file, re-encoded', Icons.compress_rounded),
  speed(
    'Change speed',
    '0.5× slow-mo to 4× time-lapse',
    Icons.slow_motion_video_rounded,
  ),
  rotate('Rotate', 'Lossless — instant', Icons.rotate_90_degrees_cw_rounded),
  removeAudio(
    'Remove audio',
    'Silent copy — lossless',
    Icons.volume_off_rounded,
  ),
  extractAudio(
    'Extract audio',
    'Save the soundtrack as .m4a',
    Icons.audiotrack_rounded,
  ),
  saveFrame(
    'Save frame',
    'This moment as a full-res photo',
    Icons.photo_camera_rounded,
  );

  const Tool(this.label, this.hint, this.icon);
  final String label, hint;
  final IconData icon;
}

/// Opens the editor tools for [rec]; [position] is the player position (for Save frame).
Future<ToolOutcome?> showTools(
  BuildContext context,
  Recording rec,
  Duration position,
) async {
  final tool = await showModalBottomSheet<Tool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit & export', style: ctx.t.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Edits are saved as new clips — your original stays untouched.',
              style: TextStyle(color: ctx.c.textDim),
            ),
            const SizedBox(height: 16),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent:
                    112, // fixed height: robust to large font scales
              ),
              children: [
                for (final t in Tool.values)
                  _ToolTile(tool: t, onTap: () => Navigator.pop(ctx, t)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (tool == null || !context.mounted) return null;
  return runTool(context, tool, rec, position);
}

Future<ToolOutcome?> runTool(
  BuildContext context,
  Tool tool,
  Recording rec,
  Duration position,
) async {
  final r = context.recorder;
  try {
    switch (tool) {
      case Tool.compress:
        final side = await showOptionSheet<int>(
          context,
          title: 'Compress to',
          subtitle:
              'Re-encodes the video. Lower resolution = much smaller file.',
          selected: 0,
          options: const [
            OptionItem(
              1080,
              '1080p',
              hint: 'Full HD · ~8 Mbps',
              icon: Icons.hd_rounded,
            ),
            OptionItem(
              720,
              '720p',
              hint: 'HD · ~4 Mbps — great for messaging',
              icon: Icons.sd_rounded,
            ),
            OptionItem(
              480,
              '480p',
              hint: 'Smallest · ~1.5 Mbps',
              icon: Icons.sd_rounded,
            ),
          ],
        );
        if (side == null || !context.mounted) return null;
        final bitrate = switch (side) {
          1080 => 8000000,
          720 => 4000000,
          _ => 1500000,
        };
        final out = await runTransform(
          context,
          [rec.path],
          TransformSpec(shortSide: side, bitrate: bitrate),
          title: 'Compressing to ${side}p',
        );
        return out == null ? null : NewVideo(out);
      case Tool.speed:
        final speed = await showOptionSheet<double>(
          context,
          title: 'Playback speed',
          subtitle: 'Exports a new clip at the chosen speed (audio pitch is preserved).',
          selected: 1,
          options: const [
            OptionItem(
              0.5,
              '0.5× slow motion',
              icon: Icons.slow_motion_video_rounded,
            ),
            OptionItem(1.5, '1.5×', icon: Icons.fast_forward_rounded),
            OptionItem(2.0, '2× fast', icon: Icons.fast_forward_rounded),
            OptionItem(4.0, '4× time-lapse', icon: Icons.bolt_rounded),
          ],
        );
        if (speed == null || !context.mounted) return null;
        final out = await runTransform(
          context,
          [rec.path],
          TransformSpec(speed: speed),
          title: 'Exporting at $speed×',
        );
        return out == null ? null : NewVideo(out);
      case Tool.rotate:
        final deg = await showOptionSheet<int>(
          context,
          title: 'Rotate',
          selected: 0,
          options: const [
            OptionItem(90, '90° clockwise', icon: Icons.rotate_right_rounded),
            OptionItem(180, '180°', icon: Icons.flip_camera_android_rounded),
            OptionItem(
              270,
              '90° counter-clockwise',
              icon: Icons.rotate_left_rounded,
            ),
          ],
        );
        if (deg == null) return null;
        return NewVideo(await r.rotate(rec.path, deg));
      case Tool.removeAudio:
        return NewVideo(await r.removeAudio(rec.path));
      case Tool.extractAudio:
        if (rec.info?.hasAudio == false) {
          if (context.mounted)
            toast(context, 'This recording has no audio', error: true);
          return null;
        }
        final audio = await r.extractAudio(rec.path);
        if (!context.mounted) return Exported();
        toast(
          context,
          'Saved to Music › Reelmint',
          icon: Icons.audiotrack_rounded,
        );
        await SharePlus.instance.share(
          ShareParams(files: [XFile(audio, mimeType: 'audio/mp4')]),
        );
        return Exported();
      case Tool.saveFrame:
        await r.saveFrame(rec.path, position);
        if (context.mounted)
          toast(
            context,
            'Frame saved to Pictures › Reelmint',
            icon: Icons.photo_rounded,
          );
        return Exported();
    }
  } on PlatformException catch (e) {
    if (context.mounted)
      toast(context, e.message ?? 'That didn’t work', error: true);
    return null;
  }
}

/// Runs a Media3 export with a progress dialog (cancellable). Returns the output path.
Future<String?> runTransform(
  BuildContext context,
  List<String> paths,
  TransformSpec spec, {
  required String title,
}) async {
  final r = context.recorder;
  final id = 'job${DateTime.now().microsecondsSinceEpoch}';
  var cancelled = false;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title, style: ctx.t.titleLarge),
        content: ListenableBuilder(
          listenable: r,
          builder: (ctx, _) {
            final p = (r.jobProgress[id] ?? 0).clamp(0, 100);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: p == 0 ? null : p / 100,
                    minHeight: 10,
                    color: L.primary,
                    backgroundColor: ctx.c.surfaceHi,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  p == 0 ? 'Preparing…' : '$p%',
                  style: TextStyle(
                    color: ctx.c.textDim,
                    fontFeatures: L.tabular,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              r.cancelJob(id);
            },
            child: Text('Cancel', style: TextStyle(color: ctx.c.textDim)),
          ),
        ],
      ),
    ),
  );
  try {
    final out = await r.transform(paths, spec, id: id);
    nav.pop();
    return out;
  } on PlatformException catch (e) {
    nav.pop();
    if (!cancelled && context.mounted) {
      if (e.code == 'compact') {
        toast(
          context,
          e.message ?? 'Already as compact as it gets',
          icon: Icons.check_circle_rounded,
        );
      } else {
        toast(context, e.message ?? 'Export failed', error: true);
      }
    }
    return null;
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, required this.onTap});
  final Tool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.c.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(tool.icon, size: 32),
          const Spacer(),
          Text(
            tool.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Text(
            tool.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.c.textDim, fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}
