import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Gambar album: cache disk agresif, fade 200ms, fallback ikon.
/// Prinsip Emil: masuk dari nyata (scale 1 + fade), bukan scale 0.
///
/// Item 2.4: placeholder sekarang shimmer (bukan kotak abu statis) supaya
/// loading terasa hidup, tapi tetap 1 layer gradient per gambar.
class AlbumArt extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final bool shimmerPlaceholder;
  const AlbumArt({
    super.key,
    this.url,
    this.size = 56,
    this.radius = 12,
    this.shimmerPlaceholder = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (url == null || url!.isEmpty) {
      return _fallback(scheme);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: size.ceil() * 2,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => shimmerPlaceholder
            ? RepaintBoundary(child: _shimmer(scheme))
            : _static(scheme),
        errorWidget: (_, _, _) => _fallback(scheme),
      ),
    );
  }

  Widget _shimmer(ColorScheme scheme) => Shimmer.fromColors(
        baseColor: scheme.surfaceContainerHigh,
        highlightColor: scheme.surfaceContainerHighest,
        period: const Duration(milliseconds: 1200),
        child: Container(width: size, height: size, color: scheme.surfaceContainerHigh),
      );

  Widget _static(ColorScheme scheme) =>
      Container(width: size, height: size, color: scheme.surfaceContainerHighest);

  Widget _fallback(ColorScheme scheme) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(Icons.music_note, color: scheme.onSurfaceVariant, size: size * 0.45),
      );
}
