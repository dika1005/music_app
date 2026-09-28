import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/widgets/album_art.dart';
import 'package:music_app/shared/widgets/full_player.dart';

/// Mini player kaca di atas bottom nav ala Stitch MelodyFlow.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (p, c) => p.current?.id != c.current?.id || p.status != c.status,
      builder: (context, state) {
        final track = state.current;
        if (track == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final playing = state.status == PlayerStatus.playing || state.status == PlayerStatus.buffering;
        final busy = state.status == PlayerStatus.buffering || state.status == PlayerStatus.loading;

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 320),
                reverseTransitionDuration: const Duration(milliseconds: 250),
                pageBuilder: (_, _, _) => const FullPlayerSheet(),
                transitionsBuilder: (_, anim, _, child) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withAlpha(80), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'art-${track.id}',
                          child: AlbumArt(url: track.artworkUrl, size: 44, radius: 10),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
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
                              const SizedBox(height: 1),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Favorite button
                        BlocBuilder<LibraryCubit, LibraryState>(
                          builder: (context, lib) {
                            final isFav = lib.isFav(track.id);
                            return _Pressable(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                context.read<LibraryCubit>().toggleFavorite(track);
                              },
                              child: Icon(
                                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: isFav ? scheme.tertiary : scheme.onSurfaceVariant,
                                size: 20,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        // Solid Play/Pause Button
                        _Pressable(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.read<PlayerCubit>().toggle();
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary,
                            ),
                            child: Center(
                              child: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Next Track Button
                        _Pressable(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.read<PlayerCubit>().next();
                          },
                          child: Icon(
                            Icons.skip_next_rounded,
                            size: 26,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress indicator along the bottom edge (isolated to ValueNotifier)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<PositionData>(
                      valueListenable: context.read<PlayerCubit>().positionNotifier,
                      builder: (context, pos, _) {
                        return Container(
                          height: 2.5,
                          color: scheme.outlineVariant.withAlpha(30),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: pos.progress,
                            child: Container(
                              color: scheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pressable mikro: tekan 0.97, lepas 150ms ease-out.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  double _scale = 1;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Padding(padding: const EdgeInsets.all(8), child: widget.child),
      ),
    );
  }
}
