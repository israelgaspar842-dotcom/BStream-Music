import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bstream_music/features/music/domain/entities/catalog_playlist.dart';
import 'package:bstream_music/features/music/domain/entities/playlist.dart';
import 'package:bstream_music/features/music/presentation/providers/music_providers.dart';
import 'package:bstream_music/features/music/presentation/providers/playlist_artwork_providers.dart';
import 'package:bstream_music/services/storage/library_operation_coordinator.dart';
import 'package:bstream_music/services/storage/local_database_service.dart';
import 'package:bstream_music/services/storage/playlist_artwork_service.dart';
import 'package:bstream_music/services/player/player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _MemoryArtworkDatabase database;
  late _ArtworkSettings settings;
  late LibraryOperationCoordinator coordinator;
  late ProviderContainer container;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'bstream-playlist-cover-change-',
    );
    database = _MemoryArtworkDatabase();
    settings = _ArtworkSettings(root.path);
    coordinator = LibraryOperationCoordinator();
    container = ProviderContainer(
      overrides: [
        databaseServiceProvider.overrideWithValue(database),
        settingsControllerProvider.overrideWith(() => settings),
        libraryOperationCoordinatorProvider.overrideWithValue(coordinator),
        playerControllerProvider.overrideWith(
          () => throw StateError('Artwork must not touch playback'),
        ),
        youtubeMusicPlaylistSyncControllerProvider.overrideWith(
          () => throw StateError('Artwork must not request account sync'),
        ),
      ],
    );
    await container.read(settingsControllerProvider.future);
    await container.read(playlistsControllerProvider.future);
  });
  tearDown(() async {
    container.dispose();
    await coordinator.dispose();
    await root.delete(recursive: true);
  });

  test(
    'cover edits update cards and the header without changing playlist order',
    () async {
      final image = await _image();
      addTearDown(image.dispose);
      final before = container.read(playlistsControllerProvider).requireValue;
      final original = database.playlists.first;
      final headerSubscription = container.listen(
        catalogPlaylistProvider(original.id),
        (_, _) {},
      );
      addTearDown(headerSubscription.close);
      await container.read(catalogPlaylistProvider(original.id).future);

      await container
          .read(playlistsControllerProvider.notifier)
          .setCustomArtwork(
            original.id,
            image,
            const ui.Rect.fromLTWH(0, 0, 1, 1),
          );
      final after = container.read(playlistsControllerProvider).requireValue;
      expect(
        after.map((playlist) => playlist.id),
        before.map((playlist) => playlist.id),
      );
      final changed = after.firstWhere(
        (playlist) => playlist.id == original.id,
      );
      expect(changed.name, original.name);
      expect(changed.trackIds, original.trackIds);
      expect(changed.createdAt, original.createdAt);
      expect(changed.updatedAt, original.updatedAt);
      expect(changed.localRevision, original.localRevision);
      expect(changed.customArtworkFileName, isNotNull);
      final header = await container.read(
        catalogPlaylistProvider(original.id).future,
      );
      expect(
        header!.playlist.customArtworkFileName,
        changed.customArtworkFileName,
      );
      expect(
        await File(
          '${root.path}/thumbnails/${changed.customArtworkFileName}',
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'database failure rolls back the new file and preserves the previous cover',
    () async {
      final image = await _image();
      addTearDown(image.dispose);
      final controller = container.read(playlistsControllerProvider.notifier);
      await controller.setCustomArtwork(
        'target',
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      );
      final oldName = database.playlists.first.customArtworkFileName!;
      database.failWrite = true;
      await expectLater(
        controller.setCustomArtwork(
          'target',
          image,
          const ui.Rect.fromLTWH(0, 0, 1, 1),
        ),
        throwsStateError,
      );
      expect(database.playlists.first.customArtworkFileName, oldName);
      expect(
        (await Directory(
          '${root.path}/thumbnails',
        ).list().toList()).map((file) => file.uri.pathSegments.last),
        [oldName],
      );
      expect(
        container
            .read(playlistsControllerProvider)
            .requireValue
            .firstWhere((playlist) => playlist.id == 'target')
            .customArtworkFileName,
        oldName,
      );
    },
  );

  test(
    'replacement and reset remove old covers but preserve song thumbnails',
    () async {
      final image = await _image();
      addTearDown(image.dispose);
      final controller = container.read(playlistsControllerProvider.notifier);
      await controller.setCustomArtwork(
        'target',
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      );
      final oldName = database.playlists.first.customArtworkFileName!;
      final song = await File(
        '${root.path}/thumbnails/song.jpg',
      ).writeAsBytes([7]);
      await controller.setCustomArtwork(
        'target',
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      );
      final newName = database.playlists.first.customArtworkFileName!;
      expect(newName, isNot(oldName));
      expect(await File('${root.path}/thumbnails/$oldName').exists(), isFalse);
      await controller.resetArtwork('target');
      expect(database.playlists.first.customArtworkFileName, isNull);
      expect(await File('${root.path}/thumbnails/$newName').exists(), isFalse);
      expect(await song.readAsBytes(), [7]);
    },
  );

  test(
    'a pending directory migration completes before the cover is written',
    () async {
      final image = await _image();
      addTearDown(image.dispose);
      final target = '${root.path}/moved';
      final entered = Completer<void>();
      final release = Completer<void>();
      final maintenance = coordinator.runExclusive(
        LibraryMaintenancePhase.migratingDirectory,
        () async {
          entered.complete();
          await release.future;
          settings.changeRoot(target);
        },
      );
      await entered.future;
      final change = container
          .read(playlistsControllerProvider.notifier)
          .setCustomArtwork(
            'target',
            image,
            const ui.Rect.fromLTWH(0, 0, 1, 1),
          );
      await Future<void>.delayed(Duration.zero);
      expect(database.writes, 0);
      expect(await Directory('${root.path}/thumbnails').exists(), isFalse);
      release.complete();
      await maintenance;
      await change;
      final name = database.playlists.first.customArtworkFileName!;
      expect(await File('$target/thumbnails/$name').exists(), isTrue);
      expect(await File('${root.path}/thumbnails/$name').exists(), isFalse);
    },
  );

  test(
    'path resolution is retained until the name or media root changes',
    () async {
      const name = 'playlist_relocated.png';
      final firstFolder = await Directory('${root.path}/thumbnails').create();
      await File('${firstFolder.path}/$name').writeAsBytes([1]);
      final secondFolder = await Directory(
        '${root.path}/next/thumbnails',
      ).create(recursive: true);
      await File('${secondFolder.path}/$name').writeAsBytes([2]);
      final service = _CountingArtworkService();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => settings = _ArtworkSettings(root.path),
          ),
          playlistArtworkServiceProvider.overrideWithValue(service),
        ],
      );
      await container.read(settingsControllerProvider.future);
      final subscription = container.listen(
        playlistArtworkPathProvider(name),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        p.normalize(
          (await container.read(playlistArtworkPathProvider(name).future))!,
        ),
        p.normalize(p.join(firstFolder.path, name)),
      );
      for (var index = 0; index < 5; index++) {
        container.read(playlistArtworkPathProvider(name));
      }
      expect(service.resolves, 1);
      settings.changeRoot('${root.path}/next');
      expect(
        p.normalize(
          (await container.read(playlistArtworkPathProvider(name).future))!,
        ),
        p.normalize(p.join(secondFolder.path, name)),
      );
      expect(service.resolves, 2);
    },
  );

  test(
    'deleting waits for a cover change and removes its committed image',
    () async {
      container.dispose();
      settings = _ArtworkSettings(root.path);
      final player = _DeletePlayer();
      final sync = _DeleteSync();
      container = _deleteContainer(
        database,
        settings,
        coordinator,
        player,
        sync,
      );
      await container.read(playlistsControllerProvider.future);
      final image = await _image();
      addTearDown(image.dispose);
      final controller = container.read(playlistsControllerProvider.notifier);
      await controller.setCustomArtwork(
        'target',
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      );
      final song = await File(
        '${root.path}/thumbnails/song.jpg',
      ).writeAsBytes([9]);
      database.writeEntered = Completer<void>();
      database.releaseWrite = Completer<void>();
      final changing = controller.setCustomArtwork(
        'target',
        image,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      );
      await database.writeEntered!.future;
      final deleting = controller.deletePlaylist('target');
      await Future<void>.delayed(Duration.zero);
      expect(database.deletes, 0);
      database.releaseWrite!.complete();
      await changing;
      await deleting;
      expect(database.deletes, 1);
      expect(database.playlists.first.deletedAt, isNotNull);
      expect(
        container
            .read(playlistsControllerProvider)
            .requireValue
            .map((playlist) => playlist.id),
        ['other'],
      );
      expect(
        (await Directory(
          '${root.path}/thumbnails',
        ).list().toList()).map((file) => p.normalize(file.path)),
        [p.normalize(song.path)],
      );
      expect(player.cleared, [
        PlayerController.playlistQueueSourceId('target'),
      ]);
      expect(sync.requests, 1);
      await expectLater(
        controller.setCustomArtwork(
          'target',
          image,
          const ui.Rect.fromLTWH(0, 0, 1, 1),
        ),
        throwsStateError,
      );
      expect(database.writes, 2);
      expect(await song.readAsBytes(), [9]);
    },
  );

  test('a failed playlist deletion retains the selected cover', () async {
    container.dispose();
    settings = _ArtworkSettings(root.path);
    final player = _DeletePlayer();
    final sync = _DeleteSync();
    container = _deleteContainer(database, settings, coordinator, player, sync);
    await container.read(playlistsControllerProvider.future);
    final image = await _image();
    addTearDown(image.dispose);
    final controller = container.read(playlistsControllerProvider.notifier);
    await controller.setCustomArtwork(
      'target',
      image,
      const ui.Rect.fromLTWH(0, 0, 1, 1),
    );
    final name = database.playlists.first.customArtworkFileName!;
    database.failDelete = true;
    await expectLater(controller.deletePlaylist('target'), throwsStateError);
    expect(database.playlists.first.deletedAt, isNull);
    expect(await File('${root.path}/thumbnails/$name').exists(), isTrue);
    expect(player.cleared, isEmpty);
    expect(sync.requests, 0);
  });

  test(
    'deleting an automatic cover never initializes image-storage settings',
    () async {
      container.dispose();
      final player = _DeletePlayer();
      final sync = _DeleteSync();
      container = ProviderContainer(
        overrides: [
          databaseServiceProvider.overrideWithValue(database),
          settingsControllerProvider.overrideWith(
            () => throw StateError('Automatic covers need no image storage'),
          ),
          playerControllerProvider.overrideWith(() => player),
          youtubeMusicPlaylistSyncControllerProvider.overrideWith(() => sync),
        ],
      );
      await container.read(playlistsControllerProvider.future);
      await container
          .read(playlistsControllerProvider.notifier)
          .deletePlaylist('target');
      expect(database.deletes, 1);
      expect(sync.requests, 1);
    },
  );
}

