import 'package:bstream_music/features/music/presentation/providers/playback_artwork_provider.dart';
import 'dart:async';

import 'package:bstream_music/features/music/presentation/providers/audio_route_providers.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:bstream_music/features/music/presentation/widgets/audio_routing_menus.dart';
import 'package:bstream_music/features/music/presentation/widgets/playback_menu_bottom_sheet.dart';
import 'package:bstream_music/services/audio_output/audio_output_service.dart';
import 'package:bstream_music/services/player/player_audio_output.dart';
import 'package:bstream_music/services/player/player_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _devices = [
  PlayerAudioDevice(id: systemDefaultAudioDeviceId, name: ''),
  PlayerAudioDevice(id: 'speakers', name: 'Altavoces USB'),
];

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform opens player outputs without system audio calls', (
      tester,
    ) async {
      final player = _Player();
      final system = _SystemOutput();
      addTearDown(player.dispose);
      addTearDown(system.dispose);
      await _open(tester, player, system, platform: platform);
      expect(find.text('Salida de audio'), findsOneWidget);
      expect(find.text('Predeterminada del sistema'), findsOneWidget);
      expect(find.text('Altavoces USB'), findsOneWidget);
      expect(find.text('Este teléfono'), findsNothing);
      expect(find.text('Volumen del reproductor'), findsOneWidget);
      expect(system.calls, 0);

      await tester.tap(
        find.byKey(const ValueKey('desktop-audio-output-route-speakers')),
      );
      await tester.pumpAndSettle();
      expect(player.selections, ['speakers']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('desktop-audio-output-route-speakers')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(system.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('player volume stays synchronized and writes only on release', (
    tester,
  ) async {
    final player = _Player();
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system);
    final sliderFinder = find.byKey(
      const ValueKey('desktop-audio-output-volume'),
    );
    expect(tester.widget<Slider>(sliderFinder).value, .6);
    player.emitSnapshot(player.currentSnapshot.copyWith(volume: .4));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, .4);
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(.7);
    slider.onChanged!(.8);
    expect(player.volumes, isEmpty);
    slider.onChangeEnd!(.8);
    await tester.pumpAndSettle();
    expect(player.volumes, [.8]);
    expect(tester.widget<Slider>(sliderFinder).value, .8);
    expect(system.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('device list updates while open and default remains available', (
    tester,
  ) async {
    final player = _Player();
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system);
    player.emitOutputs(
      const PlayerAudioOutputState(
        supported: true,
        selectedDeviceId: 'headphones',
        devices: [
          PlayerAudioDevice(id: 'headphones', name: 'Audífonos Bluetooth'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Altavoces USB'), findsNothing);
    expect(find.text('Audífonos Bluetooth'), findsOneWidget);
    expect(find.text('Predeterminada del sistema'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('desktop-audio-output-route-auto')),
    );
    await tester.pumpAndSettle();
    expect(player.selections, [systemDefaultAudioDeviceId]);
    expect(
      player.audioOutputState.selectedDeviceId,
      systemDefaultAudioDeviceId,
    );
    expect(system.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed selection keeps the previous device and can be retried', (
    tester,
  ) async {
    final player = _Player()..failSelection = true;
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system);
    final speakers = find.byKey(
      const ValueKey('desktop-audio-output-route-speakers'),
    );
    await tester.tap(speakers);
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo actualizar el audio del reproductor.'),
      findsOneWidget,
    );
    expect(
      player.audioOutputState.selectedDeviceId,
      systemDefaultAudioDeviceId,
    );
    expect(
      find.descendant(of: speakers, matching: find.byIcon(Icons.check_rounded)),
      findsNothing,
    );
    player.failSelection = false;
    await tester.tap(speakers);
    await tester.pumpAndSettle();
    expect(player.audioOutputState.selectedDeviceId, 'speakers');
    expect(
      find.text('No se pudo actualizar el audio del reproductor.'),
      findsNothing,
    );
    expect(system.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop menu fits small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = _Player();
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system, scale: 1.8);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('desktop-audio-output-volume')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile picker still uses the native output selector', (
    tester,
  ) async {
    final player = _Player();
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system, platform: TargetPlatform.android);
    expect(system.calls, 1);
    expect(find.byType(DesktopAudioOutputMenu), findsNothing);
    expect(player.selections, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unsupported output capability reports unavailable', (
    tester,
  ) async {
    final player = _Player()..emitOutputs(const PlayerAudioOutputState());
    final system = _SystemOutput();
    addTearDown(player.dispose);
    addTearDown(system.dispose);
    await _open(tester, player, system);
    expect(
      find.text('No se pudieron consultar las salidas de audio.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-audio-output-route-auto')),
      findsNothing,
    );
    expect(system.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _open(
  WidgetTester tester,
  _Player player,
  _SystemOutput system, {
  TargetPlatform platform = TargetPlatform.windows,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStringsProvider.overrideWithValue(
          const AppStrings(AppLanguage.spanish),
        ),
        playerServiceProvider.overrideWithValue(player),
        audioOutputServiceProvider.overrideWithValue(system),
        playbackArtworkProvider.overrideWithValue((
          source: null,
          fallback: null,
        )),
        playbackMenuArtworkColorProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform, brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => showAudioOutputPicker(context, ref),
                child: const Text('Abrir salidas'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir salidas'));
  await tester.pumpAndSettle();
}

class _Player extends Fake implements PlayerService, PlayerAudioOutput {
  final _outputs = StreamController<PlayerAudioOutputState>.broadcast();
  final _snapshots = StreamController<PlayerSnapshot>.broadcast();
  final selections = <String>[];
  final volumes = <double>[];
  bool failSelection = false;

  @override
  PlayerAudioOutputState audioOutputState = const PlayerAudioOutputState(
    supported: true,
    devices: _devices,
  );

  @override
  PlayerSnapshot currentSnapshot = const PlayerSnapshot(
    status: PlayerStatus.playing,
    volume: .6,
  );

  @override
  Stream<PlayerAudioOutputState> get audioOutputStream => _outputs.stream;

  @override
  Stream<PlayerSnapshot> get snapshotStream => _snapshots.stream;

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    selections.add(deviceId);
    if (failSelection) throw StateError('device unavailable');
    emitOutputs(
      PlayerAudioOutputState(
        supported: true,
        devices: audioOutputState.devices,
        selectedDeviceId: deviceId,
      ),
    );
  }

  void emitOutputs(PlayerAudioOutputState state) {
    audioOutputState = state;
    _outputs.add(state);
  }

  void emitSnapshot(PlayerSnapshot snapshot) {
    currentSnapshot = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    emitSnapshot(currentSnapshot.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    await _outputs.close();
    await _snapshots.close();
  }
}

class _SystemOutput extends AudioOutputService {
  int calls = 0;

  @override
  Future<bool> showSystemPicker() async {
    calls++;
    return true;
  }

  @override
  Future<AudioOutputState> startWatching() async {
    calls++;
    return const AudioOutputState();
  }

  @override
  Future<void> setVolume(double value) async {
    calls++;
  }
}
