part of 'music_providers.dart';

final libraryCsvServiceProvider = Provider<LibraryCsvService>((ref) {
  return const LibraryCsvService();
});

final libraryCsvImportServiceProvider = Provider<LibraryCsvImportService>((
  ref,
) {
  return LibraryCsvImportService(
    ref.watch(libraryRepositoryProvider),
    (query) => ref.read(searchTracksProvider).call(query),
    (track, {required taskId, onResolved}) async {
      final outcome = await ref
          .read(localTrackDownloadHelperProvider)
          .resolveForLibrary(
            track,
            taskId: taskId,
            onResolved: onResolved,
            allowConcurrentDownload: true,
          );
      return LibraryCsvDownloadedTrack(
        track: outcome.track,
        reusedExisting: outcome.reusedExisting,
      );
    },
    _libraryCsvGate(ref),
    maxConcurrentTracks: 3,
  );
});

final libraryCsvTransferControllerProvider =
    NotifierProvider<LibraryCsvTransferController, LibraryCsvTransferState>(
      LibraryCsvTransferController.new,
    );

enum LibraryCsvTransferPhase {
  idle,
  parsing,
  importing,
  exporting,
  completed,
  failed,
}

class LibraryCsvTransferState {
  const LibraryCsvTransferState({
    this.phase = LibraryCsvTransferPhase.idle,
    this.document,
    this.progress,
    this.result,
    this.error,
    this.errorStackTrace,
    this.cancelRequested = false,
  });

  final LibraryCsvTransferPhase phase;
  final LibraryCsvDocument? document;
  final LibraryCsvImportProgress? progress;
  final LibraryCsvImportResult? result;
  final Object? error;
  final StackTrace? errorStackTrace;
  final bool cancelRequested;

  bool get isBusy =>
      phase == LibraryCsvTransferPhase.parsing ||
      phase == LibraryCsvTransferPhase.importing ||
      phase == LibraryCsvTransferPhase.exporting;
}

class LibraryCsvTransferController extends Notifier<LibraryCsvTransferState> {
  bool _cancelRequested = false;

  @override
  LibraryCsvTransferState build() => const LibraryCsvTransferState();

