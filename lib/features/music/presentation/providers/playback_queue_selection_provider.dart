import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_providers.dart';

/// Playlist rows only need the current occurrence, not the rest of the queue.
final currentQueueLogicalEntryIdProvider = Provider<String?>((ref) {
  return ref.watch(
    playbackQueueProvider.select((queue) {
      final index = queue.currentIndex;
      return index >= 0 && index < queue.entries.length
          ? queue.entries[index].logicalEntryId
          : null;
    }),
  );
});
