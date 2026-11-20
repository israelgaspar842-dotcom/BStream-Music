import 'package:bstream_music/services/youtube_music/account/youtube_music_account_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = YouTubeMusicAccountParser();

  for (final responseKey in const [
    'onResponseReceivedActions',
    'onResponseReceivedEndpoints',
    'onResponseReceivedCommands',
  ]) {
    for (final operation in const [
      'appendContinuationItemsAction',
      'reloadContinuationItemsCommand',
    ]) {
      test(
        'reads playlist rows and browse token from $responseKey/$operation',
        () {
          final response = _response(
            [_song(100), _song(101), _token('next-page')],
            responseKey: responseKey,
            operation: operation,
          );
          expect(parser.isPlaylistEntryPage(response), isTrue);
          final entries = parser.parsePlaylistEntries(
            response,
            startingPosition: 100,
          );
          expect(entries.map((entry) => entry.position), [100, 101]);
          expect(entries.map((entry) => entry.setVideoId), [
            'set-100',
            'set-101',
          ]);
          expect(
            entries.map((entry) => entry.videoId),
            everyElement('same-video'),
          );
          expect(parser.parsePlaylistEntryContinuationTokens(response), [
            'next-page',
          ]);
        },
      );
    }
  }

  test(
    'scopes parallel modern collections to songs, saved playlists and artists',
    () {
      final response = {
        'onResponseReceivedActions': [
          _operation([_song(1), _token('songs-next')]),
          _operation([_playlist(), _token('playlists-next')]),
          _operation([_artist(), _token('artists-next')]),
          {
            'showNotificationEndpoint': {
              'contents': [_song(999), _token('notification-decoy')],
            },
          },
        ],
      };
      expect(
        parser
            .parsePlaylistEntries(response, startingPosition: 0)
            .single
            .setVideoId,
        'set-1',
      );
      expect(parser.parsePlaylistEntryContinuationTokens(response), [
        'songs-next',
      ]);
      expect(
        parser.parsePlaylistSummaries(response).single.playlistId,
        'PL-saved',
      );
      expect(parser.parseSavedPlaylistContinuationTokens(response), [
        'playlists-next',
      ]);
      expect(
        parser.parseSubscribedArtists(response).single.browseId,
        'UC-artist',
      );
      expect(parser.parseSubscribedArtistContinuationTokens(response), [
        'artists-next',
      ]);
      expect(parser.isPlaylistEntryPage(response), isTrue);
      expect(parser.isSavedPlaylistPage(response), isTrue);
      expect(parser.isSubscribedArtistPage(response), isTrue);
    },
  );

  test(
    'ambiguous modern song collections cannot fall back to unrelated legacy contents',
    () {
      final response = {
        'onResponseReceivedActions': [
          _operation([_song(1), _token('first')]),
          _operation([_song(2), _token('second')]),
        ],
        'unrelated': {
          'contents': [_song(999), _token('decoy')],
        },
      };
      expect(parser.isPlaylistEntryPage(response), isFalse);
      expect(
        parser.parsePlaylistEntries(response, startingPosition: 0),
        isEmpty,
      );
      expect(parser.parsePlaylistEntryContinuationTokens(response), isEmpty);
      expect(parser.parseContinuationTokens(response), isEmpty);
    },
  );

  test('only top-level continuation content operations are accepted', () {
    final response = {
      'onResponseReceivedActions': [
        {
          'menu': _operation([_song(1), _token('nested-decoy')]),
        },
      ],
    };
    expect(parser.isPlaylistEntryPage(response), isFalse);
    expect(parser.parsePlaylistEntries(response, startingPosition: 0), isEmpty);
    expect(parser.parsePlaylistEntryContinuationTokens(response), isEmpty);
  });

  test('wrapped continuation skips watch and popup commands', () {
    final response = _response([
      _song(1),
      {
        'continuationItemRenderer': {
          'continuationEndpoint': {
            'commandExecutorCommand': {
              'commands': [
                {
                  'continuationCommand': {
                    'token': 'watch-decoy',
                    'request': 'CONTINUATION_REQUEST_TYPE_WATCH_NEXT',
                  },
                },
                {
                  'playlistVotingRefreshPopupCommand': {
                    'continuationCommand': {
                      'token': 'popup-decoy',
                      'request': 'CONTINUATION_REQUEST_TYPE_PLAYLIST_VOTING',
                    },
                  },
                },
                {
                  'continuationCommand': {
                    'token': 'browse-next',
                    'request': 'CONTINUATION_REQUEST_TYPE_BROWSE',
                  },
                },
              ],
            },
          },
        },
      },
    ]);
    expect(parser.parsePlaylistEntryContinuationTokens(response), [
      'browse-next',
    ]);
  });

  test(
    'empty content is recognized but missing or malformed content is not',
    () {
      expect(parser.isPlaylistEntryPage(_response([])), isTrue);
      expect(parser.isSavedPlaylistPage(_response([])), isTrue);
      expect(parser.isSubscribedArtistPage(_response([])), isTrue);
      expect(parser.isPlaylistEntryPage(const {}), isFalse);
      expect(parser.isSavedPlaylistPage(const {}), isFalse);
      expect(parser.isSubscribedArtistPage(const {}), isFalse);
      final malformed = {
        'onResponseReceivedActions': [
          {
            'appendContinuationItemsAction': {
              'continuationItems': 'not-a-list',
            },
          },
        ],
      };
      expect(parser.isPlaylistEntryPage(malformed), isFalse);
      expect(parser.isSavedPlaylistPage(malformed), isFalse);
      expect(parser.isSubscribedArtistPage(malformed), isFalse);
    },
  );

  test('dedicated empty initial shelves remain valid collections', () {
    expect(
      parser.isPlaylistEntryPage({
        'musicPlaylistShelfRenderer': {'contents': []},
      }),
      isTrue,
    );
    expect(
      parser.isSavedPlaylistPage({
        'gridRenderer': {'items': []},
      }),
      isTrue,
    );
    expect(
      parser.isSubscribedArtistPage({
        'gridRenderer': {'items': []},
      }),
      isTrue,
    );
  });

  test(
    'a supported song renderer without any occurrence or video id is incomplete',
    () {
      final response = _response([
        _song(1),
        {
          'musicResponsiveListItemRenderer': {'flexColumns': []},
        },
      ]);
      expect(parser.isPlaylistEntryPage(response), isFalse);
    },
  );

  test('legacy music shelf continuation is still readable', () {
    final response = {
      'continuationContents': {
        'musicShelfContinuation': {
          'contents': [_song(1)],
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'legacy-next'},
            },
          ],
        },
      },
    };
    expect(parser.isPlaylistEntryPage(response), isTrue);
    expect(
      parser
          .parsePlaylistEntries(response, startingPosition: 100)
          .single
          .position,
      100,
    );
    expect(parser.parsePlaylistEntryContinuationTokens(response), [
      'legacy-next',
    ]);
  });

  test('an unknown row next to a valid song makes the snapshot incomplete', () {
    final response = _response([
      _song(1),
      {
        'unknownPlaylistRowRenderer': {'title': 'Not parsed yet'},
      },
    ]);

    expect(parser.isPlaylistEntryPage(response), isFalse);
  });

  test('reads current two-column header secondSubtitle track count', () {
    final header = parser.parsePlaylistHeader({
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicResponsiveHeaderRenderer': {
                          'title': {
                            'runs': [
                              {'text': 'Public large playlist'},
                            ],
                          },
                          'subtitle': {
                            'runs': [
                              {'text': 'Playlist'},
                              {'text': '2024'},
                            ],
                          },
                          'secondSubtitle': {
                            'runs': [
                              {'text': '1.1K views'},
                              {'text': '383 tracks'},
                              {'text': '23+ hours'},
                            ],
                          },
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    }, playlistId: 'PL-current-shape');

    expect(header?.title, 'Public large playlist');
    expect(header?.itemCount, 383);
  });

  test('a continuation item without a browse token cannot complete a page', () {
    final response = _response([
      _song(1),
      {
        'continuationItemRenderer': {
          'continuationEndpoint': {
            'continuationCommand': {
              'token': 'watch-next-only',
              'request': 'CONTINUATION_REQUEST_TYPE_WATCH_NEXT',
            },
          },
        },
      },
    ]);

    expect(parser.isPlaylistEntryPage(response), isFalse);
  });

  for (final label in const [
    '1,250 songs',
    '1,250 tracks',
    '1.250 canciones',
    '1\u202f250 titres',
    '1\u00a0250 músicas',
    '1250 曲',
    '1250 곡',
    '1250 首',
  ]) {
    test('reads localized declared count from $label', () {
      final header = parser.parsePlaylistHeader({
        'musicDetailHeaderRenderer': {
          'title': {'simpleText': 'Large playlist'},
          'subtitle': {'simpleText': label},
        },
      }, playlistId: 'PL-large');
      expect(header?.itemCount, 1250);
    });
  }
}

