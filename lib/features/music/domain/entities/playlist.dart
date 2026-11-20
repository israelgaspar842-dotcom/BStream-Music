class Playlist {
  static const favoritesId = 'bstream:favorites';

  const Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    required this.updatedAt,
    this.localRevision = 0,
    this.deletedAt,
    this.customArtworkFileName,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localRevision;
  final DateTime? deletedAt;

  /// An app-owned image in the current media root's thumbnails directory.
  /// A relative name survives backups, directory moves and iOS container moves.
  final String? customArtworkFileName;

  static final _customArtworkFileNamePattern = RegExp(
    r'^playlist_[A-Za-z0-9_-]+\.(?:png|jpg|jpeg)$',
  );

  static bool isValidCustomArtworkFileName(String fileName) =>
      _customArtworkFileNamePattern.stringMatch(fileName) == fileName;

  bool get isFavorites => id == favoritesId;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? localRevision,
    Object? deletedAt = _playlistUnset,
    Object? customArtworkFileName = _playlistUnset,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      localRevision: localRevision ?? this.localRevision,
      deletedAt: identical(deletedAt, _playlistUnset)
          ? this.deletedAt
          : deletedAt as DateTime?,
      customArtworkFileName: identical(customArtworkFileName, _playlistUnset)
          ? this.customArtworkFileName
          : customArtworkFileName as String?,
    );
  }
}

const Object _playlistUnset = Object();
