import 'package:bstream_music/core/theme/app_theme.dart';
import 'package:bstream_music/core/widgets/liquid_glass_surface.dart';
import 'package:bstream_music/features/music/presentation/widgets/player_controls_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final mode in SurfaceBackgroundMode.values) {
      testWidgets('circular actions follow $mode surfaces in $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: brightness,
              ),
              extensions: [AppSurfaceTheme(backgroundMode: mode)],
            ),
            home: const Scaffold(
              body: Center(
                child: PlayerActionSurface(
                  key: ValueKey('action-surface'),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(Icons.favorite_border_rounded),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.getSize(find.byKey(const ValueKey('action-surface'))),
          const Size.square(40),
        );
        expect(
          find.byType(LiquidGlassSurface),
          mode.isLiquidGlass ? findsOneWidget : findsNothing,
        );
        if (!mode.isLiquidGlass) {
          expect(
            find.byType(BackdropFilter),
            mode.usesBackdrop ? findsOneWidget : findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