Map<String, Object?> _response(
  List<Object?> items, {
  String responseKey = 'onResponseReceivedActions',
  String operation = 'appendContinuationItemsAction',
}) => {
  responseKey: [_operation(items, operation: operation)],
};

Map<String, Object?> _operation(
  List<Object?> items, {
  String operation = 'appendContinuationItemsAction',
}) => {
  operation: {'continuationItems': items},
};

Map<String, Object?> _song(int index) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {
      'videoId': 'same-video',
      'playlistSetVideoId': 'set-$index',
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {'text': 'Song $index'},
            ],
          },
        },
      },
    ],
  },
};

Map<String, Object?> _token(String token) => {
  'continuationItemRenderer': {
    'continuationEndpoint': {
      'continuationCommand': {'token': token},
    },
  },
};

Map<String, Object?> _playlist() => {
  'musicTwoRowItemRenderer': {
    'title': {
      'runs': [
        {'text': 'Saved playlist'},
      ],
    },
    'navigationEndpoint': {
      'browseEndpoint': {'browseId': 'VLPL-saved'},
    },
  },
};

Map<String, Object?> _artist() => {
  'musicTwoRowItemRenderer': {
    'title': {
      'runs': [
        {'text': 'Artist'},
      ],
    },
    'navigationEndpoint': {
      'browseEndpoint': {'browseId': 'UC-artist'},
    },
  },
};
