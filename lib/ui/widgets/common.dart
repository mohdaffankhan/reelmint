import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';

void haptic(BuildContext context, [HapticKind kind = HapticKind.light]) {
  if (!context.settings.haptics) return;
  switch (kind) {
    case HapticKind.light:
      HapticFeedback.lightImpact();
    case HapticKind.medium:
      HapticFeedback.mediumImpact();
    case HapticKind.heavy:
      HapticFeedback.heavyImpact();
    case HapticKind.select:
      HapticFeedback.selectionClick();
  }
}

enum HapticKind { light, medium, heavy, select }

/// App background: a solid base colour.
///
/// (Large translucent "bloom" gradients looked nice but measured ~3 ms extra GPU time per
/// frame on a mid-range phone at 120 Hz, enough to drop frames while scrolling. A solid
/// colour is folded into the screen clear and costs nothing.)
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.intensity = 1});
  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.c.bg, child: child);
}

/// Card surface used across the app.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = L.radius,
    this.blur = 18,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius, blur;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A real backdrop blur re-renders everything behind the card on every scroll frame,
    // which made the app stutter on mid-range GPUs. A layered tint reads the same here.
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.stroke),
      ),
      child: child,
    );
  }
}

/// Scales down slightly while pressed — the tactile feel used across the app.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptics = true,
  });
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final double scale;
  final bool haptics;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics) haptic(context, HapticKind.select);
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              haptic(context, HapticKind.medium);
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        // Only dim disabled items. An (Animated)Opacity layer around every enabled row
        // forced an offscreen pass per item on every frame, which made scrolling heavy.
        child: enabled
            ? widget.child
            : Opacity(opacity: 0.45, child: widget.child),
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.gradient});
  final String text;
  final TextStyle? style;
  final Gradient? gradient;

  // Paints the gradient straight into the glyphs. (A ShaderMask needs an offscreen layer
  // every frame, which is expensive while scrolling.)
  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final scale = MediaQuery.textScalerOf(context);
    final tp = TextPainter(
      text: TextSpan(text: text, style: base),
      textDirection: Directionality.of(context),
      textScaler: scale,
      maxLines: 1,
    )..layout();
    final rect = Offset.zero & tp.size;
    tp.dispose();
    return Text(
      text,
      style: base.copyWith(
        color: null,
        foreground: Paint()..shader = (gradient ?? L.brand).createShader(rect),
      ),
    );
  }
}

class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, this.size = 24, this.gradient});
  final IconData icon;
  final double size;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Center(
      child: Text(
        String.fromCharCode(icon.codePoint),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          inherit: false,
          fontSize: size,
          height: 1,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          foreground: Paint()
            ..shader = (gradient ?? L.brand).createShader(
              Rect.fromLTWH(0, 0, size, size),
            ),
        ),
      ),
    ),
  );
}

/// Rounded-square icon badge with a tinted background.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 40});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? L.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(100),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        fontFeatures: L.tabular,
      ),
      child: child,
    ),
  );
}

/// Thumbnail loaded through the shared cache, with a shimmer placeholder.
class ThumbImage extends StatelessWidget {
  const ThumbImage({
    super.key,
    required this.path,
    this.atMs = 0,
    this.width = 360,
    this.fit = BoxFit.cover,
  });
  final String path;
  final int atMs, width;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cached = Thumbs.instance.peek(path, atMs: atMs, width: width);
    if (cached != null) return _img(cached);
    return FutureBuilder<Uint8List?>(
      future: Thumbs.instance.get(path, atMs: atMs, width: width),
      builder: (context, snap) {
        if (snap.data != null) return _img(snap.data!);
        return Container(
          color: context.c.surfaceHi,
          child: snap.connectionState == ConnectionState.done
              ? Icon(Icons.movie_rounded, color: context.c.textFaint)
              : null,
        );
      },
    );
  }

  Widget _img(Uint8List bytes) => Image.memory(
    bytes,
    fit: fit,
    gaplessPlayback: true,
    width: double.infinity,
    height: double.infinity,
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: context.c.textFaint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// Primary call-to-action with the brand gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.gradient,
    this.expand = true,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final bool expand;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: 56,
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: gradient ?? L.brand,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: L.rose.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.c.text;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: (color ?? context.c.text).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bottom sheet with a list of selectable options. Returns the chosen value.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<OptionItem<T>> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ctx.t.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: ctx.c.textDim)),
            ],
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final o in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OptionTile(
                          item: o,
                          selected: o.value == selected,
                          onTap: () => Navigator.pop(ctx, o.value),
                        ),
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

class OptionItem<T> {
  const OptionItem(
    this.value,
    this.label, {
    this.hint,
    this.icon,
    this.badge,
    this.enabled = true,
  });
  final T value;
  final String label;
  final String? hint, badge;
  final IconData? icon;
  final bool enabled;
}

class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final OptionItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      scale: 0.98,
      onTap: item.enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? L.primary.withValues(alpha: 0.14) : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? L.primary : c.stroke,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, color: selected ? L.primary : c.textDim),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.badge != null) ...[
                        const SizedBox(width: 8),
                        Pill(
                          color: L.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          child: Text(item.badge!),
                        ),
                      ],
                    ],
                  ),
                  if (item.hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.hint!,
                      style: TextStyle(color: c.textDim, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: L.primary,
                      key: const ValueKey(1),
                    )
                  : Icon(
                      Icons.circle_outlined,
                      color: c.textFaint,
                      key: const ValueKey(0),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void toast(
  BuildContext context,
  String message, {
  IconData? icon,
  bool error = false,
}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            icon ??
                (error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded),
            color: error ? L.rose : L.mint,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool destructive = true,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: ctx.t.titleLarge),
      content: Text(message, style: TextStyle(color: ctx.c.textDim)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: TextStyle(color: ctx.c.textDim)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            action,
            style: TextStyle(
              color: destructive ? L.rose : L.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}
