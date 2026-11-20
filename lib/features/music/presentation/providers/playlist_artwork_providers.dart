import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/storage/playlist_artwork_service.dart';
import 'music_providers.dart';

final playlistArtworkServiceProvider = Provider<PlaylistArtworkService>(
  (ref) => const PlaylistArtworkService(),
);

/// Resolve once per name/media-root change, rather than statting during paint.
final playlistArtworkPathProvider = FutureProvider.autoDispose
    .family<String?, String?>((ref, fileName) {
      final mediaRoot = ref.watch(
        settingsControllerProvider.select(
          (settings) => settings.value?.downloadDirectory,
        ),
      );
      if (mediaRoot == null) return null;
      return ref
          .watch(playlistArtworkServiceProvider)
          .resolve(mediaRoot: mediaRoot, fileName: fileName);
    });
