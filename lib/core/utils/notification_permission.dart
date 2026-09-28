import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Meminta izin notifikasi (Android 13+ / POST_NOTIFICATIONS).
///
/// Notifikasi pemutaran dibuat oleh `just_audio_background`/`audio_service`
/// melalui foreground service. Android 13+ mengecualikan notifikasi yang terkait
/// media session dari izin ini, tapi sebagian ROM (Xiaomi/Oppo/Vivo) tetap
/// menyembunyikannya selama izin belum pernah diminta. Implementasi native-nya
/// ada di `MainActivity` supaya tidak perlu menambah paket `permission_handler`.
///
/// Aman dipanggil di platform lain maupun di test: kegagalan apa pun diabaikan
/// (paling buruk: dialog izin tidak muncul, playback tetap jalan).
Future<void> requestNotificationPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('melodyflow/permissions')
        .invokeMethod<void>('requestNotificationPermission');
  } catch (e) {
    debugPrint('requestNotificationPermission dilewati: $e');
  }
}