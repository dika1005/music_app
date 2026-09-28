import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton ganti spinner. Terasa cepat, tidak memblokir sentuhan.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: count,
      itemBuilder: (_, i) => const _Row(),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: 160, color: scheme.surface),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 100, color: scheme.surface),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String message;
  const EmptyView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