ProviderContainer _deleteContainer(
  _MemoryArtworkDatabase database,
  _ArtworkSettings settings,
  LibraryOperationCoordinator coordinator,
  _DeletePlayer player,
  _DeleteSync sync,
) => ProviderContainer(
  overrides: [
    databaseServiceProvider.overrideWithValue(database),
    settingsControllerProvider.overrideWith(() => settings),
    libraryOperationCoordinatorProvider.overrideWithValue(coordinator),
    playerControllerProvider.overrideWith(() => player),
    youtubeMusicPlaylistSyncControllerProvider.overrideWith(() => sync),
  ],
);

class _MemoryArtworkDatabase extends LocalDatabaseService {
  final playlists = [
    Playlist(
      id: 'target',
      name: 'Target',
      trackIds: const ['saved'],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      localRevision: 4,
    ),
    Playlist(
      id: 'other',
      name: 'Other',
      trackIds: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
    ),
  ];
  bool failWrite = false;
  bool failDelete = false;
  int writes = 0;
  int deletes = 0;
  Completer<void>? writeEntered;
  Completer<void>? releaseWrite;

  @override
  Future<List<Playlist>> getCatalogPlaylists({
    bool includeDeleted = false,
  }) async => [
    for (final playlist in playlists)
      if (includeDeleted || playlist.deletedAt == null) playlist,
  ];

