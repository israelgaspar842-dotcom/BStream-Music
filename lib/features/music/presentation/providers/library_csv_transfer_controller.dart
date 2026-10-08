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

  Future<void> shareSinglePlaylist(String playlistId, String playlistName) async {
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
            final allTracks = await repository.getLocalTracks();
            final allPlaylists = await repository.getPlaylists();

            final playlist = allPlaylists.firstWhere(
              (p) => p.id == playlistId,
              orElse: () => throw StateError('Playlist not found: $playlistId'),
            );

            final trackIdsSet = playlist.trackIds.toSet();
            final playlistTracks = allTracks
                .where((track) => trackIdsSet.contains(track.id))
                .toList(growable: false);

            final memberships = <String, List<LibraryCsvMembership>>{};
            for (var index = 0; index < playlist.trackIds.length; index++) {
              memberships
                  .putIfAbsent(playlist.trackIds[index], () => [])
                  .add(
                    LibraryCsvMembership(
                      name: playlist.name,
                      position: index + 1,
                      id: playlist.id,
                    ),
                  );
            }

            return LibraryCsvDocument(
              tracks: [
                for (var index = 0; index < playlistTracks.length; index++)
                  _trackFromLocal(
                    playlistTracks[index],
                    index + 2,
                    memberships[playlistTracks[index].id] ?? const [],
                  ),
              ],
              detectedFormat: LibraryCsvDetectedFormat.bstream,
              defaultPlaylistName: playlistName,
              hasPlaylistColumn: true,
            );
          });

      final tempDir = await getTemporaryDirectory();
      final safeName = playlistName
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File('${tempDir.path}/$safeName.csv');

      await file.writeAsBytes(
        const LibraryCsvService().exportDocument(document, LibraryCsvProfile.bstream),
        flush: true,
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Escucha mi playlist en IVG Music',
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
    sourceUri: track.sourceUrl,
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

LibraryCsvGate _libraryCsvGate(Ref ref) {
  return <T>(operation) => ref
      .read(libraryOperationCoordinatorProvider)
      .runExclusive(LibraryMaintenancePhase.importingCsv, operation);
}

Future<LibraryCsvDocument> _parseLibraryCsvFile(String path) {
  return const LibraryCsvService().importFile(path);
}