  Future<LibraryCsvDocument> preview(String path) async {
    _ensureIdle();
    _cancelRequested = false;
    state = const LibraryCsvTransferState(
      phase: LibraryCsvTransferPhase.parsing,
    );
    try {
      final document = await compute(_parseLibraryCsvFile, path);
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.completed,
        document: document,
      );
      return document;
    } catch (error, stackTrace) {
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.failed,
        error: error,
        errorStackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<LibraryCsvImportResult> importDocument(
    LibraryCsvDocument document,
  ) async {
    _ensureIdle();
    _cancelRequested = false;
    state = LibraryCsvTransferState(
      phase: LibraryCsvTransferPhase.importing,
      document: document,
    );
    try {
      final result = await ref
          .read(libraryCsvImportServiceProvider)
          .import(
            document,
            isCancellationRequested: () => _cancelRequested,
            onProgress: (progress) {
              if (state.phase != LibraryCsvTransferPhase.importing) return;
              state = LibraryCsvTransferState(
                phase: LibraryCsvTransferPhase.importing,
                document: document,
                progress: progress,
                cancelRequested: _cancelRequested,
              );
            },
          );
      ref
        ..invalidate(libraryTracksProvider)
        ..invalidate(playlistsControllerProvider);
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.completed,
        document: document,
        result: result,
        cancelRequested: result.cancelled,
      );
      return result;
    } catch (error, stackTrace) {
      ref
        ..invalidate(libraryTracksProvider)
        ..invalidate(playlistsControllerProvider);
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.failed,
        document: document,
        error: error,
        errorStackTrace: stackTrace,
        cancelRequested: _cancelRequested,
      );
      rethrow;
    }
  }

  void requestCancel() {
    if (state.phase != LibraryCsvTransferPhase.importing || _cancelRequested) {
      return;
    }
    _cancelRequested = true;
    final progress = state.progress;
    state = LibraryCsvTransferState(
      phase: LibraryCsvTransferPhase.importing,
      document: state.document,
      progress: progress == null
          ? null
          : LibraryCsvImportProgress(
              total: progress.total,
              processed: progress.processed,
              downloaded: progress.downloaded,
              reused: progress.reused,
              failed: progress.failed,
              currentTitle: progress.currentTitle,
              cancelRequested: true,
            ),
      cancelRequested: true,
    );
  }

  Future<LibraryCsvDocument> prepareExport() async {
    _ensureIdle();
    _cancelRequested = false;
    state = const LibraryCsvTransferState(
      phase: LibraryCsvTransferPhase.exporting,
    );
    try {
      final document = await ref
          .read(libraryOperationCoordinatorProvider)
          .runExclusive(LibraryMaintenancePhase.exportingCsv, () async {
            final repository = ref.read(libraryRepositoryProvider);
            final tracks = await repository.getLocalTracks();
            final playlists = await repository.getPlaylists();
            return LibraryCsvDocument.fromLibrary(
              tracks: tracks,
              playlists: playlists,
            );
          });
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.completed,
        document: document,
      );
      return document;
    } catch (error, stackTrace) {
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.failed,
        error: error,
        errorStackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void reset() {
    if (state.isBusy) return;
    _cancelRequested = false;
    state = const LibraryCsvTransferState();
  }

  Future<void> shareSinglePlaylist(
    Playlist playlist, {
    Rect? sharePositionOrigin,
  }) async {
    _ensureIdle();
    _cancelRequested = false;
    state = const LibraryCsvTransferState(
      phase: LibraryCsvTransferPhase.exporting,
    );
    try {
      final document = await ref
          .read(libraryOperationCoordinatorProvider)
          .runExclusive(LibraryMaintenancePhase.exportingCsv, () async {
            final repository = ref.read(libraryRepositoryProvider);
            final localTracks = await repository.getLocalTracks();
            final tracksById = <String, LocalTrack>{
              for (final track in localTracks) track.id: track,
            };
            // Catalog entries are the authoritative order and also carry
            // songs that were added without downloading them. Legacy rows
            // without entries fall back to the local `trackIds` order.
            final catalog = await ref
                .read(databaseServiceProvider)
                .getCatalogPlaylist(playlist.id);
            final sourcePlaylist = catalog?.playlist ?? playlist;
            final entries =
                catalog?.entries
                    .where(
                      (entry) =>
                          !entry.isDeleted &&
                          entry.playlistId == sourcePlaylist.id,
                    )
                    .toList(growable: false) ??
                const <PlaylistEntry>[];

            final rows = <LibraryCsvTrack>[];
            final exportedLocalIds = <String>{};
            final exportedVideoIds = <String>{};
            var rowNumber = 2;
            for (final entry in entries) {
              final row = _trackFromCatalogEntry(
                entry,
                rowNumber++,
                LibraryCsvMembership(
                  name: sourcePlaylist.name,
                  position: entry.position + 1,
                  id: sourcePlaylist.id,
                ),
              );
              rows.add(row);
              final localId = entry.localTrackId;
              if (localId != null && localId.isNotEmpty) {
                exportedLocalIds.add(localId);
              } else if (entry.track.provider == CatalogProvider.local) {
                exportedLocalIds.add(entry.track.providerId);
              }
              final videoId = row.youtubeVideoId;
              if (videoId != null && videoId.isNotEmpty) {
                exportedVideoIds.add(videoId);
              }
            }

            // Legacy playlists (or rows written by an older CSV import) only
            // carry `trackIds`. Append whatever the catalog entries did not
            // already cover so no song is silently dropped from the export.
            var nextPosition = entries.isEmpty ? 1 : entries.last.position + 2;
            for (final trackId in sourcePlaylist.trackIds) {
              if (!exportedLocalIds.add(trackId)) {
                continue;
              }
              final track = tracksById[trackId];
              if (track == null) {
                continue;
              }
              final videoId =
                  _youtubeVideoId(track.sourceId) ??
                  _youtubeVideoId(track.sourceUrl);
              if (videoId != null && !exportedVideoIds.add(videoId)) {
                continue;
              }
              rows.add(
                _trackFromLocal(track, rowNumber++, [
                  LibraryCsvMembership(
                    name: sourcePlaylist.name,
                    position: nextPosition++,
                    id: sourcePlaylist.id,
                  ),
                ]),
              );
            }

            if (rows.isEmpty) {
              throw const FormatException(
                'La playlist no contiene canciones para compartir.',
              );
            }

            return LibraryCsvDocument(
              tracks: rows,
              detectedFormat: LibraryCsvDetectedFormat.bstream,
              defaultPlaylistName: sourcePlaylist.name,
              hasPlaylistColumn: true,
            );
          });

      final temporaryRoot = await getTemporaryDirectory();
      final exportDirectory = await Directory(
        p.join(temporaryRoot.path, 'ivg-playlist-shares'),
      ).create(recursive: true);
      final fileName = _shareFileName(document.defaultPlaylistName);
      final file = await const LibraryCsvService().createExportFile(
        document: document,
        profile: LibraryCsvProfile.bstream,
        outputPath: p.join(exportDirectory.path, fileName),
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: 'text/csv', name: fileName),
          ],
          fileNameOverrides: [fileName],
          title: document.defaultPlaylistName,
          subject: document.defaultPlaylistName,
          text: 'Escucha mi playlist en IVG Music',
          // iPad requires a non-empty popover anchor. Android and other
          // platforms ignore it, so a safe fallback is always supplied.
          sharePositionOrigin:
              _safeShareOrigin(sharePositionOrigin) ??
              const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );

      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.completed,
        document: document,
      );
    } catch (error, stackTrace) {
      state = LibraryCsvTransferState(
        phase: LibraryCsvTransferPhase.failed,
        error: error,
        errorStackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _ensureIdle() {
    if (state.isBusy) {
      throw StateError('Ya hay una transferencia CSV en curso.');
    }
  }
}

LibraryCsvTrack _trackFromLocal(
  LocalTrack track,
  int rowNumber,
  List<LibraryCsvMembership> memberships,
) {
  final videoId =
      _youtubeVideoId(track.sourceId) ?? _youtubeVideoId(track.sourceUrl);
  return LibraryCsvTrack(
    rowNumber: rowNumber,
    title: track.title,
    artist: track.artist,
    artists: track.artists,
    album: track.album,
    youtubeVideoId: videoId,
    youtubeUrl: videoId == null
        ? null
        : 'https://www.youtube.com/watch?v=$videoId',
    duration: track.duration,
    thumbnailUrl: track.thumbnailUrl ?? track.catalogThumbnailUrl,
    // Local paths and stream URLs are device-specific and may contain
    // credentials, so only the portable YouTube identity is exported.
    sourceUri: videoId == null
        ? null
        : 'https://www.youtube.com/watch?v=$videoId',
    addedAt: track.addedAt,
    memberships: List.unmodifiable(memberships),
  );
}

String? _youtubeVideoId(String? input) {
  if (input == null || input.isEmpty) return null;
  final uri = Uri.tryParse(input);
  if (uri != null) {
    if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
      if (uri.pathSegments.contains('watch')) {
        return uri.queryParameters['v'];
      }
      if (uri.pathSegments.contains('shorts')) {
        return uri.pathSegments.last;
      }
      return uri.pathSegments.last;
    }
  }
  final regex = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  if (regex.hasMatch(input)) {
    return input;
  }
  return null;
}

