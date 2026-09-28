import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/core/constants/app_colors.dart';
import 'package:music_app/core/utils/formatters.dart';
import 'package:music_app/features/home/domain/entities/album_group.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/widgets/album_art.dart';

/// Judul seksi ala Stitch MelodyFlow: icon aksen + judul tebal + aksi opsional di kanan.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: iconColor ?? scheme.secondary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: text.labelMedium?.copyWith(
                  color: scheme.secondaryLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Putar sekumpulan lagu dari index yang dipilih.
void playFrom(BuildContext context, List<Track> tracks, int index) {
  if (tracks.isEmpty) return;
  context.read<PlayerCubit>().playQueue(tracks, index);
}

/// Blok lagu bentuk kartu ala Stitch MelodyFlow: artwork kotak + badge + neon play button + judul + artis.
class TrackGridBlock extends StatelessWidget {
  final List<Track> tracks;
  final double width;
  const TrackGridBlock({super.key, required this.tracks, this.width = 160});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: width + 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final t = tracks[i];
          return GestureDetector(
            onTap: () => playFrom(context, tracks, i),
            child: Container(
              width: width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant.withAlpha(80), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Hero(
                        tag: 'grid-art-${t.id}',
                        child: AlbumArt(url: t.artworkUrl, size: width - 16, radius: 14),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.primary,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Blok album/koleksi: kartu 2 kolom (artwork + judul). Tap = putar seisi grup.
class AlbumGridBlock extends StatelessWidget {
  final List<AlbumGroup> groups;
  const AlbumGridBlock({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < groups.length; i += 2) {
      final left = groups[i];
      final right = i + 1 < groups.length ? groups[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Expanded(child: _AlbumCard(group: left)),
          const SizedBox(width: 10),
          Expanded(child: right == null ? const SizedBox.shrink() : _AlbumCard(group: right)),
        ]),
      ));
    }
    return Column(children: [
      ...rows,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text('Album dari metadata bila tersedia, sisanya koleksi per artis.', style: text.labelSmall?.copyWith(color: scheme.outline)),
      ),
    ]);
  }
}

class _AlbumCard extends StatelessWidget {
  final AlbumGroup group;
  const _AlbumCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isLoveSongs = group.title == 'Lagu Disukai';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showAlbumTracksModal(context, group),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isLoveSongs ? const Color(0x18E11D48) : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: isLoveSongs ? Border.all(color: const Color(0x40E11D48), width: 1.2) : null,
        ),
        child: Row(children: [
          Stack(
            children: [
              if (isLoveSongs)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
                )
              else
                AlbumArt(url: group.artworkUrl, size: 52, radius: 8),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              group.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                fontWeight: isLoveSongs ? FontWeight.w800 : FontWeight.w700,
                color: isLoveSongs ? const Color(0xFFE11D48) : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(group.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ])),
          Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 20),
        ]),
      ),
    );
  }
}

/// Menampilkan Modal Sheet Detail Album / Koleksi untuk memilih lagu secara spesifik
void showAlbumTracksModal(BuildContext context, AlbumGroup group) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final isLoveSongs = group.title == 'Lagu Disukai';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withAlpha(120),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Album Header Card
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    if (isLoveSongs)
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withAlpha(80),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 36),
                      )
                    else
                      AlbumArt(url: group.artworkUrl, size: 68, radius: 14),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLoveSongs ? const Color(0x20E11D48) : scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isLoveSongs ? 'KOLEKSI LOVE SONGS' : (group.isRealAlbum ? 'ALBUM' : 'KOLEKSI ARTIS'),
                              style: text.labelSmall?.copyWith(
                                color: isLoveSongs ? const Color(0xFFE11D48) : scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.subtitle} • ${group.tracks.length} lagu',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // Putar Semua Button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        playFrom(context, group.tracks, 0);
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Putar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Tracks List
              Expanded(
                child: BlocBuilder<PlayerCubit, PlayerState>(
                  buildWhen: (p, c) => p.current?.id != c.current?.id || p.status != c.status,
                  builder: (context, playerState) {
                    final currentTrack = playerState.current;
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: group.tracks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
                      itemBuilder: (context, i) {
                        final track = group.tracks[i];
                        final isPlayingThis = currentTrack?.id == track.id;

                        return ListTile(
                          dense: true,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22,
                                child: isPlayingThis
                                    ? Icon(Icons.graphic_eq_rounded, size: 18, color: scheme.primary)
                                    : Text(
                                        '${i + 1}',
                                        textAlign: TextAlign.center,
                                        style: text.labelSmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              AlbumArt(url: track.artworkUrl, size: 40, radius: 8),
                            ],
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: isPlayingThis ? FontWeight.w800 : FontWeight.w600,
                              color: isPlayingThis ? scheme.primary : scheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${track.artist}${track.duration > Duration.zero ? " • ${formatDuration(track.duration)}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: isPlayingThis ? scheme.primary.withAlpha(200) : scheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isPlayingThis && playerState.status == PlayerStatus.playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 28,
                              color: isPlayingThis ? scheme.primary : scheme.outline,
                            ),
                            onPressed: () {
                              if (isPlayingThis) {
                                context.read<PlayerCubit>().toggle();
                              } else {
                                Navigator.pop(ctx);
                                playFrom(context, group.tracks, i);
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            playFrom(context, group.tracks, i);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Blok lingkaran artis dengan gambar profil dari artwork lagu mereka. Tap = buka pencarian lagu artis itu.
class ArtistCircleBlock extends StatelessWidget {
  final List<String> artists;
  final void Function(String artist) onTap;
  /// Map artis → artwork URL dari lagu mereka, untuk ditampilkan sebagai profil
  final Map<String, String?> artworkMap;
  const ArtistCircleBlock({
    super.key,
    required this.artists,
    required this.onTap,
    this.artworkMap = const {},
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final a = artists[i];
          final artUrl = artworkMap[a];
          return GestureDetector(
            onTap: () => onTap(a),
            child: SizedBox(
              width: 88,
              child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.secondaryContainer,
                    border: Border.all(color: scheme.outlineVariant.withAlpha(80), width: 1.5),
                  ),
                  child: ClipOval(
                    child: artUrl != null && artUrl.isNotEmpty
                        ? AlbumArt(url: artUrl, size: 80, radius: 40)
                        : Center(
                            child: Text(
                              a.isNotEmpty ? a[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(a, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: text.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Pil riwayat pencarian. Tap = ulangi pencarian.
class QueryChips extends StatelessWidget {
  final List<String> queries;
  final void Function(String query) onTap;
  const QueryChips({super.key, required this.queries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: queries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          avatar: const Icon(Icons.history_rounded, size: 16),
          label: Text(queries[i]),
          onPressed: () => onTap(queries[i]),
        ),
      ),
    );
  }
}

/// Pil genre cepat. Tap = isi pencarian.
class GenreChips extends StatelessWidget {
  final void Function(String genre) onTap;
  const GenreChips({super.key, required this.onTap});
  static const genres = ['Pop', 'Rock', 'Lo-Fi', 'Jazz', 'EDM', 'K-Pop', 'Hip-Hop', 'Acoustic'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: genres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(label: Text(genres[i]), onPressed: () => onTap(genres[i])),
      ),
    );
  }
}
