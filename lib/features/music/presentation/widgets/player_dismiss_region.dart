import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind, VelocityTracker;
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Moves the existing player subtree while its top handle is dragged. Only the
/// transform listens to the animation; artwork and controls are not rebuilt.
class PlayerDismissRegion extends StatefulWidget {
  const PlayerDismissRegion({
    required this.child,
    required this.onDismiss,
    this.active = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onDismiss;
  final bool active;

  @override
  State<PlayerDismissRegion> createState() => _PlayerDismissRegionState();
}

class _PlayerDismissRegionState extends State<PlayerDismissRegion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _translation = AnimationController.unbounded(
    vsync: this,
  );
  double? _dragStartY;
  VelocityTracker? _globalVelocity;
  bool _dismissed = false;

  bool get _enabled => widget.active && widget.onDismiss != null && !_dismissed;

  @override
  void didUpdateWidget(covariant PlayerDismissRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || widget.onDismiss == null) {
      _translation.stop();
      _dragStartY = null;
      _globalVelocity = null;
      // Keep a committed drag's final frame while the parent transitions out.
      if (!_dismissed || widget.onDismiss == null) _translation.value = 0;
    }
    if ((!oldWidget.active && widget.active) ||
        (oldWidget.onDismiss == null && widget.onDismiss != null)) {
      _dismissed = false;
      _translation.value = 0;
    }
  }

  @override
  void dispose() {
    _translation.dispose();
    super.dispose();
  }

  void _start(DragStartDetails details) {
    if (!_enabled) return;
    _translation.stop();
    _translation.value = 0;
    _dragStartY = details.globalPosition.dy;
    _globalVelocity = VelocityTracker.withKind(
      details.kind ?? PointerDeviceKind.touch,
    );
    final timeStamp = details.sourceTimeStamp;
    if (timeStamp != null) {
      _globalVelocity!.addPosition(timeStamp, details.globalPosition);
    }
  }

  void _update(DragUpdateDetails details) {
    final startY = _dragStartY;
    if (!_enabled || startY == null) return;
    final timeStamp = details.sourceTimeStamp;
    if (timeStamp != null) {
      _globalVelocity?.addPosition(timeStamp, details.globalPosition);
    }
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    _translation.value = (details.globalPosition.dy - startY)
        .clamp(0.0, height)
        .toDouble();
  }

  void _end(DragEndDetails details) {
    if (_dragStartY == null) return;
    _dragStartY = null;
    final offset = _translation.value;
    // Flutter's recognizer estimates velocity in the handle's local space.
    // That space follows this transform, so measure the real pointer motion.
    final velocity =
        _globalVelocity?.getVelocityEstimate()?.pixelsPerSecond.dy ??
        details.primaryVelocity ??
        0;
    _globalVelocity = null;
    if (_enabled && (offset >= 64 || (offset >= 12 && velocity > 400))) {
      _dismissed = true;
      widget.onDismiss?.call();
      return;
    }
    _returnToOrigin();
  }

  void _cancel() {
    _dragStartY = null;
    _globalVelocity = null;
    _returnToOrigin();
  }

  void _returnToOrigin() {
    if (_translation.value == 0) return;
    if (!widget.active ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _translation.value = 0;
      return;
    }
    _translation.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PlayerDismissScope(
      state: this,
      enabled: _enabled,
      child: AnimatedBuilder(
        animation: _translation,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          key: const ValueKey('player-dismiss-translation'),
          offset: Offset(0, _translation.value),
          child: child,
        ),
      ),
    );
  }
}

class _PlayerDismissScope extends InheritedWidget {
  const _PlayerDismissScope({
    required this.state,
    required this.enabled,
    required super.child,
  });

  final _PlayerDismissRegionState state;
  final bool enabled;

  static _PlayerDismissScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlayerDismissScope>();

  @override
  bool updateShouldNotify(_PlayerDismissScope oldWidget) =>
      oldWidget.enabled != enabled || oldWidget.state != state;
}

/// Shared top affordance for tapping or dragging the full player down.
class PlayerCollapseHandle extends StatelessWidget {
  const PlayerCollapseHandle({
    required this.label,
    required this.onCollapse,
    super.key,
  });

  final String label;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final scope = _PlayerDismissScope.maybeOf(context);
    final collapse = scope != null && !scope.enabled ? null : onCollapse;
    final indicator = SizedBox(
      width: 96,
      height: 20,
      child: Center(
        child: Container(
          width: 52,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.playbackControlForegroundFor(
              context,
            ).withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
    if (collapse == null) return ExcludeSemantics(child: indicator);

    return Semantics(
      button: true,
      label: label,
      onTap: collapse,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                collapse();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            excludeFromSemantics: true,
            onTap: collapse,
            onVerticalDragStart: scope?.state._start,
            onVerticalDragUpdate: scope?.state._update,
            onVerticalDragEnd: scope?.state._end,
            onVerticalDragCancel: scope?.state._cancel,
            child: indicator,
          ),
        ),
      ),
    );
  }
}
