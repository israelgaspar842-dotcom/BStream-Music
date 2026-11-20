import 'dart:io';
import 'package:bstream_music/features/music/domain/entities/local_track.dart';
import 'package:bstream_music/services/player/media_kit_player_service.dart';
import 'package:bstream_music/services/player/player_audio_output.dart';
import 'package:bstream_music/services/player/player_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises real desktop device enumeration and both crossfade decks using
/// silent PCM. Never changes the system default device or system volume.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop player output survives playback and crossfade', (
    tester,
  ) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    const headless = bool.fromEnvironment('BSTREAM_HEADLESS_AUDIO');
    const trackDuration = Duration(milliseconds: 2600);
    final directory = await Directory.systemTemp.createTemp(
      'bstream_desktop_output_',
    );
    final files = <File>[];
    final service = MediaKitPlayerService();
    final output = service as PlayerAudioOutput;
    final observedOutputs = <PlayerAudioOutputState>[];
    final subscription = output.audioOutputStream.listen(observedOutputs.add);
    try {
      // Enumeration must work before opening media. Native media_kit initially
      // exposes only `auto`; wait for its actual device list on real hardware.
      await _waitUntil(
        () =>
            output.audioOutputState.supported &&
            output.audioOutputState.devices.any(
              (device) => device.id == systemDefaultAudioDeviceId,
            ) &&
            (headless ||
                output.audioOutputState.devices.any(
                  (device) => device.id != systemDefaultAudioDeviceId,
                )),
        reason: 'Idle device enumeration',
      );
      expect(service.currentSnapshot.status, PlayerStatus.idle);

      await output.selectAudioOutput(systemDefaultAudioDeviceId);
      expect(
        output.audioOutputState.selectedDeviceId,
        systemDefaultAudioDeviceId,
      );
      final physicalDevices = output.audioOutputState.devices
          .where((device) => device.id != systemDefaultAudioDeviceId)
          .toList();
      final selectedId = physicalDevices.isEmpty
          ? systemDefaultAudioDeviceId
          : physicalDevices.first.id;
      await output.selectAudioOutput(selectedId);
      expect(output.audioOutputState.selectedDeviceId, selectedId);
      await expectLater(
        output.selectAudioOutput('bstream-nonexistent-output-device'),
        throwsA(isA<ArgumentError>()),
      );
      expect(output.audioOutputState.selectedDeviceId, selectedId);

      final tracks = <LocalTrack>[];
      for (var index = 0; index < 2; index++) {
        final file = File(
          '${directory.path}${Platform.pathSeparator}silence-$index.wav',
        );
        files.add(file);
        await file.writeAsBytes(_silentWave(trackDuration));
        tracks.add(
          LocalTrack(
            id: 'desktop-output-$index',
            title: 'Silent desktop output fixture $index',
            artist: 'BStream integration test',
            filePath: file.path,
            duration: trackDuration,
            addedAt: DateTime(2026),
          ),
        );
      }

      await service.setVolume(.35);
      await service.playLocal(tracks.first);
      await _waitUntil(
        () => service.currentSnapshot.position > Duration.zero,
        reason: 'Silent PCM playback clock',
      );
      expect(service.currentSnapshot.status, PlayerStatus.playing);
      expect(service.currentSnapshot.volume, closeTo(.35, .001));

      // Changing only this player's output keeps its source and logical gain.
      await output.selectAudioOutput(systemDefaultAudioDeviceId);
      await output.selectAudioOutput(selectedId);
      expect(service.currentSnapshot.trackId, tracks.first.id);
      expect(service.currentSnapshot.status, PlayerStatus.playing);
      await service.setVolume(.22);
      expect(service.currentSnapshot.volume, closeTo(.22, .001));
      expect(output.audioOutputState.selectedDeviceId, selectedId);

      await service.configureCrossfade(
        enabled: true,
        duration: const Duration(milliseconds: 700),
      );
      await service.seek(Duration.zero);
      await service.prepareCrossfade(LocalCrossfadePlaybackSource(tracks[1]));
      expect(output.audioOutputState.selectedDeviceId, selectedId);
      // A selection while the next deck is already prepared must reach it too.
      await output.selectAudioOutput(systemDefaultAudioDeviceId);
      await output.selectAudioOutput(selectedId);
      await service.seek(const Duration(milliseconds: 1950));
      await service.prepareCrossfade(LocalCrossfadePlaybackSource(tracks[1]));
      await _waitUntil(
        () => service.currentSnapshot.trackId == tracks[1].id,
        reason: 'Crossfade promotion',
      );
      expect(service.currentSnapshot.status, PlayerStatus.playing);
      expect(service.currentSnapshot.position, greaterThan(Duration.zero));
      expect(service.currentSnapshot.volume, closeTo(.22, .001));
      expect(output.audioOutputState.selectedDeviceId, selectedId);
      expect(
        observedOutputs.any((state) => state.selectedDeviceId == selectedId),
        isTrue,
      );
      await service.stop();

      debugPrint(
        'DESKTOP_AUDIO_OUTPUT_NATIVE_OK '
        'physicalDevices=${physicalDevices.length} '
        'explicitDevice=${selectedId != systemDefaultAudioDeviceId} '
        'headless=$headless; silent playback and crossfade verified. '
        'Physical audibility and unplug recovery require a hardware check.',
      );
    } finally {
      await subscription.cancel();
      await service.dispose();
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
      if (await directory.exists()) await directory.delete();
    }
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= const Duration(seconds: 8)) {
      fail('$reason did not complete within 8 seconds.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Uint8List _silentWave(Duration duration) {
  const sampleRate = 8000;
  const bytesPerSample = 2;
  final dataLength =
      sampleRate * duration.inMilliseconds ~/ 1000 * bytesPerSample;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  data.setUint16(32, bytesPerSample, Endian.little);
  data.setUint16(34, bytesPerSample * 8, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  return bytes;
}
