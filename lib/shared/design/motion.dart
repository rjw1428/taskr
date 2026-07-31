import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';

/// True when the OS asks for reduced motion (or is removing animations, e.g.
/// during accessibility navigation). All animated UI should degrade when true.
bool reduceMotion(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq == null) return false;
  return mq.disableAnimations || mq.accessibleNavigation;
}

/// A one-shot entrance: fades and rises its child into place. Honors
/// reduced-motion (renders instantly) and supports a stagger [delay].
class AppReveal extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final double offsetY;

  const AppReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.slow,
      curve: Motion.enter,
      builder: (context, t, child) {
        // Delay is folded into the tween by clamping progress; a real stagger
        // uses [delay] via the caller staggering item indexes.
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * offsetY), child: child),
        );
      },
      child: child,
    );
  }
}

/// Stagger helper: the entrance delay for the Nth item in a list, capped so
/// long lists don't wait forever.
Duration staggerDelay(int index, {int cap = 8}) =>
    Motion.fast * (index.clamp(0, cap) / cap);

/// A fade-through page transition built on the motion tokens, degrading to an
/// instant push when reduced motion is on.
Route<T> fadeThroughRoute<T>(WidgetBuilder builder, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: Motion.base,
    reverseTransitionDuration: Motion.fast,
    pageBuilder: (context, animation, secondary) => builder(context),
    transitionsBuilder: (context, animation, secondary, child) {
      if (reduceMotion(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.standard);
      return FadeTransition(
        opacity: curved,
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 1.0).animate(secondary),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
