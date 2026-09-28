import 'package:get_it/get_it.dart';
import 'package:music_app/features/auth/data/profile_service.dart';
import 'package:music_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:music_app/features/player/data/repositories/track_repository_impl.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

final sl = GetIt.instance;

Future<void> initInjection() async {
  // Plugin tunggal YouTube Music
  sl.registerLazySingleton(() => YtFlutterMusicapi());

  // Audio handler untuk background playback & notification controls
  sl.registerSingleton<AppAudioHandler>(AppAudioHandler());
  try {
    await sl<AppAudioHandler>().init();
  } catch (_) {
    // Non-Android / testing mode
  }

  // Data Source & Repository murni yt_flutter_musicapi
  sl.registerLazySingleton(() => YtMusicDataSource(sl()));
  sl.registerLazySingleton<TrackRepository>(() => TrackRepositoryImpl(sl()));

  // Use cases
  sl.registerLazySingleton(() => GetTrendingTracks(sl()));
  sl.registerLazySingleton(() => SearchTracks(sl()));
  sl.registerLazySingleton(() => GetRelatedTracks(sl()));
  sl.registerLazySingleton(() => GetLyrics(sl()));

  // Profile cubit
  final profileCubit = ProfileCubit();
  sl.registerSingleton(profileCubit);

  // BLoC / Cubit
  final playerCubit = PlayerCubit(sl(), sl());
  final libraryCubit = LibraryCubit();
  final homeCubit = HomeCubit(sl(), sl());
  playerCubit.onTrackPlayed = (track) => libraryCubit.pushRecent(track);

  sl.registerSingleton(playerCubit);
  sl.registerSingleton(homeCubit);
  sl.registerLazySingleton(() => SearchCubit(sl()));
  sl.registerSingleton(libraryCubit);

  // Muat data lokal library (favorit, riwayat, dsb)
  try {
    await sl<LibraryCubit>().restore();
  } catch (_) {
    // Abaikan jika storage belum siap
  }

  // Muat profil pengguna
  try {
    await sl<ProfileCubit>().restore();
  } catch (_) {}
}
