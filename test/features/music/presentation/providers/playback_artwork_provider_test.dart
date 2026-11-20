import 'package:bstream_music/features/music/domain/entities/local_track.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:bstream_music/features/music/presentation/providers/playback_artwork_provider.dart';
import 'package:bstream_music/services/player/player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'saved track ID wins over an earlier track with the same source URL',
    () async {
      final earlier = _track('earlier', thumbnail: '/cover/earlier.png');
      final selected = _track('selected', thumbnail: '/cover/selected.png');
      final container = await _container(
        const PlayerSnapshot(
          status: PlayerStatus.playing,
          trackId: ' selected ',
          sourceUrl: 'https://example.com/audio',
        ),
        [earlier, selected],
      );
      expect(container.read(playbackLocalTrackProvider), same(selected));
      expect(
        container.read(playbackArtworkProvider).source,
        '/cover/selected.png',
      );
    },
  );

  test('missing ID falls back to a normalized source URL', () async {
    final saved = _track('saved', source: ' https://example.com/audio ');
    final container = await _container(
      const PlayerSnapshot(
        status: PlayerStatus.playing,
        trackId: 'unknown',
        sourceUrl: ' https://example.com/audio ',
      ),
      [saved],
    );
    expect(container.read(playbackLocalTrackProvider), same(saved));
  });

  test(
    'artwork uses remote playback cover without a saved match and retains local offline fallback',
    () async {
      final saved = _track(
        'saved',
        thumbnail: 'https://example.com/cover.png',
        offline: '/cover/offline.png',
      );
      final player = _ArtworkPlayer(
        const PlayerSnapshot(
          status: PlayerStatus.playing,
          trackId: 'remote',
          thumbnailUrl: ' https://example.com/remote.png ',
        ),
      );
      final container = await _container(player.initial, [
        saved,
      ], player: player);
      expect(container.read(playbackArtworkProvider), (
        source: 'https://example.com/remote.png',
        fallback: null,
      ));

      player.emit(
        const PlayerSnapshot(
          status: PlayerStatus.playing,
          trackId: 'saved',
          thumbnailUrl: 'https://example.com/remote.png',
        ),
      );
      await container.pump();
      expect(container.read(playbackArtworkProvider), (
        source: 'https://example.com/cover.png',
        fallback: '/cover/offline.png',
      ));
    },
  );

  test('playback position updates do not notify artwork consumers', () async {
    final player = _ArtworkPlayer(
      const PlayerSnapshot(status: PlayerStatus.playing, trackId: 'saved'),
    );
    final container = await _container(player.initial, [
      _track('saved'),
    ], player: player);
    var notifications = 0;
    final subscription = container.listen(
      playbackArtworkProvider,
      (_, _) => notifications++,
    );
    addTearDown(subscription.close);

    player.emit(
      const PlayerSnapshot(
        status: PlayerStatus.playing,
        trackId: 'saved',
        position: Duration(seconds: 5),
      ),
    );
    await container.pump();
    expect(notifications, 0);
  });
}

Future<ProviderContainer> _container(
  PlayerSnapshot snapshot,
  List<LocalTrack> tracks, {
  _ArtworkPlayer? player,
}) async {
  final controller = player ?? _ArtworkPlayer(snapshot);
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(() => controller),
      libraryTracksProvider.overrideWith((ref) async => tracks),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(playbackArtworkProvider, (_, _) {});
  addTearDown(subscription.close);
  await container.read(playerControllerProvider.future);
  await container.read(libraryTracksProvider.future);
  await container.pump();
  return container;
}

LocalTrack _track(
  String id, {
  String source = 'https://example.com/audio',
  String thumbnail = '/cover/saved.png',
  String? offline,
}) => LocalTrack(
  id: id,
  title: id,
  artist: 'Artist',
  filePath: '/audio/$id.mp3',
  addedAt: DateTime(2026),
  sourceUrl: source,
  thumbnailUrl: thumbnail,
  thumbnailPath: offline,
);

class _ArtworkPlayer extends PlayerController {
  _ArtworkPlayer(this.initial);
  final PlayerSnapshot initial;

  @override
  Future<PlayerSnapshot> build() async => initial;

  void emit(PlayerSnapshot snapshot) => state = AsyncData(snapshot);
}
