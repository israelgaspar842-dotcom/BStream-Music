import 'package:bstream_music/features/music/domain/entities/catalog_track.dart';
import 'package:bstream_music/services/youtube_music/account/youtube_music_account.dart';
import 'package:bstream_music/services/youtube_music/playlist_sync/playlist_sync_engine.dart';
import 'package:bstream_music/services/youtube_music/playlist_sync/playlist_sync_models.dart';
import 'package:bstream_music/services/youtube_music/playlist_sync/playlist_sync_store.dart';
import 'package:bstream_music/services/youtube_music/playlist_sync/playlist_three_way_merger.dart';
import 'package:bstream_music/services/youtube_music/playlist_sync/youtube_music_account_playlist_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reads 250 occurrences across modern append and reload continuations',
    () async {
      final transport = _Transport([
        _initial(_songs(0, 100), next: 'page-2', count: 250),
        _modern(_songs(100, 100), next: 'page-3'),
        _modern(
          _songs(200, 50),
          responseKey: 'onResponseReceivedCommands',
          action: 'reloadContinuationItemsCommand',
        ),
      ]);

      final snapshot = await _gateway(transport).getPlaylist('PL-large');

      expect(snapshot.isComplete, isTrue);
      expect(snapshot.entries, hasLength(250));
      expect(snapshot.pagesFetched, 3);
      expect(
        snapshot.entries.map((entry) => entry.position),
        List.generate(250, (i) => i),
      );
      expect(
        snapshot.entries.map((entry) => entry.setVideoId).toSet(),
        hasLength(250),
      );
      expect(snapshot.entries[0].videoId, snapshot.entries[7].videoId);
      expect(
        transport.requests.map((request) => request.body['continuation']),
        [null, 'page-2', 'page-3'],
      );
    },
  );

  test(
    'default page bound reads 5000 songs instead of stopping at 40 pages',
    () async {
      final transport = _Transport([
        _initial(_songs(0, 100), next: 'page-2', count: 5000),
        for (var page = 2; page <= 50; page++)
          _modern(
            _songs((page - 1) * 100, 100),
            next: page < 50 ? 'page-${page + 1}' : null,
          ),
      ]);
      final gateway = YouTubeMusicAccountGateway(
        transport: transport,
        sessionHeaders: StaticYouTubeMusicSessionHeadersProvider(
          YouTubeMusicSessionHeaders(const {}),
        ),
        clientContext: const {
          'client': {'clientName': 'WEB_REMIX', 'clientVersion': 'fixture'},
        },
      );

      final snapshot = await gateway.getPlaylist('PL-five-thousand');

      expect(snapshot.isComplete, isTrue);
      expect(snapshot.entries, hasLength(5000));
      expect(snapshot.pagesFetched, 50);
      expect(snapshot.entries.last.position, 4999);
    },
  );

  test('supports legacy and modern playlist pages in one read', () async {
    final transport = _Transport([
      _initial(_songs(0, 100), next: 'legacy-2', count: 250),
      {
        'continuationContents': {
          'musicPlaylistShelfContinuation': {
            'contents': [..._songs(100, 100), _continuation('modern-3')],
          },
        },
      },
      _modern(_songs(200, 50), responseKey: 'onResponseReceivedEndpoints'),
    ]);

    final snapshot = await _gateway(transport).getPlaylist('PL-mixed');

    expect(snapshot.isComplete, isTrue);
    expect(snapshot.entries, hasLength(250));
    expect(snapshot.entries.last.position, 249);
  });

  test(
    'keeps unavailable occurrences and repeated videos while paginating',
    () async {
      final unavailable = _song(100, available: false);
      final transport = _Transport([
        _initial([_song(0)], next: 'page-2', count: 3),
        _modern([unavailable, _song(7)]),
      ]);

      final snapshot = await _gateway(transport).getPlaylist('PL-unavailable');

      expect(snapshot.isComplete, isTrue);
      expect(snapshot.entries, hasLength(3));
      expect(snapshot.entries[1].videoId, isNull);
      expect(snapshot.entries[1].setVideoId, 'set-100');
      expect(snapshot.entries[1].isAvailable, isFalse);
      expect(snapshot.entries.first.videoId, snapshot.entries.last.videoId);
    },
  );

  test('accepts a genuine empty initial playlist shelf', () async {
    final snapshot = await _gateway(
      _Transport([_initial([], count: 0)]),
    ).getPlaylist('PL-empty');

    expect(snapshot.isComplete, isTrue);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.summary?.itemCount, 0);
    expect(snapshot.pagesFetched, 1);
  });

  test(
    'missing continuation cannot complete a declared 250-song playlist',
    () async {
      final snapshot = await _gateway(
        _Transport([_initial(_songs(0, 100), count: 250)]),
      ).getPlaylist('PL-missing-continuation');

      expect(snapshot.entries, hasLength(100));
      expect(snapshot.isComplete, isFalse);
      expect(snapshot.termination, RemotePaginationTermination.invalidResponse);
    },
  );

  for (final counts in const [(383, 382), (1163, 1156)]) {
    test(
      'accepts ${counts.$2} visible tracks of ${counts.$1} advertised',
      () async {
        final visible = counts.$2;
        final responses = <Object?>[
          _initial(_songs(0, 100), next: 'page-2', count: counts.$1),
          for (var offset = 100; offset < visible; offset += 100)
            _modern(
              _songs(offset, (visible - offset).clamp(0, 100)),
              next: offset + 100 < visible ? 'page-${offset ~/ 100 + 2}' : null,
            ),
        ];
        final snapshot = await _gateway(
          _Transport(responses),
        ).getPlaylist('PL-hidden-tracks');

        expect(snapshot.summary?.itemCount, counts.$1);
        expect(snapshot.entries, hasLength(visible));
        expect(snapshot.isComplete, isTrue);
        expect(snapshot.termination, RemotePaginationTermination.exhausted);
      },
    );
  }

  test(
    'small playlist with hidden tracks is not mistaken for truncation',
    () async {
      final snapshot = await _gateway(
        _Transport([_initial(_songs(0, 2), count: 3)]),
      ).getPlaylist('PL-small-hidden-track');

      expect(snapshot.isComplete, isTrue);
      expect(snapshot.entries, hasLength(2));
    },
  );

  test(
    'accepts a recognized empty end when all declared rows were received',
    () async {
      final snapshot = await _gateway(
        _Transport([
          _initial(_songs(0, 100), next: 'page-2', count: 100),
          _modern([]),
        ]),
      ).getPlaylist('PL-verified-empty-end');

      expect(snapshot.entries, hasLength(100));
      expect(snapshot.isComplete, isTrue);
      expect(snapshot.termination, RemotePaginationTermination.exhausted);
    },
  );

  test('refuses a replayed occurrence even when the token changes', () async {
    final transport = _Transport([
      _initial(_songs(0, 2), next: 'page-2', count: 4),
      _modern([_song(0), _song(2)], next: 'different-token'),
    ]);

    final snapshot = await _gateway(transport).getPlaylist('PL-overlap');

    expect(snapshot.isComplete, isFalse);
    expect(snapshot.termination, RemotePaginationTermination.invalidResponse);
    expect(snapshot.entries.map((entry) => entry.setVideoId), [
      'set-0',
      'set-1',
    ]);
    expect(transport.requests, hasLength(2));
  });

  test('refuses repeated occurrence IDs inside a single page', () async {
    final snapshot = await _gateway(
      _Transport([
        _initial([_song(0), _song(0)], count: 2),
      ]),
    ).getPlaylist('PL-duplicate-occurrence');

    expect(snapshot.isComplete, isFalse);
    expect(snapshot.termination, RemotePaginationTermination.invalidResponse);
  });

  test('preserves repeated videos that have no occurrence ID', () async {
    Map<String, Object?> withoutOccurrenceId(int index) {
      final item = _song(index);
      final renderer = item['musicResponsiveListItemRenderer']! as Map;
      (renderer['playlistItemData']! as Map).remove('playlistSetVideoId');
      return item;
    }

    final snapshot = await _gateway(
      _Transport([
        _initial([withoutOccurrenceId(0)], next: 'page-2', count: 2),
        _modern([withoutOccurrenceId(7)]),
      ]),
    ).getPlaylist('PL-duplicates-no-set-id');

    expect(snapshot.isComplete, isTrue);
    expect(snapshot.entries, hasLength(2));
    expect(snapshot.entries.first.videoId, snapshot.entries.last.videoId);
  });

  for (final response in <Object?>[
    <String, Object?>{},
    {
      'musicPlaylistShelfRenderer': {'contents': 'not-a-list'},
    },
    {
      'unrecognized': {'items': <Object?>[]},
    },
  ]) {
    test(
      'does not treat an unknown initial response as an empty playlist: $response',
      () async {
        final snapshot = await _gateway(
          _Transport([response]),
        ).getPlaylist('PL-invalid');

        expect(snapshot.isComplete, isFalse);
        expect(
          snapshot.termination,
          RemotePaginationTermination.invalidResponse,
        );
        expect(snapshot.entries, isEmpty);
      },
    );
  }

  for (final continuation in <Object?>[
    <String, Object?>{},
    _modern([]),
    {
      'continuationContents': {
        'musicPlaylistShelfContinuation': {'contents': <Object?>[]},
      },
    },
  ]) {
    test(
      'does not mark a missing or empty continuation complete: $continuation',
      () async {
        final transport = _Transport([
          _initial(_songs(0, 100), next: 'page-2', count: 250),
          continuation,
        ]);

        final snapshot = await _gateway(transport).getPlaylist('PL-incomplete');

        expect(snapshot.isComplete, isFalse);
        expect(
          snapshot.termination,
          RemotePaginationTermination.invalidResponse,
        );
        expect(snapshot.entries, hasLength(100));
        expect(snapshot.pagesFetched, 2);
        expect(transport.requests, hasLength(2));
      },
    );
  }

  test(
    'retains the loop and page-limit protections for modern continuations',
    () async {
      final repeated = await _gateway(
        _Transport([
          _initial(_songs(0, 100), next: 'page-2', count: 250),
          _modern(_songs(100, 100), next: 'page-2'),
        ]),
      ).getPlaylist('PL-loop');
      final limited = await _gateway(
        _Transport([
          _initial(_songs(0, 100), next: 'page-2', count: 250),
          _modern(_songs(100, 100), next: 'page-3'),
        ]),
        maxReadPages: 2,
      ).getPlaylist('PL-limit');

      expect(
        repeated.termination,
        RemotePaginationTermination.repeatedContinuation,
      );
      expect(limited.termination, RemotePaginationTermination.pageLimit);
      expect(repeated.isComplete, isFalse);
      expect(limited.isComplete, isFalse);
      expect(repeated.entries, hasLength(200));
      expect(limited.entries, hasLength(200));
    },
  );

  test(
    'unknown saved-playlist and subscription pages are incomplete',
    () async {
      final playlists = await _gateway(_Transport([{}])).getSavedPlaylists();
      final artists = await _gateway(_Transport([{}])).getSubscribedArtists();

      expect(playlists.isComplete, isFalse);
      expect(artists.isComplete, isFalse);
      expect(
        playlists.termination,
        RemotePaginationTermination.invalidResponse,
      );
      expect(artists.termination, RemotePaginationTermination.invalidResponse);
    },
  );

  test(
    'known empty saved-playlist and subscription containers remain valid',
    () async {
      final payload = {
        'contents': [
          {
            'gridRenderer': {'items': <Object?>[]},
          },
        ],
      };
      final playlists = await _gateway(
        _Transport([payload]),
      ).getSavedPlaylists();
      final artists = await _gateway(
        _Transport([payload]),
      ).getSubscribedArtists();

      expect(playlists.isComplete, isTrue);
      expect(artists.isComplete, isTrue);
      expect(playlists.playlists, isEmpty);
      expect(artists.artists, isEmpty);
    },
  );

  test(
    'saved-playlist and subscription continuations keep their accumulated data',
    () async {
      final playlists = await _gateway(
        _Transport([
          _grid([_collectionCard('VLPL-one', 'Playlist one')], next: 'page-2'),
          {},
        ]),
      ).getSavedPlaylists();
      final artists = await _gateway(
        _Transport([
          _grid([
            _collectionCard('UC-one', 'Artist one', artist: true),
          ], next: 'page-2'),
          {},
        ]),
      ).getSubscribedArtists();

      expect(playlists.isComplete, isFalse);
      expect(artists.isComplete, isFalse);
      expect(
        playlists.termination,
        RemotePaginationTermination.invalidResponse,
      );
      expect(artists.termination, RemotePaginationTermination.invalidResponse);
      expect(playlists.playlists.single.playlistId, 'PL-one');
      expect(artists.artists.single.channelId, 'UC-one');
    },
  );

  test(
    'saved playlists and subscriptions follow modern continuation actions',
    () async {
      final playlists = await _gateway(
        _Transport([
          _grid([_collectionCard('VLPL-one', 'Playlist one')], next: 'page-2'),
          _modern([_collectionCard('VLPL-two', 'Playlist two')]),
        ]),
      ).getSavedPlaylists();
      final artists = await _gateway(
        _Transport([
          _grid([
            _collectionCard('UC-one', 'Artist one', artist: true),
          ], next: 'page-2'),
          _modern([_collectionCard('UC-two', 'Artist two', artist: true)]),
        ]),
      ).getSubscribedArtists();

      expect(playlists.isComplete, isTrue);
      expect(artists.isComplete, isTrue);
      expect(playlists.playlists.map((item) => item.playlistId), [
        'PL-one',
        'PL-two',
      ]);
      expect(artists.artists.map((item) => item.channelId), [
        'UC-one',
        'UC-two',
      ]);
    },
  );

  test(
    'incomplete remote read defers sync without replacing 250 local songs',
    () async {
      const key = PlaylistSyncKey(
        accountKey: 'UC-fixture',
        playlistId: 'local-large',
      );
      final now = DateTime.utc(2026, 11, 6);
      final local = PlaylistSyncSnapshot(
        title: 'Large playlist',
        remotePlaylistId: 'PL-large',
        items: [
          for (var i = 0; i < 250; i++)
            PlaylistSyncItem(
              videoId: _video(i),
              setVideoId: 'set-$i',
              track: CatalogTrack.youtube(videoId: _video(i), title: 'Song $i'),
            ),
        ],
      );
      final store = _SyncStore(
        PlaylistSyncWork(
          binding: PlaylistSyncBinding(
            key: key,
            remotePlaylistId: 'PL-large',
            mode: PlaylistSyncMode.automatic,
            localRevisionAtBase: 1,
            createdAt: now,
            updatedAt: now,
          ),
          base: local,
          local: local,
          localRevision: 1,
          localDeleted: false,
        ),
      );
      final transport = _Transport([
        _initial(_songs(0, 100), next: 'page-2', count: 250),
        {},
      ]);
      final engine = PlaylistSyncEngine(
        store: store,
        gateway: YouTubeMusicAccountPlaylistGateway(
          accountGateway: _gateway(transport),
          accountKey: key.accountKey,
        ),
        merger: PlaylistThreeWayMerger(itemIdFactory: () => 'unused'),
        mutationTokenFactory: () => 'unused',
        clock: () => now,
      );

      final result = await engine.sync(key);

      expect(result.disposition, PlaylistSyncDisposition.deferred);
      expect(store.deferredReads, 1);
      expect(store.unexpectedWrites, isEmpty);
      expect(store.work.local.items, hasLength(250));
      expect(
        transport.requests.every(
          (request) => request.kind == YouTubeMusicAccountRequestKind.read,
        ),
        isTrue,
      );
    },
  );
}

