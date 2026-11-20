import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_dialog.dart';
import '../../domain/entities/playlist.dart';
import '../providers/lyrics_share_providers.dart';
import '../providers/music_providers.dart';
import 'lyrics_share_photo_cropper.dart';

enum _PlaylistArtworkMode { random, custom }

/// Edits a saved playlist's artwork without changing its songs or playback.
class PlaylistArtworkEditor extends ConsumerStatefulWidget {
  const PlaylistArtworkEditor({
    required this.playlist,
    required this.child,
    super.key,
  });

  final Playlist playlist;
  final Widget child;

  @override
  ConsumerState<PlaylistArtworkEditor> createState() =>
      _PlaylistArtworkEditorState();
}

class _PlaylistArtworkEditorState extends ConsumerState<PlaylistArtworkEditor> {
  bool _editing = false;

  Future<void> _edit() async {
    if (_editing) return;
    setState(() => _editing = true);
    final strings = ref.read(appStringsProvider);
    final playlistId = widget.playlist.id;
    // Keep the same controller even if navigation disposes this cover while
    // the system picker or its full-screen crop editor is open.
    final controller = ref.read(playlistsControllerProvider.notifier);
    final picker = ref.read(lyricsSharePhotoServiceProvider);
    try {
      final selected = await showAppDialog<_PlaylistArtworkMode>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
          key: const ValueKey('playlist-artwork-dialog'),
          title: Text(strings.playlistArtworkTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('playlist-artwork-random'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shuffle_rounded),
                title: Text(strings.playlistArtworkRandom),
                trailing: widget.playlist.customArtworkFileName == null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(
                  dialogContext,
                ).pop(_PlaylistArtworkMode.random),
              ),
              ListTile(
                key: const ValueKey('playlist-artwork-custom'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(strings.playlistArtworkCustom),
                trailing: widget.playlist.customArtworkFileName != null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(
                  dialogContext,
                ).pop(_PlaylistArtworkMode.custom),
              ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      if (selected == _PlaylistArtworkMode.random) {
        await controller.resetArtwork(playlistId);
        return;
      }
      final image = await picker.pickPhoto();
      if (image == null) return;
      try {
        if (!mounted) return;
        final crop = await showLyricsSharePhotoCropper(
          context: context,
          image: image,
          aspectRatio: 1,
        );
        if (!mounted || crop == null) return;
        await controller.setCustomArtwork(playlistId, image, crop);
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.playlistArtworkSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = ref.watch(appStringsProvider).playlistArtworkEdit;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: _editing ? null : _edit,
          borderRadius: BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
}
