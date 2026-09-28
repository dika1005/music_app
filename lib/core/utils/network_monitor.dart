import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Monitor konektivitas ringan tanpa dependency tambahan (item 5.4).
///
/// Cara kerja:
/// - Probe TCP ke IP literal publik (tanpa DNS) sehingga tetap akurat
///   walau DNS sedang bermasalah.
/// - Saat online, cek ulang tiap 20 detik. Saat offline, coba pulih tiap 5 detik.
/// - Setiap kegagalan jaringan (timeout/socket) di app bisa memanggil
///   [markOffline] agar banner muncul instan tanpa menunggu interval probe.
///
/// Dipakai oleh [NetworkMonitor.instance]; UI cukup mendengarkan [isOnline].
class NetworkMonitor {
  NetworkMonitor._({this.probeTimeout = const Duration(seconds: 2)});

  static final NetworkMonitor instance = NetworkMonitor._();

  /// Dipakai test agar tidak menyentuh jaringan nyata.
  @visibleForTesting
  static NetworkMonitor createForTest({Duration probeTimeout = const Duration(seconds: 2)}) =>
      NetworkMonitor._(probeTimeout: probeTimeout);

  /// IP literal publik (tanpa DNS) — akurat walau resolver perangkat bermasalah.
  /// Offline baru dinyatakan kalau KEDUA target gagal, supaya jaringan korporat
  /// yang memblokir salah satu host tidak memicu banner palsu.
  final List<String> probeHosts = const ['1.1.1.1', '8.8.8.8'];
  final int probePort = 443;
  final Duration probeTimeout;

  /// Interval probe saat online vs saat offline (lebih rapat supaya cepat pulih).
  final Duration onlineInterval = const Duration(seconds: 20);
  final Duration offlineInterval = const Duration(seconds: 5);

  /// true = ada koneksi, false = offline. Mulai dari true agar UI tidak
  /// menampilkan banner sebelum probe pertama selesai.
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  Timer? _timer;
  bool _probing = false;
  bool _disposed = false;

  bool get online => isOnline.value;

  /// Mulai loop probe. Aman dipanggil berkali-kali.
  void start() {
    if (_disposed) return;
    _timer?.cancel();
    _scheduleProbe(immediate: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dipanggil app saat operasi jaringan gagal (timeout/socket) — banner
  /// langsung muncul dan probe dijadwalkan lebih rapat.
  void markOffline() {
    if (_disposed) return;
    if (isOnline.value) isOnline.value = false;
    _scheduleProbe(immediate: false);
  }

  /// Dipanggil app saat operasi jaringan sukses — banner langsung hilang.
  void markOnline() {
    if (_disposed) return;
    if (!isOnline.value) isOnline.value = true;
    _scheduleProbe(immediate: false);
  }

  /// Cek sekali (dipakai tombol "Coba lagi" / RefreshIndicator).
  Future<bool> checkNow() async {
    _timer?.cancel();
    final ok = await _probe();
    if (!_disposed) isOnline.value = ok;
    _scheduleProbe(immediate: false);
    return ok;
  }

  void _scheduleProbe({required bool immediate}) {
    _timer?.cancel();
    final delay = immediate
        ? Duration.zero
        : (isOnline.value ? onlineInterval : offlineInterval);
    _timer = Timer(delay, () async {
      final ok = await _probe();
      if (_disposed) return;
      if (isOnline.value != ok) isOnline.value = ok;
      _scheduleProbe(immediate: false);
    });
  }

  Future<bool> _probe() async {
    if (_disposed || _probing) return isOnline.value;
    _probing = true;
    try {
      for (final host in probeHosts) {
        Socket? socket;
        try {
          socket = await Socket.connect(host, probePort, timeout: probeTimeout);
          return true;
        } catch (_) {
          // Coba target berikutnya.
        } finally {
          try {
            socket?.destroy();
          } catch (_) {}
        }
      }
      return false;
    } finally {
      _probing = false;
    }
  }

  void dispose() {
    _disposed = true;
    stop();
    isOnline.dispose();
  }
}
