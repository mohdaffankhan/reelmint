import 'package:flutter/widgets.dart';

import '../services/library.dart';
import '../services/recorder.dart';
import '../services/settings.dart';

/// Hands the app-wide services down the tree.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.recorder,
    required this.settings,
    required this.library,
    required super.child,
  });

  final Recorder recorder;
  final Settings settings;
  final Library library;

  static AppScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}

extension ScopeX on BuildContext {
  Recorder get recorder => AppScope.of(this).recorder;
  Settings get settings => AppScope.of(this).settings;
  Library get library => AppScope.of(this).library;
}
