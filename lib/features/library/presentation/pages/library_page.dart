import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:music_app/features/home/domain/entities/album_group.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/widgets/album_art.dart';
import 'package:music_app/shared/widgets/section_blocks.dart';

enum LibrarySort { newest, title, artist }

/// Library: Koleksi personal murni pengguna (Lagu Disukai, Riwayat Putar, Playlist Kamu).
/// Tampilan solid dan bersih tanpa efek glow atau blur yang memberatkan perangkat.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  LibrarySort _sort = LibrarySort.newest;

  List<Track> _applyTrackSort(List<Track> tracks) {
    final list = List<Track>.from(tracks);
    switch (_sort) {
      case LibrarySort.newest:
        return list;
      case LibrarySort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return list;
      case LibrarySort.artist:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        return list;
    }
  }

  List<UserPlaylist> _applyPlaylistSort(List<UserPlaylist> playlists) {
    final list = List<UserPlaylist>.from(playlists);
    switch (_sort) {
      case LibrarySort.newest:
        return list;
      case LibrarySort.title:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      case LibrarySort.artist:
        list.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
        return list;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Koleksi Kamu',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: scheme.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      // Tombol buat playlist baru
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.add_rounded,
                            color: scheme.primary,
                            size: 22,
                          ),
                          tooltip: 'Buat Playlist Baru',
                          onPressed: () => _showCreatePlaylistDialog(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Tombol shortir (Sorting)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
                        ),
                        child: PopupMenuButton<LibrarySort>(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.sort_rounded,
                            color: _sort != LibrarySort.newest ? scheme.primary : scheme.onSurfaceVariant,
                            size: 20,
                          ),
                          tooltip: 'Urutkan Koleksi',
                          onSelected: (val) {
                            setState(() => _sort = val);
                          },
                          itemBuilder: (ctx) => [
                            CheckedPopupMenuItem(
                              value: LibrarySort.newest,
                              checked: _sort == LibrarySort.newest,
                              child: const Text('Terbaru ditambahkan'),
                            ),
                            CheckedPopupMenuItem(
                              value: LibrarySort.title,
                              checked: _sort == LibrarySort.title,
                              child: const Text('Judul (A - Z)'),
                            ),
                            CheckedPopupMenuItem(
                              value: LibrarySort.artist,
                              checked: _sort == LibrarySort.artist,
                              child: const Text('Nama Artis (A - Z)'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: BlocBuilder<LibraryCubit, LibraryState>(
                builder: (context, state) {
                  // Koleksi harus kosong sebelum ada lagu yang diputar/disukai/dibuat playlistnya
                  if (state.favorites.isEmpty &&
                      state.recents.isEmpty &&
                      state.playlists.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.queue_music_rounded,
                                size: 32,
                                color: scheme.outline,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Koleksi masih kosong',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Putar musik atau buat playlist untuk mulai mengumpulkan koleksi lagu favoritmu.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Buat Playlist Pertama'),
                              onPressed: () => _showCreatePlaylistDialog(context),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Data murni koleksi
                  final sortedPlaylists = _applyPlaylistSort(state.playlists);
                  final sortedFavorites = _applyTrackSort(state.favorites);
                  final sortedRecents = _applyTrackSort(state.recents);

                  final pool = state.libraryPool;
                  final albums = AlbumGroup.fromTracks(pool);
                  final artists = state.libraryArtists;

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      // Custom Playlists
                      if (sortedPlaylists.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Playlist Kamu (${sortedPlaylists.length})',
                          icon: Icons.queue_music_rounded,
                          iconColor: scheme.primary,
                          action: '+ Buat baru',
                          onAction: () => _showCreatePlaylistDialog(context),
                        ),
                        ...sortedPlaylists.map((p) => _PlaylistTile(playlist: p)),
                      ],
                      // Lagu Disukai
                      if (sortedFavorites.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Lagu Disukai (${sortedFavorites.length})',
                          icon: Icons.favorite_rounded,
                          iconColor: scheme.tertiary,
                          action: 'Putar semua',
                          onAction: () => playFrom(context, sortedFavorites, 0),
                        ),
                        TrackGridBlock(tracks: sortedFavorites),
                      ],
                      // Artis dari lagu yang benar-benar pernah diputar/disukai
                      if (artists.isNotEmpty) ...[
                        const SectionHeader(title: 'Artis Favorit'),
                        Builder(
                          builder: (context) {
                            // Build artworkMap from library tracks
                            final artworkMap = <String, String?>{};
                            for (final artist in artists) {
                              for (final t in [...state.favorites, ...state.recents]) {
                                if (t.artist == artist && t.artworkUrl != null && t.artworkUrl!.isNotEmpty) {
                                  artworkMap[artist] = t.artworkUrl;
                                  break;
                                }
                              }
                            }
                            return ArtistCircleBlock(
                              artists: artists,
                              onTap: (a) => context.go('/search?q=${Uri.encodeComponent(a)}'),
                              artworkMap: artworkMap,
                            );
                          },
                        ),
                      ],
                      // Album dari koleksi
                      if (albums.isNotEmpty) ...[
                        const SectionHeader(title: 'Album & Koleksi'),
                        AlbumGridBlock(groups: albums),
                      ],
                      // Riwayat Putar
                      if (sortedRecents.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Riwayat Putar (${sortedRecents.length})',
                          icon: Icons.history_rounded,
                          action: 'Bersihkan',
                          onAction: () => _confirmClearHistory(context),
                        ),
                        TrackGridBlock(tracks: sortedRecents),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: const Text('Hapus riwayat?'),
        content: const Text('Semua lagu di riwayat putar akan dibersihkan dari koleksi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LibraryCubit>().clearHistory();
            },
            child: Text('Hapus', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: const Text('Buat Playlist Baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama playlist...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (name) {
            final trimmed = name.trim();
            if (trimmed.isNotEmpty) {
              final newPl = context.read<LibraryCubit>().createPlaylist(trimmed);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Playlist "$trimmed" berhasil dibuat')),
              );
              _showPlaylistDetail(context, newPl);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final newPl = context.read<LibraryCubit>().createPlaylist(name);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playlist "$name" berhasil dibuat')),
                );
                _showPlaylistDetail(context, newPl);
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistDetail(BuildContext context, UserPlaylist playlist) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, libState) {
            final currentPl = libState.playlists.firstWhere(
              (p) => p.id == playlist.id,
              orElse: () => playlist,
            );

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant.withAlpha(120),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
                            ),
                            child: Icon(Icons.queue_music_rounded, color: scheme.primary, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentPl.name,
                                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${currentPl.tracks.length} lagu',
                                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (currentPl.tracks.isNotEmpty)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                playFrom(context, currentPl.tracks, 0);
                              },
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text('Putar'),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded),
                            color: scheme.surfaceContainerHigh,
                            onSelected: (val) {
                              if (val == 'add') {
                                _showAddSongsToPlaylistSheet(context, currentPl);
                              } else if (val == 'rename') {
                                _showRenamePlaylistDialog(context, currentPl);
                              } else if (val == 'delete') {
                                Navigator.pop(sheetContext);
                                context.read<LibraryCubit>().deletePlaylist(currentPl.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Playlist "${currentPl.name}" dihapus')),
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'add',
                                child: Row(
                                  children: [
                                    Icon(Icons.add_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Tambah Lagu'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Ubah Nama'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, color: scheme.error, size: 18),
                                    const SizedBox(width: 8),
                                    Text('Hapus Playlist', style: TextStyle(color: scheme.error)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action button Tambah Lagu
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: scheme.outlineVariant),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: Icon(Icons.add_rounded, color: scheme.primary, size: 20),
                          label: Text('Tambah Lagu ke Playlist', style: TextStyle(color: scheme.primary)),
                          onPressed: () => _showAddSongsToPlaylistSheet(context, currentPl),
                        ),
                      ),
                    ),
                    const Divider(height: 12),
                    Expanded(
                      child: currentPl.tracks.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.music_off_rounded, size: 48, color: scheme.outline),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Playlist masih kosong',
                                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Klik tombol "Tambah Lagu ke Playlist" di atas untuk menambahkan lagu favoritmu.',
                                      textAlign: TextAlign.center,
                                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: currentPl.tracks.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 2),
                              itemBuilder: (context, i) {
                                final track = currentPl.tracks[i];
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AlbumArt(url: track.artworkUrl, size: 44, radius: 8),
                                  ),
                                  title: Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.remove_circle_outline_rounded, color: scheme.error, size: 20),
                                    tooltip: 'Hapus dari playlist',
                                    onPressed: () {
                                      context.read<LibraryCubit>().removeFromPlaylist(currentPl.id, track.id);
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    playFrom(context, currentPl.tracks, i);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, UserPlaylist playlist) {
    final ctrl = TextEditingController(text: playlist.name);
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        title: const Text('Ubah Nama Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nama baru...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                context.read<LibraryCubit>().renamePlaylist(playlist.id, newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showAddSongsToPlaylistSheet(BuildContext context, UserPlaylist playlist) {
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return _AddSongsSheet(playlist: playlist);
      },
    );
  }
}

/// Sheet untuk menambah lagu ke playlist dari favorit, riwayat, atau pencarian langsung
class _AddSongsSheet extends StatefulWidget {
  final UserPlaylist playlist;
  const _AddSongsSheet({required this.playlist});

  @override
  State<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<_AddSongsSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Track> _searchResults = [];
  bool _searching = false;

  Future<void> _performSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await sl<TrackRepository>().search(query, limit: 15);
      if (!mounted) return;
      res.fold(
        (_) => setState(() => _searching = false),
        (tracks) => setState(() {
          _searchResults = tracks;
          _searching = false;
        }),
      );
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final lib = context.watch<LibraryCubit>();
    final currentPl = lib.state.playlists.firstWhere(
      (p) => p.id == widget.playlist.id,
      orElse: () => widget.playlist,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tambah ke "${currentPl.name}"',
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pilih dari koleksi atau cari lagu baru',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Search Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari judul lagu atau artis...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _performSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: _performSearch,
              ),
            ),
            const Divider(height: 1),
            // Results list
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchCtrl.text.trim().isNotEmpty
                      ? _searchResults.isEmpty
                          ? Center(
                              child: Text(
                                'Tidak ada hasil untuk "${_searchCtrl.text}"',
                                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: _searchResults.length,
                              itemBuilder: (ctx, i) {
                                final track = _searchResults[i];
                                final inPl = currentPl.tracks.any((t) => t.id == track.id);
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AlbumArt(url: track.artworkUrl, size: 44, radius: 8),
                                  ),
                                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    icon: Icon(
                                      inPl ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                      color: inPl ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: inPl
                                        ? null
                                        : () {
                                            lib.addToPlaylist(currentPl.id, track);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Ditambahkan ke ${currentPl.name}'),
                                                duration: const Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                  ),
                                );
                              },
                            )
                      : ListView(
                          controller: scrollCtrl,
                          children: [
                            if (lib.state.favorites.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text('Dari Lagu Disukai', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              ...lib.state.favorites.map((track) {
                                final inPl = currentPl.tracks.any((t) => t.id == track.id);
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AlbumArt(url: track.artworkUrl, size: 44, radius: 8),
                                  ),
                                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    icon: Icon(
                                      inPl ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                      color: inPl ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: inPl
                                        ? null
                                        : () {
                                            lib.addToPlaylist(currentPl.id, track);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Ditambahkan ke ${currentPl.name}'),
                                                duration: const Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                  ),
                                );
                              }),
                            ],
                            if (lib.state.recents.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text('Dari Riwayat Putar', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              ...lib.state.recents.map((track) {
                                final inPl = currentPl.tracks.any((t) => t.id == track.id);
                                return ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AlbumArt(url: track.artworkUrl, size: 44, radius: 8),
                                  ),
                                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: IconButton(
                                    icon: Icon(
                                      inPl ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                      color: inPl ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                    onPressed: inPl
                                        ? null
                                        : () {
                                            lib.addToPlaylist(currentPl.id, track);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Ditambahkan ke ${currentPl.name}'),
                                                duration: const Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }
}

/// Tile playlist di library (solid tanpa gradient glow)
class _PlaylistTile extends StatelessWidget {
  final UserPlaylist playlist;
  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey('playlist-${playlist.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => context.read<LibraryCubit>().deletePlaylist(playlist.id),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
          ),
          child: Center(
            child: Icon(
              Icons.queue_music_rounded,
              color: scheme.primary,
              size: 26,
            ),
          ),
        ),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${playlist.tracks.length} lagu',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.play_arrow_rounded),
          color: scheme.primary,
          onPressed: playlist.tracks.isEmpty
              ? null
              : () => playFrom(context, playlist.tracks, 0),
        ),
        onTap: () {
          final parent = context.findAncestorStateOfType<_LibraryPageState>();
          parent?._showPlaylistDetail(context, playlist);
        },
      ),
    );
  }
}
