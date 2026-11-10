import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/scope.dart';
import 'app/theme.dart';
import 'services/library.dart';
import 'services/recorder.dart';
import 'services/settings.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final settings = await Settings.load();
  L.accent = settings.accent;
  final recorder = Recorder();
  await recorder.init();
  Thumbs.instance.recorder = recorder;
  final library = Library(recorder, settings);
  library.refresh();

  runApp(
    AppScope(
      recorder: recorder,
      settings: settings,
      library: library,
      child: const ReelmintApp(),
    ),
  );
}

class ReelmintApp extends StatelessWidget {
  const ReelmintApp({super.key});

  /// Accent colours are read at build time everywhere, so a change re-builds the
  /// whole tree in place (state such as the current tab is kept).
  static void _rebuildAll(BuildContext context) {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (L.accent != s.accent) {
          L.accent = s.accent;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _rebuildAll(context);
          });
        }
        return MaterialApp(
          title: 'Reelmint',
          debugShowCheckedModeBanner: false,
          themeMode: s.themeMode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: const _Root(),
        );
      },
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  Widget build(BuildContext context) {
    final s = context.settings;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: s.onboarded
          ? const LockGate(key: ValueKey('shell'), child: Shell())
          : OnboardingScreen(
              key: const ValueKey('onboarding'),
              onDone: () => setState(() => s.onboarded = true),
            ),
    );
  }
}
