import 'package:flutter/material.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';

/// Covers the app with a lock screen when App lock is on — at launch and after
/// the app has been in the background for more than [relockAfter].
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.child,
    this.relockAfter = const Duration(seconds: 30),
  });
  final Widget child;
  final Duration relockAfter;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = context.settings.appLock;
  DateTime? _leftAt;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _leftAt == null
          ? Duration.zero
          : DateTime.now().difference(_leftAt!);
      _leftAt = null;
      if (context.settings.appLock && away > widget.relockAfter && !_locked) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await context.recorder.authenticate();
    _prompting = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Keep the app alive (and its state) underneath, but hide it from view and accessibility.
        ExcludeSemantics(
          excluding: _locked,
          child: Offstage(offstage: _locked, child: widget.child),
        ),
        if (_locked) _LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AmbientBackground(
      intensity: 1.3,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: L.brand,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: L.primary.withValues(alpha: 0.4),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
              const SizedBox(height: 28),
              Text('Reelmint is locked', style: context.t.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Your recordings are private. Unlock with your fingerprint, face or screen lock.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.c.textDim, fontSize: 15),
              ),
              const Spacer(),
              GradientButton(
                label: 'Unlock',
                icon: Icons.fingerprint_rounded,
                onTap: onUnlock,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
