import 'package:bstream_music/features/music/domain/entities/catalog_playlist.dart';
import 'package:bstream_music/features/music/domain/entities/catalog_track.dart';
import 'package:bstream_music/features/music/domain/entities/local_track.dart';
import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:bstream_music/features/music/domain/entities/playlist_entry.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'catalog queue prefers downloads and preserves duplicate occurrences',
    () {
      final now = DateTime.utc(2026, 8, 22);
      final track = CatalogTrack.youtube(
        videoId: 'video-1',
        title: 'Track',
        artists: const ['Artist'],
      );
      final playlist = CatalogPlaylist(
        playlist: Playlist(
          id: 'playlist-1',
          name: 'Synced',
          trackIds: const [],
          createdAt: now,
          updatedAt: now,
        ),
        entries: [
          PlaylistEntry(
            id: 'entry-2',
            playlistId: 'playlist-1',
            track: track,
            localTrackId: 'local-1',
            position: 1,
            createdAt: now,
            updatedAt: now,
          ),
          PlaylistEntry(
            id: 'entry-1',
            playlistId: 'playlist-1',
            track: track,
            localTrackId: 'local-1',
            position: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      final local = LocalTrack(
        id: 'local-1',
        title: 'Track',
        artist: 'Artist',
        filePath: r'C:\music\track.m4a',
        sourceId: 'video-1',
        addedAt: now,
      );

      final queue = catalogPlaylistPlaybackItems(playlist, [local]);

      expect(queue.map((item) => item.entryId), ['entry-1', 'entry-2']);
      expect(queue.every((item) => identical(item.localTrack, local)), isTrue);
      expect(queue.every((item) => item.remoteTrack?.id == 'video-1'), isTrue);
    },
  );

  test('catalog queue keeps a remote entry when no download exists', () {
    final now = DateTime.utc(2026, 8, 22);
    final playlist = CatalogPlaylist(
      playlist: Playlist(
        id: 'playlist-1',
        name: 'Remote',
        trackIds: const [],
        createdAt: now,
        updatedAt: now,
      ),
      entries: [
        PlaylistEntry(
          id: 'remote-entry',
          playlistId: 'playlist-1',
          track: CatalogTrack.youtube(videoId: 'remote-1', title: 'Remote'),
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final queue = catalogPlaylistPlaybackItems(playlist, const []);

    expect(queue.single.localTrack, isNull);
    expect(queue.single.remoteTrack?.id, 'remote-1');
  });

  test(
    'shared playlist projection keeps unavailable entries and matches queue order',
    () {
      final now = DateTime.utc(2026, 11, 12);
      final remote = CatalogTrack.youtube(videoId: 'video-1', title: 'Remote');
      final unavailable = CatalogTrack.local(
        localTrackId: 'missing-local',
        title: 'Unavailable',
      );
      PlaylistEntry entry(
        String id,
        int position,
        CatalogTrack track, {
        bool deleted = false,
      }) => PlaylistEntry(
        id: id,
        playlistId: 'playlist-1',
        track: track,
        position: position,
        createdAt: now,
        updatedAt: now,
        deletedAt: deleted ? now : null,
      );
      final playlist = CatalogPlaylist(
        playlist: Playlist(
          id: 'playlist-1',
          name: 'Mixed',
          trackIds: const [],
          createdAt: now,
          updatedAt: now,
        ),
        entries: [
          entry('duplicate-b', 3, remote),
          entry('unavailable', 0, unavailable),
          entry('deleted', -1, remote, deleted: true),
          entry('duplicate-a', 3, remote),
        ],
      );
      final local = LocalTrack(
        id: 'download',
        title: 'Downloaded',
        artist: 'Artist',
        filePath: '/music/download.m4a',
        sourceId: 'video-1',
        addedAt: now,
      );

      final projection = catalogPlaylistResolvedEntries(playlist, [local]);
      final queue = catalogPlaylistPlaybackItems(playlist, [local]);

      expect(projection.map((item) => item.entry.id), [
        'unavailable',
        'duplicate-a',
        'duplicate-b',
      ]);
      expect(projection.first.playback, isNull);
      expect(
        projection.skip(1).every((item) => item.playback!.localTrack == local),
        isTrue,
      );
      expect(
        projection.map((item) => item.playback?.entryId).whereType<String>(),
        queue.map((item) => item.entryId),
      );
      expect(() => projection.clear(), throwsUnsupportedError);
    },
  );

  test(
    'projection preserves explicit local identity and first remote match',
    () {
      final now = DateTime.utc(2026, 11, 12);
      final remote = CatalogTrack.youtube(videoId: 'video-1', title: 'Remote');
      final first = LocalTrack(
        id: 'first-local',
        title: 'First local',
        artist: 'Artist',
        filePath: '/music/first.m4a',
        sourceId: 'video-1',
        addedAt: now,
      );
      final second = first.copyWith(id: 'second-local');
      final playlist = CatalogPlaylist(
        playlist: Playlist(
          id: 'playlist-1',
          name: 'Identities',
          trackIds: const [],
          createdAt: now,
          updatedAt: now,
        ),
        entries: [
          for (final (id, localId) in [
            ('inferred', null),
            ('explicit', 'second-local'),
            ('missing', 'missing-local'),
          ])
            PlaylistEntry(
              id: id,
              playlistId: 'playlist-1',
              track: remote,
              localTrackId: localId,
              position: 0,
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );

      final byId = {
        for (final item in catalogPlaylistResolvedEntries(playlist, [
          first,
          second,
        ]))
          item.entry.id: item.playback!,
      };
      expect(byId['inferred']!.localTrack, same(first));
      expect(byId['explicit']!.localTrack, same(second));
      expect(byId['missing']!.localTrack, isNull);
      expect(byId['missing']!.remoteTrack?.id, 'video-1');
    },
  );
}
