import 'package:bstream_music/features/music/data/models/playlist_model.dart';
import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 11, 12);

  Playlist playlist({String? artwork}) => Playlist(
    id: 'playlist',
    name: 'My playlist',
    trackIds: const ['one', 'two'],
    createdAt: createdAt,
    updatedAt: createdAt,
    customArtworkFileName: artwork,
  );

  test('custom artwork survives model serialization and unrelated edits', () {
    final original = playlist(artwork: 'playlist_custom-cover.png');
    final edited = original.copyWith(name: 'Renamed');
    expect(edited.customArtworkFileName, original.customArtworkFileName);
    final restored = PlaylistModel.fromMap(
      PlaylistModel.fromEntity(edited).toMap(),
    );
    expect(restored.customArtworkFileName, 'playlist_custom-cover.png');
    expect(restored.name, 'Renamed');
    expect(restored.trackIds, original.trackIds);
    final automatic = restored.copyWith(customArtworkFileName: null);
    expect(automatic.customArtworkFileName, isNull);
  });

  test('old playlist records retain automatic artwork', () {
    final legacy = PlaylistModel.fromEntity(playlist()).toMap()
      ..remove('custom_artwork_file_name');
    expect(PlaylistModel.fromMap(legacy).customArtworkFileName, isNull);
  });

  test('only complete app-owned image basenames are accepted', () {
    for (final valid in [
      'playlist_45aebf31-a1c3-41fb-a08b-0d16661cdf82.png',
      'playlist_custom_123.jpg',
      'playlist_custom.jpeg',
    ]) {
      expect(Playlist.isValidCustomArtworkFileName(valid), isTrue);
    }
    for (final invalid in [
      '',
      '../playlist_cover.png',
      '/playlist_cover.png',
      r'C:\playlist_cover.png',
      'file:///playlist_cover.png',
      'song_cover.png',
      'playlist_cover.png\n',
      'playlist_cover.png/other',
      'playlist_cover.svg',
    ]) {
      expect(
        Playlist.isValidCustomArtworkFileName(invalid),
        isFalse,
        reason: invalid,
      );
    }
  });
}
