import 'dart:collection';

import 'package:bstream_music/features/music/domain/entities/catalog_playlist.dart';
import 'package:bstream_music/features/music/domain/entities/catalog_track.dart';
import 'package:bstream_music/features/music/domain/entities/download_options.dart';
import 'package:bstream_music/features/music/domain/entities/download_result.dart';
import 'package:bstream_music/features/music/domain/entities/local_track.dart';
import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:bstream_music/features/music/domain/entities/playlist_entry.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'download progress reuses playlist IDs and cancellable identities',
    () async {
      final library = _CountingTracks([_local('saved', 'aaaaaaaaaaa')]);
      final setup = await _setup(
        library: library,
        catalog: _catalog([_entry('active', 'aaaaaaaaaaa')]),
      );
      final container = setup.container;
      final downloads = setup.downloads;
      final ids = container.read(
        playlistDownloadVideoIdsProvider(_playlist.id),
      );
      expect(ids, {'aaaaaaaaaaa'});
      downloads.emit(_task('aaaaaaaaaaa', DownloadProgressStatus.queued));
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        true,
      );

      var pendingChanges = 0;
      var cancellableChanges = 0;
      final pendingSubscription = container.listen(
        playlistHasPendingDownloadsProvider(_playlist.id),
        (_, _) => pendingChanges++,
      );
      final cancellableSubscription = container.listen(
        cancellableDownloadVideoIdsProvider,
        (_, _) => cancellableChanges++,
      );
      addTearDown(pendingSubscription.close);
      addTearDown(cancellableSubscription.close);
      final traversals = library.traversals;
      for (final progress in [0.0, 0.2, 0.8]) {
        downloads.emit(
          _task(
            'aaaaaaaaaaa',
            DownloadProgressStatus.running,
            progress: progress,
          ),
        );
        await container.pump();
      }
      expect(
        container.read(playlistDownloadVideoIdsProvider(_playlist.id)),
        same(ids),
      );
      expect(library.traversals, traversals);
      expect(pendingChanges, 0);
      expect(cancellableChanges, 0);

      downloads.emit(_task('aaaaaaaaaaa', DownloadProgressStatus.completed));
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        false,
      );
      expect(pendingChanges, 1);
      expect(cancellableChanges, 1);
      expect(library.traversals, traversals);

      downloads.emit(_task('aaaaaaaaaaa', DownloadProgressStatus.queued));
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        true,
      );
      downloads.clear();
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        false,
      );
    },
  );

  test(
    'catalog edits refresh matching IDs and ignore deleted occurrences',
    () async {
      final setup = await _setup(
        catalog: _catalog([
          _entry('deleted', 'aaaaaaaaaaa', deleted: true),
          _entry('other', 'bbbbbbbbbbb'),
        ]),
      );
      final container = setup.container;
      setup.downloads.emit(
        _task('aaaaaaaaaaa', DownloadProgressStatus.running),
      );
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        false,
      );

      container.read(setup.catalogSource.notifier).state = _catalog([
        _entry('new', 'aaaaaaaaaaa'),
      ]);
      await container.read(catalogPlaylistProvider(_playlist.id).future);
      await container.pump();
      expect(container.read(playlistDownloadVideoIdsProvider(_playlist.id)), {
        'aaaaaaaaaaa',
      });
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        true,
      );

      setup.downloads.emit(_task('aaaaaaaaaaa', DownloadProgressStatus.failed));
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        false,
      );
      setup.downloads.emit(_task('bbbbbbbbbbb', DownloadProgressStatus.queued));
      await container.pump();
      expect(
        container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
        false,
      );
    },
  );

  test('legacy playlist IDs refresh when library metadata changes', () async {
    final setup = await _setup(library: [_local('saved', 'aaaaaaaaaaa')]);
    final container = setup.container;
    setup.downloads.emit(_task('bbbbbbbbbbb', DownloadProgressStatus.running));
    await container.pump();
    expect(
      container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
      false,
    );

    container.read(setup.librarySource.notifier).state = [
      _local('saved', 'bbbbbbbbbbb'),
    ];
    await container.read(libraryTracksProvider.future);
    await container.pump();
    expect(container.read(playlistDownloadVideoIdsProvider(_playlist.id)), {
      'bbbbbbbbbbb',
    });
    expect(
      container.read(playlistHasPendingDownloadsProvider(_playlist.id)),
      true,
    );
  });
}