YouTubeMusicAccountGateway _gateway(
  _Transport transport, {
  int maxReadPages = 40,
}) => YouTubeMusicAccountGateway(
  transport: transport,
  sessionHeaders: StaticYouTubeMusicSessionHeadersProvider(
    YouTubeMusicSessionHeaders(const {}),
  ),
  clientContext: const {
    'client': {'clientName': 'WEB_REMIX', 'clientVersion': 'fixture'},
  },
  maxReadPages: maxReadPages,
);

Map<String, Object?> _initial(
  List<Object?> songs, {
  String? next,
  required int count,
}) => {
  'header': {
    'musicEditablePlaylistDetailHeaderRenderer': {
      'title': _runs('Large playlist'),
      'subtitle': _runs('$count songs'),
      'editPlaylistEndpoint': <String, Object?>{},
    },
  },
  'contents': [
    {
      'musicPlaylistShelfRenderer': {
        'contents': [...songs, if (next != null) _continuation(next)],
      },
    },
  ],
};

Map<String, Object?> _modern(
  List<Object?> songs, {
  String? next,
  String responseKey = 'onResponseReceivedActions',
  String action = 'appendContinuationItemsAction',
}) => {
  responseKey: [
    {
      action: {
        'continuationItems': [...songs, if (next != null) _continuation(next)],
      },
    },
  ],
};

