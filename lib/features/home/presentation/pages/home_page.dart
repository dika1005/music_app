import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:music_app/features/home/domain/entities/album_group.dart';
import 'package:music_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:music_app/features/home/presentation/bloc/home_state.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/widgets/add_to_playlist_sheet.dart';
import 'package:music_app/shared/widgets/connectivity_banner.dart';
import 'package:music_app/shared/widgets/home_header.dart';
import 'package:music_app/shared/widgets/loading_states.dart';
import 'package:music_app/shared/widgets/section_blocks.dart';
import 'package:music_app/shared/widgets/album_art.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Item 3.1: dulu `sl<HomeCubit>()..load()` dipanggil di dalam build(),
    // sehingga setiap rebuild halaman memicu pemanggilan load() lagi.
    // Sekarang hanya sekali saat halaman pertama dibuka.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sl<HomeCubit>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: sl<HomeCubit>(), child: const _HomeView());
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  /// Item 6.4: "Lihat Semua" pada blok Sedang Populer (dulu hanya 5 baris terkunci).
  bool _showAllTrending = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, home) {
          switch (home.status) {
            case HomeStatus.initial:
                case HomeStatus.loading:
                  return const SafeArea(child: SkeletonList());
                case HomeStatus.error:
                  return SafeArea(
                    child: ErrorView(
                      message: home.message ?? 'Gagal memuat',
                      onRetry: () => context.read<HomeCubit>().load(),
                    ),
                  );
                case HomeStatus.empty:
                  return const SafeArea(child: EmptyView(message: 'Belum ada lagu.'));
                case HomeStatus.loaded:
                  return BlocBuilder<LibraryCubit, LibraryState>(
                    builder: (context, lib) {
                      // Album dan koleksi kamu: MURNI dari apa yang user setel dan sukai!
                      // Jika user belum memutar atau menyukai lagu apa pun, ini KOSONG (tanpa fallback sistem).
                      final userTracks = <Track>[];
                      final seenIds = <String>{};
                      for (final t in [...lib.favorites, ...lib.recents]) {
                        if (seenIds.add(t.id)) userTracks.add(t);
                      }
                      final albums = <AlbumGroup>[];
                      if (lib.favorites.isNotEmpty) {
                        albums.add(AlbumGroup(
                          title: 'Lagu Disukai',
                          artist: 'Koleksi Love Songs',
                          tracks: lib.favorites,
                          artworkUrl: lib.favorites.first.artworkUrl,
                          isRealAlbum: false,
                        ));
                      }
                      albums.addAll(AlbumGroup.fromTracks(userTracks));
                      final artists = lib.topArtists;

                      return RefreshIndicator(
                        onRefresh: () => context.read<HomeCubit>().refresh(),
                        child: CustomScrollView(
                          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                          slivers: [
                            const SliverToBoxAdapter(child: HomeHeader()),
                            const SliverToBoxAdapter(child: SizedBox(height: 8)),
                            // Data dari cache karena fetch gagal (item 5.4)
                            if (home.message != null)
                              SliverToBoxAdapter(child: StaleDataNotice(message: home.message!)),
                            // 1. PALING ATAS: Album & Koleksi Kamu (murni dari riwayat/favorit user)
                            if (albums.isNotEmpty)
                              ..._albums(albums),

                            // 2. KEDUA: Terakhir Diputar (murni riwayat user)
                            if (lib.recents.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                child: SectionHeader(
                                  title: 'Terakhir Diputar',
                                  icon: Icons.history_rounded,
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: TrackGridBlock(
                                  tracks: lib.recents.take(6).toList(),
                                ),
                              ),
                            ],

                            // 3. KETIGA: Sedang Populer (YouTube Music charts)
                            if (home.tracks.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: SectionHeader(
                                  title: 'Sedang Populer',
                                  icon: Icons.trending_up_rounded,
                                  iconColor: scheme.tertiary,
                                  action: _showAllTrending ? 'Lebih sedikit' : 'Lihat Semua',
                                  onAction: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _showAllTrending = !_showAllTrending);
                                  },
                                ),
                              ),
                              SliverList.builder(
                                itemCount: _showAllTrending
                                    ? home.tracks.length
                                    : (home.tracks.length > 5 ? 5 : home.tracks.length),
                                itemBuilder: (context, i) {
                                  final track = home.tracks[i];
                                  final rank = (i + 1).toString().padLeft(2, '0');
                                  return _RankedTrackTile(
                                    rank: rank,
                                    track: track,
                                    isTop: i == 0,
                                    queue: home.tracks,
                                    queueIndex: i,
                                  );
                                },
                              ),
                            ],

                            // Catatan: blok "Sering diputar" dihapus karena isinya
                            // sama dengan "Terakhir Diputar" (hanya beda urutan).
                            if (artists.isNotEmpty) ..._artists(context, artists, lib),
                            if (lib.queries.isNotEmpty) ...[
                              const SliverToBoxAdapter(child: SectionHeader(title: 'Pencarian terakhir')),
                              SliverToBoxAdapter(
                                child: QueryChips(queries: lib.queries, onTap: (q) => _openSearch(context, q)),
                              ),
                            ],
                            const SliverToBoxAdapter(child: SectionHeader(title: 'Jelajahi genre')),
                            SliverToBoxAdapter(child: GenreChips(onTap: (g) => _openSearch(context, g))),
                            const SliverToBoxAdapter(child: SizedBox(height: 24)),
                          ],
                        ),
                      );
                    },
                  );
              }
            },
          ),
    );
  }



  List<Widget> _albums(List<AlbumGroup> albums) => [
        const SliverToBoxAdapter(child: SectionHeader(title: 'Album & koleksi kamu')),
        SliverToBoxAdapter(child: AlbumGridBlock(groups: albums)),
      ];

  List<Widget> _artists(BuildContext context, List<String> artists, LibraryState lib) {
    // Build artworkMap: artist name → first available artwork URL from their tracks
    final artworkMap = <String, String?>{};
    for (final artist in artists) {
      for (final t in [...lib.recents, ...lib.favorites, ...lib.searchResults]) {
        if (t.artist == artist && t.artworkUrl != null && t.artworkUrl!.isNotEmpty) {
          artworkMap[artist] = t.artworkUrl;
          break;
        }
      }
    }
    return [
      const SliverToBoxAdapter(child: SectionHeader(title: 'Artis top kamu')),
      SliverToBoxAdapter(
        child: ArtistCircleBlock(
          artists: artists,
          onTap: (a) => _openSearch(context, a),
          artworkMap: artworkMap,
        ),
      ),
    ];
  }

  void _openSearch(BuildContext context, String query) =>
      context.go('/search?q=${Uri.encodeComponent(query)}');
}



/// Ranked Track Tile for Trending / Mood lists
class _RankedTrackTile extends StatelessWidget {
  final String rank;
  final Track track;
  final bool isTop;
  final List<Track> queue;
  final int queueIndex;

  const _RankedTrackTile({
    required this.rank,
    required this.track,
    required this.isTop,
    required this.queue,
    required this.queueIndex,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () => playFrom(context, queue, queueIndex),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withAlpha(180),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x10FFFFFF)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  rank,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isTop ? scheme.primary : scheme.outline,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AlbumArt(url: track.artworkUrl, size: 48, radius: 10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              BlocBuilder<LibraryCubit, LibraryState>(
                builder: (context, lib) {
                  final isFav = lib.isFav(track.id);
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? scheme.tertiary : scheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.read<LibraryCubit>().toggleFavorite(track);
                    },
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.playlist_add_rounded, color: scheme.onSurfaceVariant, size: 22),
                tooltip: 'Tambah ke playlist',
                onPressed: () => showAddToPlaylistSheet(context, track),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                ),
                icon: Icon(Icons.play_arrow_rounded, color: scheme.primary, size: 20),
                tooltip: 'Putar lagu',
                onPressed: () => playFrom(context, queue, queueIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
