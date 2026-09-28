import 'package:flutter/material.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:music_app/shared/widgets/full_player_tabs.dart';

/// Modal bottom sheet untuk manajemen dan pembersihan cache aplikasi
void showCacheSheet(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const CacheSheet(),
  );
}

class CacheSheet extends StatefulWidget {
  const CacheSheet({super.key});

  @override
  State<CacheSheet> createState() => _CacheSheetState();
}

class _CacheSheetState extends State<CacheSheet> {
  late int _audioCacheCount;
  late int _chartsCacheCount;

  @override
  void initState() {
    super.initState();
    _refreshCounts();
  }

  void _refreshCounts() {
    final ds = sl<YtMusicDataSource>();
    setState(() {
      _audioCacheCount = ds.cachedAudioCount;
      _chartsCacheCount = ds.cachedChartsCount;
    });
  }

  void _clearCache() {
    sl<YtMusicDataSource>().clearAllCache();
    sl<AppAudioHandler>().server.clearCache();
    clearLyricsCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _refreshCounts();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Semua cache audio, lirik & data berhasil dibersihkan!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withAlpha(120),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.cached_rounded, color: scheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hapus Cache',
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Optimalkan penyimpanan & kurangi beban',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withAlpha(60)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cache URL Streaming Audio', style: text.bodyMedium),
                      Text(
                        '$_audioCacheCount item',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cache Tangga Lagu & Data', style: text.bodyMedium),
                      Text(
                        '$_chartsCacheCount item',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'MelodyFlow menyimpan cache URL streaming, data musik, dan lirik secara otomatis untuk mempercepat pemutaran dan menghemat kuota Anda. Anda dapat mengosongkan seluruh memori cache kapan saja.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              label: const Text('Hapus Semua Cache Sekarang', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _clearCache,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
