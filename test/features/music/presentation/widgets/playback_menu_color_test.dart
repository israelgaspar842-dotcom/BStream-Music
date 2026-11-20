import 'package:bstream_music/features/music/presentation/providers/playback_artwork_provider.dart';
import 'dart:async';

import 'package:bstream_music/features/music/presentation/providers/artwork_progress_color_provider.dart';
import 'package:bstream_music/features/music/presentation/widgets/playback_menu_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'menus and detail surfaces share a color lookup and its lifetime',
    () async {
      const source = '/fixture/shared-cover.png';
      final service = _CountingColorService();
      final container = ProviderContainer(
        overrides: [
          artworkSurfaceColorServiceProvider.overrideWithValue(service),
          playbackArtworkProvider.overrideWithValue((
            source: source,
            fallback: null,
          )),
        ],
      );
      addTearDown(container.dispose);
      final page = container.listen(
        artworkSurfaceColorProvider(source),
        (_, _) {},
      );
      final menu = container.listen(
        playbackMenuArtworkColorProvider,
        (_, _) {},
      );

      expect(service.acquisitions, 1);
      service.result.complete(Colors.orange);
      await container.read(artworkSurfaceColorProvider(source).future);
      expect(container.read(playbackMenuArtworkColorProvider), Colors.orange);

      menu.close();
      await container.pump();
      expect(service.releases, 0);
      page.close();
      await container.pump();
      expect(service.releases, 1);
    },
  );
}

class _CountingColorService extends ArtworkProgressColorService {
  final result = Completer<Color>();
  int acquisitions = 0;
  int releases = 0;

  @override
  ArtworkProgressColorLease acquire(String? rawSource) {
    acquisitions++;
    return _CountingLease(result.future, () => releases++);
  }
}

class _CountingLease extends ArtworkProgressColorLease {
  _CountingLease(Future<Color> future, this.onRelease) : super(future: future);
  final VoidCallback onRelease;

  @override
  void release() => onRelease();
}
