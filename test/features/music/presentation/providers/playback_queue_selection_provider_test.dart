import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:bstream_music/features/music/presentation/providers/playback_queue_selection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('other queue edits do not invalidate the selected occurrence', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final queue = container.read(playbackQueueProvider.notifier);
    queue.replace([_entry('same-song', 'occurrence-a')], 0);
    var notifications = 0;
    final subscription = container.listen(
      currentQueueLogicalEntryIdProvider,
      (_, _) => notifications++,
    );
    addTearDown(subscription.close);
    expect(container.read(currentQueueLogicalEntryIdProvider), 'occurrence-a');

    queue.replace([
      _entry('other-song', 'other-occurrence'),
      _entry('same-song', 'occurrence-a'),
      _entry('same-song', 'occurrence-b'),
    ], 1);
    await container.pump();
    expect(container.read(currentQueueLogicalEntryIdProvider), 'occurrence-a');
    expect(notifications, 0);

    // The same song may occur twice; changing occurrence must update the rows.
    queue.replace([
      _entry('same-song', 'occurrence-a'),
      _entry('same-song', 'occurrence-b'),
    ], 1);
    await container.pump();
    expect(container.read(currentQueueLogicalEntryIdProvider), 'occurrence-b');
    expect(notifications, 1);

    queue.replace([], -1);
    await container.pump();
    expect(container.read(currentQueueLogicalEntryIdProvider), isNull);
    expect(notifications, 2);
  });

  test('legacy queues and invalid indices retain track-ID fallback', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final queue = container.read(playbackQueueProvider.notifier);
    queue.replace([_entry('legacy-song', null)], 0);
    expect(container.read(currentQueueLogicalEntryIdProvider), isNull);
    queue.replace([_entry('song', 'entry')], 4);
    expect(container.read(currentQueueLogicalEntryIdProvider), isNull);
    queue.replace([_entry('song', 'entry')], -1);
    expect(container.read(currentQueueLogicalEntryIdProvider), isNull);
  });
}

PlaybackQueueEntry _entry(String trackId, String? logicalEntryId) =>
    PlaybackQueueEntry(
      id: trackId,
      title: trackId,
      artist: 'Artist',
      isRemote: true,
      logicalEntryId: logicalEntryId,
    );
