import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bstream_music/services/local_media/desktop_device_audio_catalog.dart';
import 'package:bstream_music/services/local_media/device_audio_catalog.dart';
import 'package:bstream_music/services/local_media/device_audio_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('shares the scan while its music roots are still loading', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bstream-device-audio-concurrent-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    await File(p.join(temporary.path, 'Artist - Song.mp3')).writeAsBytes([1]);
    final roots = Completer<List<Directory>>();
    var rootsCalls = 0;
    final catalog = DesktopDeviceAudioCatalog(() {
      rootsCalls++;
      return roots.future;
    });

    final filtered = catalog.load();
    final unfiltered = catalog.load(
      options: const DeviceAudioFilterOptions(excludeShortAudio: false),
    );
    final refreshed = catalog.refresh();
    expect(rootsCalls, 1);
    roots.complete([temporary]);
    final results = await Future.wait([filtered, unfiltered, refreshed]);

    expect(rootsCalls, 1);
    expect(results.every((result) => result.tracks.length == 1), isTrue);
    await catalog.refresh();
    expect(rootsCalls, 2, reason: 'a later refresh still forces a new scan');
  });

  test('shares the next scan when an exclusion root changes', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bstream-device-audio-roots-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final firstRoot = Directory(p.join(temporary.path, 'First'));
    final secondRoot = Directory(p.join(temporary.path, 'Second'));
    await firstRoot.create();
    await secondRoot.create();
    await File(p.join(firstRoot.path, 'First.mp3')).writeAsBytes([1]);
    await File(p.join(secondRoot.path, 'Second.mp3')).writeAsBytes([1]);
    final initialRoots = Completer<List<Directory>>();
    final nextRoots = Completer<List<Directory>>();
    final nextStarted = Completer<void>();
    var rootsCalls = 0;
    final catalog = DesktopDeviceAudioCatalog(() {
      rootsCalls++;
      if (rootsCalls == 1) return initialRoots.future;
      if (!nextStarted.isCompleted) nextStarted.complete();
      return nextRoots.future;
    });

    final first = catalog.load(bstreamRoot: firstRoot.path);
    final second = catalog.load(bstreamRoot: secondRoot.path);
    final concurrentSecond = catalog.load(bstreamRoot: secondRoot.path);
    expect(rootsCalls, 1);
    initialRoots.complete([temporary]);
    final initial = await first;
    await nextStarted.future;
    expect(rootsCalls, 2);
    nextRoots.complete([temporary]);
    final next = await Future.wait([second, concurrentSecond]);

    expect(initial.tracks.single.title, 'Second');
    expect(
      next.every((result) => result.tracks.single.title == 'First'),
      isTrue,
    );
    expect(rootsCalls, 2);
  });

  test('retries a roots lookup after a shared failure', () async {
    final failedRoots = Completer<List<Directory>>();
    var rootsCalls = 0;
    final catalog = DesktopDeviceAudioCatalog(() {
      rootsCalls++;
      return rootsCalls == 1 ? failedRoots.future : Future.value([]);
    });
    final first = catalog.load();
    final second = catalog.load();
    final failures = [
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ];
    failedRoots.completeError(StateError('Music roots unavailable'));
    await Future.wait(failures);

    expect((await catalog.load()).tracks, isEmpty);
    expect(rootsCalls, 2);
  });

  test('scans Music recursively and prunes the managed BStream root', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'bstream-device-audio-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final music = Directory(p.join(temporary.path, 'Music'));
    final album = Directory(p.join(music.path, 'Album'));
    final managed = Directory(
      p.join(music.path, 'Downloads', 'BStream-Music', 'audio'),
    );
    await album.create(recursive: true);
    await managed.create(recursive: true);
    await File(
      p.join(album.path, 'Artist - Clear Title.mp3'),
    ).writeAsBytes(const <int>[1]);
    await File(p.join(album.path, 'ignore.txt')).writeAsString('not audio');
    await File(
      p.join(managed.path, 'Managed - Hidden.m4a'),
    ).writeAsBytes(const <int>[1]);

    var rootsCalls = 0;
    final catalog = DesktopDeviceAudioCatalog(() async {
      rootsCalls += 1;
      return <Directory>[music];
    });
    final result = await catalog.load(
      bstreamRoot: p.join(music.path, 'Downloads', 'BStream-Music'),
    );

    expect(result.status, DeviceAudioPermissionStatus.notRequired);
    expect(result.tracks, hasLength(1));
    final track = result.tracks.single;
    expect(track.title, 'Clear Title');
    expect(track.artist, 'Artist');
    expect(track.folderName, 'Album');
    expect(track.relativePath, 'Album');
    expect(track.duration, isNull);
    expect(track.uri, p.join(album.path, 'Artist - Clear Title.mp3'));

    await catalog.load();
    expect(rootsCalls, 2, reason: 'changing the excluded root rescans safely');
    await catalog.load();
    expect(rootsCalls, 2, reason: 'the raw session snapshot is reused');
    await catalog.refresh();
    expect(rootsCalls, 3, reason: 'only refresh forces a new filesystem scan');
  });

  test(
    'reads desktop duration without loading audio into the catalog',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'bstream-device-audio-metadata-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final music = Directory(p.join(temporary.path, 'Music'));
      await music.create(recursive: true);
      await File(
        p.join(music.path, 'Tone.wav'),
      ).writeAsBytes(_pcmWave(duration: const Duration(seconds: 2)));

      final result = await DesktopDeviceAudioCatalog(
        () async => <Directory>[music],
      ).load(options: const DeviceAudioFilterOptions(excludeShortAudio: false));

      expect(result.tracks, hasLength(1));
      expect(result.tracks.single.title, 'Tone');
      expect(result.tracks.single.duration, const Duration(seconds: 2));
    },
  );
}

Uint8List _pcmWave({required Duration duration}) {
  const sampleRate = 8000;
  const channelCount = 1;
  const bitsPerSample = 8;
  const blockAlign = channelCount * bitsPerSample ~/ 8;
  const byteRate = sampleRate * blockAlign;
  final dataLength = byteRate * duration.inMilliseconds ~/ 1000;
  final data = ByteData(44 + dataLength);

  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channelCount, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  return data.buffer.asUint8List();
}
