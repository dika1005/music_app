package com.example.music_app

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (dari audio_service, dipakai just_audio_background) diperlukan agar
// activity tersambung ke FlutterEngine bersama milik service audio. Kalau tetap FlutterActivity,
// pemutaran latar belakang / notifikasi media bisa tidak sinkron.
// Referensi: README audio_service -> "Custom Android activity".
class MainActivity : AudioServiceActivity() {
    private var permissionChannelRegistered = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerPermissionChannel(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cadangan bila configureFlutterEngine tidak dipanggil (engine di-cache
        // oleh audio_service): daftarkan memakai engine yang sudah aktif.
        flutterEngine?.let { registerPermissionChannel(it) }
    }

    /**
     * Channel kecil untuk izin POST_NOTIFICATIONS (Android 13+).
     *
     * Notifikasi pemutaran dibuat oleh audio_service lewat foreground service, tapi
     * sebagian ROM tetap memblokirnya sebelum izin diminta. Dipakai dari Dart
     * (lib/core/utils/notification_permission.dart) supaya tidak perlu menambah
     * paket permission_handler.
     */
    private fun registerPermissionChannel(engine: FlutterEngine) {
        if (permissionChannelRegistered) return
        permissionChannelRegistered = true
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> result.success(requestNotificationPermission())
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission(): Boolean {
        // Di bawah Android 13 izin ini tidak ada (notifikasi selalu boleh tampil).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        if (checkSelfPermission(POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return true
        requestPermissions(arrayOf(POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        return true
    }

    private companion object {
        const val CHANNEL = "melodyflow/permissions"

        // Ditulis sebagai literal agar aman di perangkat < API 33.
        const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
    }
}