Map<String, Object?> _grid(List<Object?> items, {String? next}) => {
  'contents': [
    {
      'gridRenderer': {
        'items': [...items, if (next != null) _continuation(next)],
      },
    },
  ],
};

Map<String, Object?> _collectionCard(
  String browseId,
  String title, {
  bool artist = false,
}) => {
  'musicTwoRowItemRenderer': {
    'title': _runs(title),
    if (artist) 'channelId': browseId,
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseId': browseId,
        if (artist)
          'browseEndpointContextSupportedConfigs': {
            'browseEndpointContextMusicConfig': {
              'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
            },
          },
      },
    },
  },
};

List<Object?> _songs(int start, int count) => [
  for (var i = start; i < start + count; i++) _song(i),
];

String _video(int index) => 'v${(index % 7).toString().padLeft(10, '0')}';

Map<String, Object?> _song(int index, {bool available = true}) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {
      if (available) 'videoId': _video(index),
      'playlistSetVideoId': 'set-$index',
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': _runs('Song $index'),
        },
      },
    ],
  },
};

Map<String, Object?> _continuation(String value) => {
  'continuationItemRenderer': {
    'continuationEndpoint': {
      'continuationCommand': {'token': value},
    },
  },
};

Map<String, Object?> _runs(String text) => {
  'runs': [
    {'text': text},
  ],
};

class _Transport implements YouTubeMusicAccountTransport {
  _Transport(List<Object?> bodies) : bodies = List.of(bodies);

  final List<Object?> bodies;
  final requests = <YouTubeMusicAccountRequest>[];

  @override
  Future<YouTubeMusicAccountResponse> send(
    YouTubeMusicAccountRequest request,
  ) async {
    requests.add(request);
    return YouTubeMusicAccountResponse(
      statusCode: 200,
      body: bodies.removeAt(0),
    );
  }
}

class _SyncStore implements PlaylistSyncStore {
  _SyncStore(this.work);

  final PlaylistSyncWork work;
  int deferredReads = 0;
  final unexpectedWrites = <Symbol>[];

  @override
  Future<PlaylistSyncWork?> loadWork(PlaylistSyncKey key) async => work;

  @override
  Future<void> recordDeferred({
    required PlaylistSyncKey key,
    required int requestedLocalRevision,
    required String reason,
    required DateTime now,
    required DateTime nextAttemptAt,
    PlaylistSyncSnapshot? desired,
    String? mutationToken,
    String? error,
    bool ambiguous = false,
  }) async {
    deferredReads++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedWrites.add(invocation.memberName);
    throw StateError('Unexpected store operation ${invocation.memberName}');
  }
}
