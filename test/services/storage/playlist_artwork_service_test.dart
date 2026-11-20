import 'dart:io';
import 'dart:ui' as ui;

import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:bstream_music/services/storage/playlist_artwork_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const service = PlaylistArtworkService();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bstream-playlist-artwork-');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'stores the exact approved square crop with a bounded PNG size',
    () async {
      final image = await _splitImage(2400, 1200);
      addTearDown(image.dispose);
      final name = await service.save(
        mediaRoot: root.path,
        image: image,
        crop: const ui.Rect.fromLTWH(.5, 0, .5, 1),
      );
      expect(Playlist.isValidCustomArtworkFileName(name), isTrue);
      final file = File('${root.path}/thumbnails/$name');
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, PlaylistArtworkService.maximumEdge);
        expect(frame.image.height, PlaylistArtworkService.maximumEdge);
        final data = (await frame.image.toByteData())!;
        final center =
            ((frame.image.width ~/ 2) * frame.image.width +
                frame.image.width ~/ 2) *
            4;
        expect(data.getUint8(center), lessThan(3));
        expect(data.getUint8(center + 1), lessThan(3));
        expect(data.getUint8(center + 2), greaterThan(252));
        expect(image.width, 2400); // Ownership remains with the crop editor.
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
      expect(
        (await Directory(
          '${root.path}/thumbnails',
        ).list().toList()).map((entry) => p.normalize(entry.path)),
        [p.normalize(file.path)],
      );
    },
  );

  test(
    'keeps small photos sharp and uses a new cache identity per save',
    () async {
      final image = await _splitImage(80, 40);
      addTearDown(image.dispose);
      final first = await service.save(
        mediaRoot: root.path,
        image: image,
        crop: const ui.Rect.fromLTWH(0, 0, .5, 1),
      );
      final second = await service.save(
        mediaRoot: root.path,
        image: image,
        crop: const ui.Rect.fromLTWH(.5, 0, .5, 1),
      );
      expect(first, isNot(second));
      final codec = await ui.instantiateImageCodec(
        await File('${root.path}/thumbnails/$first').readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 40);
      expect(frame.image.height, 40);
      frame.image.dispose();
      codec.dispose();
    },
  );

  test(
    'rejects invalid or nonsquare selections without creating a file',
    () async {
      final image = await _splitImage(80, 40);
      addTearDown(image.dispose);
      for (final crop in [
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        const ui.Rect.fromLTWH(-.1, 0, .5, 1),
        const ui.Rect.fromLTWH(0, 0, 0, 1),
      ]) {
        await expectLater(
          service.save(mediaRoot: root.path, image: image, crop: crop),
          throwsArgumentError,
        );
      }
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'resolves against the current root and only deletes owned images',
    () async {
      final folder = await Directory('${root.path}/thumbnails').create();
      const name = 'playlist_owned.png';
      final owned = await File('${folder.path}/$name').writeAsBytes([1]);
      final song = await File('${folder.path}/song.jpg').writeAsBytes([2]);
      for (final unowned in ['song.jpg', '../song.jpg', owned.path]) {
        expect(
          await service.resolve(mediaRoot: root.path, fileName: unowned),
          isNull,
        );
        await service.delete(mediaRoot: root.path, fileName: unowned);
      }
      expect(await song.exists(), isTrue);
      expect(await owned.exists(), isTrue);
      expect(
        await service.resolve(mediaRoot: root.path, fileName: name),
        p.normalize(owned.path),
      );
      await service.delete(mediaRoot: root.path, fileName: name);
      expect(await owned.exists(), isFalse);
      expect(await song.readAsBytes(), [2]);
      expect(
        await service.resolve(mediaRoot: root.path, fileName: name),
        isNull,
      );
    },
  );
}

Future<ui.Image> _splitImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
  canvas.drawRect(
    ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