final _playlist = Playlist(
  id: 'menu-playlist',
  name: 'Playlist',
  trackIds: const ['saved'],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<
  ({
    ProviderContainer container,
    _MutableDownloads downloads,
    StateProvider<CatalogPlaylist?> catalogSource,
    StateProvider<List<LocalTrack>> librarySource,
  })
>
_setup({List<LocalTrack> library = const [], CatalogPlaylist? catalog}) async {
  final librarySource = StateProvider<List<LocalTrack>>((ref) => library);
  final catalogSource = StateProvider<CatalogPlaylist?>((ref) => catalog);
  final downloads = _MutableDownloads();
  final container = ProviderContainer(
    overrides: [
      libraryTracksProvider.overrideWith(
        (ref) async => ref.watch(librarySource),
      ),
      catalogPlaylistProvider.overrideWith(
        (ref, id) async => ref.watch(catalogSource),
      ),
      playlistsControllerProvider.overrideWith(() => _FixedPlaylists()),
      downloadControllerProvider.overrideWith(() => downloads),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    playlistHasPendingDownloadsProvider(_playlist.id),
    (_, _) {},
  );
  addTearDown(subscription.close);
  await container.read(playlistsControllerProvider.future);
  await container.read(catalogPlaylistProvider(_playlist.id).future);
  await container.read(libraryTracksProvider.future);
  await container.pump();
  return (
    container: container,
    downloads: downloads,
    catalogSource: catalogSource,
    librarySource: librarySource,
  );
}

CatalogPlaylist _catalog(List<PlaylistEntry> entries) =>
    CatalogPlaylist(playlist: _playlist, entries: entries);

PlaylistEntry _entry(String id, String videoId, {bool deleted = false}) =>
    PlaylistEntry(
      id: id,
      playlistId: _playlist.id,
      track: CatalogTrack.youtube(videoId: videoId, title: id),
      position: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      deletedAt: deleted ? DateTime.utc(2026) : null,
    );

LocalTrack _local(String id, String sourceId) => LocalTrack(
  id: id,
  title: id,
  artist: 'Artist',
  filePath: '/audio/$id.mp3',
  addedAt: DateTime.utc(2026),
  sourceId: sourceId,
);

DownloadTaskState _task(
  String videoId,
  DownloadProgressStatus status, {
  double? progress,
}) => DownloadTaskState(
  url: 'https://youtu.be/$videoId',
  taskId: 'task-$videoId',
  mediaType: DownloadMediaType.audio,
  status: status,
  progress: progress,
);

class _MutableDownloads extends DownloadController {
  @override
  Map<String, DownloadTaskState> build() => const {};

  void emit(DownloadTaskState task) => state = {...state, task.url: task};
  void clear() => state = const {};
}

class _FixedPlaylists extends PlaylistsController {
  @override
  Future<List<Playlist>> build() async => [_playlist];
}

class _CountingTracks extends ListBase<LocalTrack> {
  _CountingTracks(this._tracks);

  final List<LocalTrack> _tracks;
  var traversals = 0;

  @override
  Iterator<LocalTrack> get iterator {
    traversals++;
    return _tracks.iterator;
  }

  @override
  int get length => _tracks.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  LocalTrack operator [](int index) => _tracks[index];
  @override
  void operator []=(int index, LocalTrack value) =>
      throw UnsupportedError('read only');
}
