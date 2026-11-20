import 'package:flutter/material.dart';
import '../../../../core/widgets/app_shared_widgets.dart';

/// A neutral, transparent pill that lets the player's existing backdrop show
/// through without introducing another artwork hue or decoding another image.
class PlayerControlsCapsule extends StatelessWidget {
  const PlayerControlsCapsule({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: .05)
            : Colors.black.withValues(alpha: .04),
        borderRadius: const BorderRadius.all(Radius.circular(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );
  }
}

/// Circular playback actions follow the app's configured surface material.
class PlayerActionSurface extends StatelessWidget {
  const PlayerActionSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppInsetHeaderSurface(
    padding: EdgeInsets.zero,
    borderRadius: 999,
    child: child,
  );
}