LibraryCsvTrack _trackFromCatalogEntry(
  PlaylistEntry entry,
  int rowNumber,
  LibraryCsvMembership membership,
) {
  final track = entry.track;
  final videoId = entry.videoId ?? track.youtubeVideoId;
  final artists = track.artists
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList(growable: false);
  return LibraryCsvTrack(
    rowNumber: rowNumber,
    title: track.title,
    artist: artists.isEmpty ? '' : artists.first,
    artists: artists,
    album: track.album,
    youtubeVideoId: videoId,
    youtubeUrl: videoId == null
        ? null
        : 'https://www.youtube.com/watch?v=$videoId',
    duration: track.duration,
    thumbnailUrl: track.thumbnailUrl,
    // Only the canonical video identity is portable. Local paths and source
    // URLs may contain credentials or device-specific locations.
    sourceUri: videoId == null
        ? null
        : 'https://www.youtube.com/watch?v=$videoId',
    addedAt: entry.createdAt,
    memberships: List.unmodifiable([membership]),
  );
}

/// Produces a conservative file name that WhatsApp and other document
/// pickers accept on every platform.
String _shareFileName(String playlistName) {
  var name = playlistName
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.toLowerCase().endsWith('.csv')) {
    name = name.substring(0, name.length - 4).trim();
  }
  if (name.isEmpty) {
    name = 'IVG Music';
  }
  if (name.length > 120) {
    name = name.substring(0, 120).trim();
  }
  return '$name.csv';
}

Rect? _safeShareOrigin(Rect? origin) {
  if (origin == null ||
      !origin.left.isFinite ||
      !origin.top.isFinite ||
      !origin.width.isFinite ||
      !origin.height.isFinite ||
      origin.width <= 0 ||
      origin.height <= 0) {
    return null;
  }
  return origin;
}

LibraryCsvGate _libraryCsvGate(Ref ref) {
  return <T>(operation) => ref
      .read(libraryOperationCoordinatorProvider)
      .runExclusive(LibraryMaintenancePhase.importingCsv, operation);
}

Future<LibraryCsvDocument> _parseLibraryCsvFile(String path) {
  return const LibraryCsvService().importFile(path);
}
