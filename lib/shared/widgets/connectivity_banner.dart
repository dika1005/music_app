import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:music_app/core/utils/network_monitor.dart';

/// Banner global "Tidak ada koneksi internet" yang muncul/hilang otomatis.
///
/// Hanya me-rebuild dirinya sendiri (ValueListenableBuilder di atas
/// [NetworkMonitor.isOnline]) sehingga tidak membebani halaman di bawahnya.
/// [notifier] bisa diisi manual di test supaya tidak menyentuh singleton/global.
class ConnectivityBanner extends StatelessWidget {
  final ValueListenable<bool>? notifier;
  const ConnectivityBanner({super.key, this.notifier});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: notifier ?? NetworkMonitor.instance.isOnline,
      builder: (context, online, _) => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: online
            ? const SizedBox(width: double.infinity)
            : Material(
                color: scheme.errorContainer,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: scheme.error.withAlpha(60))),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 16, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tidak ada koneksi — memutar lagu tersimpan & mencoba ulang...',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => NetworkMonitor.instance.checkNow(),
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onErrorContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Catatan inline saat konten yang tampil berasal dari cache (data mungkin basi).
/// Dipakai Home ketika fetch gagal tapi masih ada data tersimpan.
class StaleDataNotice extends StatelessWidget {
  final String message;
  const StaleDataNotice({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
