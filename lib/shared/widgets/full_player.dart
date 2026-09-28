import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/core/utils/formatters.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/widgets/add_to_playlist_sheet.dart';
import 'package:music_app/shared/widgets/album_art.dart';
import 'package:music_app/shared/widgets/full_player_tabs.dart';

/// Fullscreen player: Tampilan minimalis ala Spotify, tajam & bersih tanpa blur berat.
/// Up Next, Lirik, dan Detail dijadikan tombol navigasi di bagian bawah yang membuka modal masing-masing.
class FullPlayerSheet extends StatelessWidget {
  const FullPlayerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (p, c) =>
          p.current?.id != c.current?.id ||
          p.status != c.status ||
          p.shuffle != c.shuffle ||
          p.repeat != c.repeat,
      builder: (context, state) {
        final track = state.current;
        if (track == null) {
          return const Scaffold(
            body: Center(child: Text('Pilih lagu dulu')),
          );
        }

        final cubit = context.read<PlayerCubit>();
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final playing = state.status == PlayerStatus.playing;
        final busy = state.status == PlayerStatus.buffering || state.status == PlayerStatus.loading;

        return Scaffold(
          backgroundColor: scheme.surface,
          body: _SwipeToDismiss(
            child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Responsif untuk berbagai resolusi layar
                final maxHeight = constraints.maxHeight;
                final artSize = (maxHeight * 0.42).clamp(180.0, 340.0);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),

                      // 1. TOP HEADER BAR
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surfaceContainerHigh,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.expand_more_rounded, size: 28),
                              color: scheme.onSurface,
                              tooltip: 'Tutup',
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'MEMUTAR LAGU',
                                style: text.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MelodyFlow',
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          // Tambah ke Playlist
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surfaceContainerHigh,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.playlist_add_rounded, size: 22),
                              color: scheme.onSurfaceVariant,
                              tooltip: 'Tambah ke Playlist',
                              onPressed: () => showAddToPlaylistSheet(context, track),
                            ),
                          ),
                        ],
                      ),

                      // 2. ALBUM ARTWORK BESAR & TAJAM (FULLSCREEN PROMINENT)
                      Expanded(
                        child: Center(
                          child: Hero(
                            tag: 'art-${track.id}',
                            child: Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: scheme.outlineVariant.withAlpha(120),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(50),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: AlbumArt(
                                  url: track.artworkUrl,
                                  size: artSize,
                                  radius: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 3. TRACK TITLE, ARTIST, & FAVORITE HEART
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: text.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface,
                                    letterSpacing: -0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artist,
                                  style: text.titleMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          BlocBuilder<LibraryCubit, LibraryState>(
                            builder: (_, favState) {
                              final fav = favState.isFav(track.id);
                              return IconButton(
                                iconSize: 28,
                                icon: Icon(
                                  fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                ),
                                color: fav ? scheme.tertiary : scheme.onSurfaceVariant,
                                tooltip: fav ? 'Hapus dari Favorit' : 'Sukai Lagu',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  context.read<LibraryCubit>().toggleFavorite(track);
                                },
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 4. PLAYBACK SLIDER / PROGRESS SCRUBBER (Debounced & isolated)
                      const _PlaybackSliderScrubber(),

                      const SizedBox(height: 8),

                      // 5. MAIN PLAYBACK CONTROLS (SHUFFLE, PREV, PLAY/PAUSE, NEXT, REPEAT)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Shuffle
                          IconButton(
                            iconSize: 26,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: state.shuffle ? scheme.primary : scheme.outline,
                            ),
                            tooltip: 'Acak Lagu',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              cubit.toggleShuffle();
                            },
                          ),
                          // Skip Previous
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: scheme.onSurface,
                            tooltip: 'Sebelumnya',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              cubit.previous();
                            },
                          ),
                          // Play / Pause Circle
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              cubit.toggle();
                            },
                            child: Container(
                              width: 66,
                              height: 66,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withAlpha(80),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: busy
                                    ? const SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        size: 40,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                          // Skip Next
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_next_rounded),
                            color: scheme.onSurface,
                            tooltip: 'Berikutnya',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              cubit.next();
                            },
                          ),
                          // Repeat
                          IconButton(
                            iconSize: 26,
                            icon: Icon(
                              state.repeat == 'one'
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: state.repeat != 'off' ? scheme.primary : scheme.outline,
                            ),
                            tooltip: 'Ulang Lagu',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              cubit.cycleRepeat();
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 6. BOTTOM NAVIGATION ACTION BAR (LIRIK, UP NEXT, DETAIL)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withAlpha(70),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Lirik
                            _BottomNavButton(
                              icon: Icons.lyrics_rounded,
                              label: 'Lirik',
                              onTap: () => showLyricsModal(context),
                              color: scheme.primary,
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: scheme.outlineVariant.withAlpha(80),
                            ),
                            // Up Next
                            _BottomNavButton(
                              icon: Icons.queue_music_rounded,
                              label: 'Up Next',
                              onTap: () => showUpNextModal(context),
                              color: scheme.onSurface,
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: scheme.outlineVariant.withAlpha(80),
                            ),
                            // Detail
                            _BottomNavButton(
                              icon: Icons.info_outline_rounded,
                              label: 'Detail',
                              onTap: () => showDetailModal(context, track),
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
}

class _PlaybackSliderScrubber extends StatefulWidget {
  const _PlaybackSliderScrubber();

  @override
  State<_PlaybackSliderScrubber> createState() => _PlaybackSliderScrubberState();
}

class _PlaybackSliderScrubberState extends State<_PlaybackSliderScrubber> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PlayerCubit>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ValueListenableBuilder<PositionData>(
      valueListenable: cubit.positionNotifier,
      builder: (context, posData, _) {
        final currentProgress = _dragValue ?? posData.progress;
        final displayPos = _dragValue != null
            ? posData.duration * _dragValue!
            : posData.position;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.surfaceContainerHighest,
                thumbColor: scheme.primary,
              ),
              child: Slider(
                value: currentProgress.clamp(0.0, 1.0),
                onChangeStart: (v) {
                  setState(() => _dragValue = v);
                },
                onChanged: (v) {
                  setState(() => _dragValue = v);
                },
                onChangeEnd: (v) {
                  final target = posData.duration * v;
                  cubit.seek(target);
                  setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(displayPos),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatDuration(posData.duration),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _BottomNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Item 3.3: swipe-down menutup full player dan MENGIKUTI jari (follow-finger).
///
/// Sebelumnya sheet hanya bereaksi setelah jari dilepas (velocity > 300) sehingga
/// terasa "lepas dari tangan". Sekarang konten ikut tergeser + meredup saat ditarik,
/// lalu memantul kembali (220ms) bila dilepas sebelum ambang 25% tinggi layar.
class _SwipeToDismiss extends StatefulWidget {
  final Widget child;
  const _SwipeToDismiss({required this.child});

  @override
  State<_SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<_SwipeToDismiss> {
  double _offset = 0;
  Duration _snapDuration = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final progress = (_offset / (height * 0.4)).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        final delta = d.delta.dy;
        setState(() {
          // Resistensi ringan saat menarik ke atas supaya tidak terasa "kaku".
          _offset = (_offset + (delta < 0 ? delta * 0.25 : delta)).clamp(0.0, height);
          _snapDuration = Duration.zero;
        });
      },
      onVerticalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (_offset > height * 0.25 || velocity > 700) {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
          return;
        }
        setState(() {
          _offset = 0;
          _snapDuration = const Duration(milliseconds: 220);
        });
      },
      child: AnimatedContainer(
        duration: _snapDuration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _offset, 0),
        child: Opacity(opacity: 1 - progress * 0.4, child: widget.child),
      ),
    );
  }
}
