import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Accent palettes the user can pick in Settings → Appearance.
enum Accent {
  aurora('Aurora', [Color(0xFF7C5CFF), Color(0xFFFF4D6D), Color(0xFFFFA94D)]),
  ocean('Ocean', [Color(0xFF3B82F6), Color(0xFF06B6D4), Color(0xFF34D399)]),
  sunset('Sunset', [Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFEC4899)]),
  royal('Royal', [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFD946EF)]),
  forest('Forest', [Color(0xFF10B981), Color(0xFF14B8A6), Color(0xFF84CC16)]),
  graphite('Graphite', [
    Color(0xFF64748B),
    Color(0xFF94A3B8),
    Color(0xFFCBD5E1),
  ]);

  const Accent(this.label, this.colors);
  final String label;
  final List<Color> colors;

  LinearGradient get gradient => LinearGradient(
    colors: colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Reelmint design tokens. [primary] and [brand] follow the selected [Accent];
/// the semantic colours (record red, pause amber, success mint) are fixed.
class L {
  static Accent accent = Accent.aurora;

  static Color get primary => accent.colors.first;
  static LinearGradient get brand => accent.gradient;

  static const rose = Color(0xFFFF4D6D);
  static const amber = Color(0xFFFFA94D);
  static const mint = Color(0xFF2EE6A8);
  static const sky = Color(0xFF4DABF7);

  static const recordGradient = LinearGradient(
    colors: [Color(0xFFFF5F7E), Color(0xFFFF2D55)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const radius = 22.0;
  static const tabular = [FontFeature.tabularFigures()];
}

/// Theme-dependent colours, read with `context.c`.
@immutable
class ReelmintColors extends ThemeExtension<ReelmintColors> {
  const ReelmintColors({
    required this.bg,
    required this.bgGlow,
    required this.surface,
    required this.surfaceHi,
    required this.stroke,
    required this.text,
    required this.textDim,
    required this.textFaint,
  });

  final Color bg, bgGlow, surface, surfaceHi, stroke, text, textDim, textFaint;

  static const dark = ReelmintColors(
    bg: Color(0xFF0A0910),
    bgGlow: Color(0xFF1B1430),
    surface: Color(0x14FFFFFF),
    surfaceHi: Color(0x22FFFFFF),
    stroke: Color(0x1FFFFFFF),
    text: Color(0xFFF7F5FF),
    textDim: Color(0xB3EDEAFF),
    textFaint: Color(0x66EDEAFF),
  );

  static const light = ReelmintColors(
    bg: Color(0xFFF5F3FB),
    bgGlow: Color(0xFFE9E2FF),
    surface: Color(0xB3FFFFFF),
    surfaceHi: Color(0xFFFFFFFF),
    stroke: Color(0x14000000),
    text: Color(0xFF14121C),
    textDim: Color(0xA614121C),
    textFaint: Color(0x5914121C),
  );

  @override
  ReelmintColors copyWith() => this;

  @override
  ReelmintColors lerp(ThemeExtension<ReelmintColors>? other, double t) {
    if (other is! ReelmintColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ReelmintColors(
      bg: l(bg, other.bg),
      bgGlow: l(bgGlow, other.bgGlow),
      surface: l(surface, other.surface),
      surfaceHi: l(surfaceHi, other.surfaceHi),
      stroke: l(stroke, other.stroke),
      text: l(text, other.text),
      textDim: l(textDim, other.textDim),
      textFaint: l(textFaint, other.textFaint),
    );
  }
}

extension ReelmintContext on BuildContext {
  ReelmintColors get c => Theme.of(this).extension<ReelmintColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  TextTheme get t => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? ReelmintColors.dark : ReelmintColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(
      seedColor: L.primary,
      brightness: b,
      primary: L.primary,
      secondary: L.rose,
      surface: c.bg,
    ),
    scaffoldBackgroundColor: c.bg,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
  );
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
      ),
      headlineLarge: text.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: c.text,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF15131F) : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.textFaint,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF17151F) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF221F2E) : const Color(0xFF1C1A24),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? L.primary : c.surfaceHi,
      ),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: L.primary,
      inactiveTrackColor: c.surfaceHi,
      thumbColor: Colors.white,
      overlayColor: L.primary.withValues(alpha: 0.15),
      trackHeight: 4,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: c.textFaint),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()},
    ),
  );
}
