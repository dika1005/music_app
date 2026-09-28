import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/core/utils/notification_permission.dart';
import 'package:music_app/features/auth/data/profile_service.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.melodyflow.audio',
    androidNotificationChannelName: 'MelodyFlow playback',
    // Ikon monokrom khusus notifikasi. "mipmap/ic_launcher" (default) dirender
    // sebagai siluet kotak di Android 13+ karena bukan ikon status bar.
    androidNotificationIcon: 'drawable/ic_stat_music',
    androidNotificationOngoing: true,
    // Jangan turunkan priority service saat pause. Dengan `true` (default
    // audio_service), notifikasi dilepas dari status foreground setiap kali
    // playback di-pause — dan aplikasi ini mem-pause lagu di hampir setiap
    // perpindahan lagu (lihat AppAudioHandler.stopImmediately) sehingga
    // notifikasi pemutaran mudah hilang/dibuang sistem.
    androidStopForegroundOnPause: false,
    androidShowNotificationBadge: true,
    notificationColor: const Color(0xFF14B8A6),
  );
  // Android 13+ (POST_NOTIFICATIONS): notifikasi pemutaran dibuat lewat foreground
  // service, tapi sebagian ROM tetap memblokirnya bila izin belum pernah diminta.
  await requestNotificationPermission();
  await initInjection();
  // Item 5.4: mulai probe konektivitas (banner offline + degradasi anggun).
  NetworkMonitor.instance.start();
  runApp(const MelodyFlowApp());
}

/// Root: dark-only M3 theme + GoRouter + cubits global (player, library, profile).
class MelodyFlowApp extends StatelessWidget {
  const MelodyFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<PlayerCubit>()),
        BlocProvider.value(value: sl<LibraryCubit>()),
        BlocProvider.value(value: sl<ProfileCubit>()),
      ],
      child: MaterialApp.router(
        title: 'MelodyFlow',
        debugShowCheckedModeBanner: false,
        // Item 6.2: app ini dark-only — satu tema saja, tanpa darkTheme/themeMode
        // ganda yang membuat `AppTheme.light()` tidak pernah benar-benar dipakai.
        theme: AppTheme.dark(),
        routerConfig: appRouter,
      ),
    );
  }
}
