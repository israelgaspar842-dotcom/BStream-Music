import 'package:bstream_music/features/music/presentation/widgets/player_dismiss_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _handleKey = ValueKey('test-player-handle');

void main() {
  testWidgets('slow downward drag follows the pointer and dismisses once', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 35));
    await tester.pump();
    await gesture.moveTo(start + const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_translation(tester), closeTo(90, 0.1));
    expect(dismissed, 0);
    await gesture.up();
    await tester.pump();
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short slow drag returns without dismissing', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 35));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_translation(tester), 0);
    expect(dismissed, 0);
  });

  testWidgets('an upward drag never dismisses or moves the player upward', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start - const Offset(0, 100));
    await tester.pump();
    expect(_translation(tester), 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dismissed, 0);
  });

  testWidgets('a quick downward flick needs intentional movement', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    await tester.fling(find.byKey(_handleKey), const Offset(0, 45), 700);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('holding after a short fast drag does not use stale velocity', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    for (var index = 1; index <= 5; index++) {
      await gesture.moveTo(
        start + Offset(0, index * 9.0),
        timeStamp: Duration(milliseconds: index * 15),
      );
      await tester.pump(const Duration(milliseconds: 15));
    }
    expect(_translation(tester), closeTo(45, 0.1));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up(timeStamp: const Duration(milliseconds: 575));
    await tester.pumpAndSettle();
    expect(dismissed, 0);
    expect(_translation(tester), 0);
  });

  testWidgets('tap and keyboard activation use the collapse action', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
    await tester.tap(find.byKey(_handleKey));
    expect(dismissed, 1);
    final detector = find.descendant(
      of: find.byKey(_handleKey),
      matching: find.byType(FocusableActionDetector),
    );
    final focus = tester.widget<FocusableActionDetector>(detector);
    final focusElement = tester.element(
      find.descendant(of: detector, matching: find.byType(GestureDetector)),
    );
    Focus.of(focusElement).requestFocus();
    await tester.pump();
    expect(focus.shortcuts, isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(dismissed, 2);
  });

  testWidgets('a cancelled drag resets and reduced motion skips settling', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      _harness(onDismiss: () => dismissed++, reducedMotion: true),
    );
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 35));
    await tester.pump();
    expect(_translation(tester), greaterThan(0));
    await gesture.cancel();
    await tester.pump();
    expect(_translation(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(dismissed, 0);
  });

  testWidgets('decorative handles do not capture taps or drags', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(onDismiss: null));
    expect(
      find.descendant(
        of: find.byKey(_handleKey),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
    await tester.drag(find.byKey(_handleKey), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(_translation(tester), 0);
  });

  testWidgets(
    'deactivation resets an unfinished drag and a new visit is clean',
    (tester) async {
      var dismissed = 0;
      void dismiss() => dismissed++;
      await tester.pumpWidget(_harness(onDismiss: dismiss));
      final start = tester.getCenter(find.byKey(_handleKey));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(0, 35));
      await tester.pump();
      await tester.pumpWidget(_harness(onDismiss: dismiss, active: false));
      expect(_translation(tester), 0);
      await gesture.up();
      await tester.pumpWidget(_harness(onDismiss: dismiss));
      expect(_translation(tester), 0);
      await tester.drag(find.byKey(_handleKey), const Offset(0, 100));
      await tester.pump();
      expect(dismissed, 1);
      await tester.pumpWidget(_harness(onDismiss: dismiss, active: false));
      await tester.pumpWidget(_harness(onDismiss: dismiss));
      expect(_translation(tester), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging transforms the player without rebuilding its content', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      _harness(
        onDismiss: () {},
        child: Builder(
          builder: (context) {
            builds++;
            return const Align(
              alignment: Alignment.topCenter,
              child: PlayerCollapseHandle(
                key: _handleKey,
                label: 'Minimizar reproductor',
                onCollapse: _noop,
              ),
            );
          },
        ),
      ),
    );
    final initialBuilds = builds;
    final start = tester.getCenter(find.byKey(_handleKey));
    final gesture = await tester.startGesture(start);
    for (final offset in [25.0, 40.0, 55.0]) {
      await gesture.moveTo(start + Offset(0, offset));
      await tester.pump();
    }
    expect(builds, initialBuilds);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(builds, initialBuilds);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removing the action cancels settling and disposal leaves no ticker',
    (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(_harness(onDismiss: () => dismissed++));
      final start = tester.getCenter(find.byKey(_handleKey));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(0, 35));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(_harness(onDismiss: null));
      expect(_translation(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(dismissed, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

void _noop() {}

double _translation(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('player-dismiss-translation')))
    .transform
    .getTranslation()
    .y;

Widget _harness({
  required VoidCallback? onDismiss,
  bool active = true,
  bool reducedMotion = false,
  Widget? child,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: PlayerDismissRegion(
        active: active,
        onDismiss: onDismiss,
        child:
            child ??
            Align(
              alignment: Alignment.topCenter,
              child: PlayerCollapseHandle(
                key: _handleKey,
                label: 'Minimizar reproductor',
                onCollapse: onDismiss,
              ),
            ),
      ),
    ),
  ),
);
