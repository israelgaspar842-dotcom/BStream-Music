import 'dart:ui' as ui;

import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:bstream_music/features/music/presentation/providers/lyrics_share_providers.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:bstream_music/features/music/presentation/widgets/lyrics_share_photo_cropper.dart';
import 'package:bstream_music/features/music/presentation/widgets/playlist_artwork_editor.dart';
import 'package:bstream_music/services/sharing/lyrics_share_photo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform artwork offers Random and Custom on the cover', (
      tester,
    ) async {
      final controller = _ArtworkPlaylists();
      final photos = _Photos();
      await _open(tester, controller, photos, platform: platform);

      expect(
        find.byKey(const ValueKey('playlist-artwork-dialog')),
        findsOneWidget,
      );
      expect(find.text('Portada de la playlist'), findsOneWidget);
      expect(find.text('Aleatorio'), findsOneWidget);
      expect(find.text('Personalizada'), findsOneWidget);
      expect(controller.resets, isEmpty);
      expect(controller.saved, isEmpty);
      expect(photos.calls, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.resets, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Random clears only the custom artwork without picking a photo', (
    tester,
  ) async {
    final controller = _ArtworkPlaylists();
    final photos = _Photos();
    await _open(tester, controller, photos);
    await tester.tap(find.byKey(const ValueKey('playlist-artwork-random')));
    await tester.pumpAndSettle();

    expect(controller.resets, [_playlist.id]);
    expect(controller.current.customArtworkFileName, isNull);
    expect(controller.current.trackIds, _playlist.trackIds);
    expect(controller.saved, isEmpty);
    expect(photos.calls, 0);
    expect(find.byKey(const ValueKey('playlist-artwork-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the gallery retains the existing cover', (
    tester,
  ) async {
    final controller = _ArtworkPlaylists();
    final photos = _Photos();
    await _open(tester, controller, photos);
    await _chooseCustom(tester);

    expect(photos.calls, 1);
    expect(
      controller.current.customArtworkFileName,
      _playlist.customArtworkFileName,
    );
    expect(controller.saved, isEmpty);
    expect(controller.resets, isEmpty);
    expect(find.byType(LyricsSharePhotoCropper), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Custom reuses the square photo cropper before saving', (
    tester,
  ) async {
    final photo = await _image(tester, 600, 300);
    final controller = _ArtworkPlaylists();
    final photos = _Photos(photo: photo);
    await _open(tester, controller, photos);
    await _chooseCustom(tester);

    final cropper = tester.widget<LyricsSharePhotoCropper>(
      find.byType(LyricsSharePhotoCropper),
    );
    expect(cropper.aspectRatio, 1);
    expect(controller.saved, isEmpty);
    await tester.tap(find.byKey(const ValueKey('lyrics-photo-crop-confirm')));
    await tester.pumpAndSettle();

    expect(photos.calls, 1);
    expect(controller.saved, hasLength(1));
    final saved = controller.saved.single;
    expect(saved.playlistId, _playlist.id);
    expect(saved.imageSize, const Size(600, 300));
    expect(saved.crop.left, closeTo(.25, .000001));
    expect(saved.crop.top, closeTo(0, .000001));
    expect(saved.crop.width, closeTo(.5, .000001));
    expect(saved.crop.height, closeTo(1, .000001));
    expect(
      saved.crop.width * saved.imageSize.width,
      closeTo(saved.crop.height * saved.imageSize.height, .000001),
    );
    expect(controller.resets, isEmpty);
    expect(find.byType(LyricsSharePhotoCropper), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the crop retains the existing cover', (tester) async {
    final photo = await _image(tester, 300, 900);
    final controller = _ArtworkPlaylists();
    final photos = _Photos(photo: photo);
    await _open(tester, controller, photos);
    await _chooseCustom(tester);
    expect(find.byType(LyricsSharePhotoCropper), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    expect(controller.saved, isEmpty);
    expect(controller.resets, isEmpty);
    expect(
      controller.current.customArtworkFileName,
      _playlist.customArtworkFileName,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a gallery error keeps the cover and reports a localized error', (
    tester,
  ) async {
    final controller = _ArtworkPlaylists();
    await _open(tester, controller, _Photos(fail: true));
    await _chooseCustom(tester);

    expect(
      find.text('No se pudo actualizar la portada de la playlist.'),
      findsOneWidget,
    );
    expect(
      controller.current.customArtworkFileName,
      _playlist.customArtworkFileName,
    );
    expect(controller.saved, isEmpty);
    expect(controller.resets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save error keeps the previous cover after cropping', (
    tester,
  ) async {
    final photo = await _image(tester, 600, 300);
    final controller = _ArtworkPlaylists(failSave: true);
    await _open(tester, controller, _Photos(photo: photo));
    await _chooseCustom(tester);
    await tester.tap(find.byKey(const ValueKey('lyrics-photo-crop-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo actualizar la portada de la playlist.'),
      findsOneWidget,
    );
    expect(
      controller.current.customArtworkFileName,
      _playlist.customArtworkFileName,
    );
    expect(controller.resets, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

final _playlist = Playlist(
  id: 'custom-artwork-playlist',
  name: 'Mi playlist',
  trackIds: const ['track-one', 'track-two'],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  customArtworkFileName: 'playlist_previous.png',
);

Future<void> _open(
  WidgetTester tester,
  _ArtworkPlaylists controller,
  _Photos photos, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.binding.setSurfaceSize(
    platform == TargetPlatform.windows
        ? const Size(1200, 800)
        : const Size(390, 820),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStringsProvider.overrideWithValue(
          const AppStrings(AppLanguage.spanish),
        ),
        databaseServiceProvider.overrideWith(
          (ref) => throw StateError('The editor fixture cannot use user data'),
        ),
        playlistsControllerProvider.overrideWith(() => controller),
        lyricsSharePhotoServiceProvider.overrideWithValue(photos),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Center(
            child: PlaylistArtworkEditor(
              playlist: _playlist,
              child: const ColoredBox(
                color: Colors.teal,
                child: SizedBox.square(
                  key: ValueKey('editable-playlist-cover'),
                  dimension: 140,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('editable-playlist-cover')));
  await tester.pumpAndSettle();
}

Future<void> _chooseCustom(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('playlist-artwork-custom')));
  await tester.pumpAndSettle();
}

Future<ui.Image> _image(WidgetTester tester, int width, int height) async {
  final image = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.teal, BlendMode.src);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }))!;
  // The editor owns the photo after the fake picker returns it.
  return image;
}

class _Photos implements LyricsSharePhotoService {
  _Photos({this.photo, this.fail = false});

  final ui.Image? photo;
  final bool fail;
  int calls = 0;

  @override
  Future<ui.Image?> pickPhoto() async {
    calls++;
    if (fail) throw const FormatException('Invalid photo fixture');
    return photo;
  }
}

typedef _SavedArtwork = ({String playlistId, Size imageSize, Rect crop});

class _ArtworkPlaylists extends PlaylistsController {
  _ArtworkPlaylists({this.failSave = false});

  final bool failSave;
  Playlist current = _playlist;
  final List<String> resets = [];
  final List<_SavedArtwork> saved = [];

  @override
  Future<List<Playlist>> build() async => [current];

  @override
  Future<void> resetArtwork(String playlistId) async {
    resets.add(playlistId);
    current = current.copyWith(customArtworkFileName: null);
    state = AsyncData([current]);
  }

  @override
  Future<void> setCustomArtwork(
    String playlistId,
    ui.Image image,
    Rect crop,
  ) async {
    if (failSave) throw StateError('Artwork save fixture failed');
    saved.add((
      playlistId: playlistId,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      crop: crop,
    ));
    current = current.copyWith(customArtworkFileName: 'playlist_new.png');
    state = AsyncData([current]);
  }
}