  @override
  Future<CatalogPlaylist?> getCatalogPlaylist(
    String playlistId, {
    bool includeDeletedEntries = false,
  }) async {
    final playlist = playlists
        .where((playlist) => playlist.id == playlistId)
        .firstOrNull;
    return playlist == null
        ? null
        : CatalogPlaylist(playlist: playlist, entries: const []);
  }

  @override
  Future<Playlist?> setPlaylistArtworkFileName(
    String playlistId,
    String? fileName,
  ) async {
    writes++;
    if (failWrite) throw StateError('Artwork commit failed');
    if (writeEntered != null) {
      writeEntered!.complete();
      await releaseWrite!.future;
      writeEntered = null;
      releaseWrite = null;
    }
    final index = playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index < 0 || playlists[index].deletedAt != null) return null;
    return playlists[index] = playlists[index].copyWith(
      customArtworkFileName: fileName,
    );
  }

  @override
  Future<void> tombstoneCatalogPlaylist({
    required String playlistId,
    required DateTime now,
    bool deleteRemote = false,
    String? remoteAccountKey,
  }) async {
    if (failDelete) throw StateError('Playlist deletion failed');
    deletes++;
    final index = playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index >= 0) {
      playlists[index] = playlists[index].copyWith(deletedAt: now);
    }
  }
}

class _DeletePlayer extends PlayerController {
  final cleared = <String>[];
  @override
  Future<PlayerSnapshot> build() async =>
      const PlayerSnapshot(status: PlayerStatus.idle);
  @override
  Future<bool> clearQueueSource(String sourceId) async {
    cleared.add(sourceId);
    return true;
  }
}

class _DeleteSync extends YouTubeMusicPlaylistSyncController {
  int requests = 0;
  @override
  YouTubeMusicPlaylistSyncState build() =>
      const YouTubeMusicPlaylistSyncState();
  @override
  void requestAutomaticSync() => requests++;
}

class _ArtworkSettings extends SettingsController {
  _ArtworkSettings(this.root);
  final String root;
  @override
  Future<SettingsState> build() async =>
      SettingsState(downloadDirectory: root, language: AppLanguage.spanish);
  void changeRoot(String root) =>
      state = AsyncData(state.requireValue.copyWith(downloadDirectory: root));
}

class _CountingArtworkService extends PlaylistArtworkService {
  int resolves = 0;
  @override
  Future<String?> resolve({
    required String mediaRoot,
    required String? fileName,
  }) {
    resolves++;
    return super.resolve(mediaRoot: mediaRoot, fileName: fileName);
  }
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF79C8B6), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(48, 48);
  } finally {
    picture.dispose();
  }
}
