import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../features/music/domain/entities/playlist.dart';

/// Stores an approved square crop without decoding the selected photo again.
/// Persist only the returned name; its directory can move with the media root.
class PlaylistArtworkService {
  const PlaylistArtworkService();

  static const maximumEdge = 1024;

  Future<String> save({
    required String mediaRoot,
    required ui.Image image,
    required ui.Rect crop,
  }) async {
    if (mediaRoot.trim().isEmpty ||
        !crop.isFinite ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        crop.left < -0.000001 ||
        crop.top < -0.000001 ||
        crop.right > 1.000001 ||
        crop.bottom > 1.000001) {
      throw ArgumentError('The selected artwork crop is invalid.');
    }
    final source =
        ui.Rect.fromLTRB(
          crop.left * image.width,
          crop.top * image.height,
          crop.right * image.width,
          crop.bottom * image.height,
        ).intersect(
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
        );
    if ((source.width - source.height).abs() >
        math.max(0.0001, math.max(source.width, source.height) * 0.000001)) {
      throw ArgumentError('Playlist artwork must use a square crop.');
    }
    final edge = math.min(
      maximumEdge,
      math.max(1, math.min(source.width, source.height).round()),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromLTWH(0, 0, edge.toDouble(), edge.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    ui.Image? rendered;
    try {
      rendered = await picture.toImage(edge, edge);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode playlist artwork.');
      final directory = Directory(p.join(mediaRoot, 'thumbnails'));
      await directory.create(recursive: true);
      final name = 'playlist_${const Uuid().v4()}.png';
      final temporary = File(p.join(directory.path, '$name.tmp'));
      final destination = File(p.join(directory.path, name));
      try {
        await temporary.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        await temporary.rename(destination.path);
        return name;
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } finally {
      rendered?.dispose();
      picture.dispose();
    }
  }

  Future<String?> resolve({
    required String mediaRoot,
    required String? fileName,
  }) async {
    if (mediaRoot.trim().isEmpty ||
        fileName == null ||
        !Playlist.isValidCustomArtworkFileName(fileName)) {
      return null;
    }
    final file = File(p.join(mediaRoot, 'thumbnails', fileName));
    return await file.exists() ? file.path : null;
  }

  /// Ignores unowned names; a playlist can never delete a song's thumbnail.
  Future<void> delete({
    required String mediaRoot,
    required String? fileName,
  }) async {
    if (mediaRoot.trim().isEmpty ||
        fileName == null ||
        !Playlist.isValidCustomArtworkFileName(fileName)) {
      return;
    }
    final file = File(p.join(mediaRoot, 'thumbnails', fileName));
    if (await file.exists()) await file.delete();
  }
}
