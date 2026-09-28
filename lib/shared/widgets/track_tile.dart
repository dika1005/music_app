import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/widgets/add_to_playlist_sheet.dart';
import 'package:music_app/shared/widgets/album_art.dart';
import 'package:music_app/shared/widgets/full_player_tabs.dart';

/// Satu baris lagu. Tap = putar. Trailing: menu detail/favorit/queue/playlist.
class TrackTile extends StatelessWidget {
  final Track track;
  final List<Track> queue;
  final int queueIndex;
  const TrackTile({super.key, required this.track, required this.queue, required this.queueIndex});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (p, c) => p.current?.id != c.current?.id || p.status != c.status,
      builder: (context, player) {
        final active = player.current?.id == track.id;
        final scheme = Theme.of(context).colorScheme;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Hero(
            // Prefix 'tile-' supaya tidak bentrok dengan MiniPlayer ('art-<id>').
            tag: 'tile-art-${track.id}',
            child: AlbumArt(url: track.artworkUrl, size: 56),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(
              color: active ? scheme.primary : null,
              fontWeight: active ? FontWeight.w700 : null,
            ),
          ),
          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
          trailing: active && player.status == PlayerStatus.playing
              ? Icon(Icons.equalizer_rounded, color: scheme.primary)
              : IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _menu(context, track);
                  },
                ),
          onTap: () {
            // Item 3.4: feedback haptik saat mulai memutar lagu.
            HapticFeedback.lightImpact();
            context.read<PlayerCubit>().playQueue(queue, queueIndex);
          },
        );
      },
    );
  }

  void _menu(BuildContext context, Track track) {
    final player = context.read<PlayerCubit>();
    final libCubit = context.read<LibraryCubit>();
    final fav = libCubit.state.isFav(track.id);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AlbumArt(url: track.artworkUrl, size: 48, radius: 10),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Putar sekarang'),
              onTap: () {
                Navigator.pop(ctx);
                HapticFeedback.lightImpact();
                player.playQueue(queue, queueIndex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Putar berikutnya'),
              onTap: () {
                Navigator.pop(ctx);
                player.playUpNext(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Akan diputar berikutnya: ${track.title}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Tambah ke akhir antrean'),
              onTap: () {
                Navigator.pop(ctx);
                player.addToQueue(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ditambahkan ke akhir antrean: ${track.title}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              title: Text(fav ? 'Hapus dari favorit' : 'Simpan ke favorit'),
              onTap: () {
                Navigator.pop(ctx);
                HapticFeedback.lightImpact();
                context.read<LibraryCubit>().toggleFavorite(track);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_add_rounded, color: scheme.primary),
              title: const Text('Tambah ke playlist'),
              onTap: () {
                Navigator.pop(ctx);
                showAddToPlaylistSheet(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Detail lagu'),
              onTap: () {
                Navigator.pop(ctx);
                showDetailModal(context, track);
              },
            ),
          ],
        ),
      ),
    );
  }
}
