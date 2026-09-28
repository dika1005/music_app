// Home: blok "Terakhir Diputar" tetap ada, blok duplikat "Sering diputar" dihapus.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/auth/data/profile_service.dart';
import 'package:music_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:music_app/features/home/presentation/pages/home_page.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';

class _Repo implements TrackRepository {
  _Repo({this.trending_ = const []});
  final List<Track> trending_;

  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => Right(trending_);
  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> related(Track t, {int limit = 10}) async => const Right([]);
  @override
  Future<Either<Failure, String>> audioUrl(String id) async => const Left(ServerFailure('x'));
  @override
  Future<Either<Failure, String>> lyrics({required String title, required String artist, Duration? duration}) async =>
      const Left(ServerFailure('x'));
  @override
  Future<Either<Failure, List<Track>>> artistSongs(String a, {int limit = 25}) async => const Right([]);
}

void main() {
  setUp(() => sl.reset());
  tearDown(() => sl.reset());

  testWidgets('Home: "Terakhir Diputar" ada, "Sering diputar" sudah dihapus', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = _Repo(
      trending_: const [Track(id: 'p1', title: 'Populer Satu', artist: 'Artis P')],
    );
    sl.registerSingleton<HomeCubit>(HomeCubit(GetTrendingTracks(repo), SearchTracks(repo)));

    final lib = LibraryCubit();
    final player = PlayerCubit(AppAudioHandler(), repo);
    final profile = ProfileCubit();
    addTearDown(() async {
      await player.close();
      await lib.close();
      await profile.close();
    });
    lib.pushRecent(const Track(id: 'r1', title: 'Riwayat Satu', artist: 'Artis R'));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: lib),
          BlocProvider.value(value: player),
          BlocProvider.value(value: profile),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomePage()),
      ),
    );

    // postFrameCallback HomePage -> HomeCubit.load(), lalu state loaded rebuild.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Terakhir Diputar'), findsOneWidget);
    expect(find.text('Riwayat Satu'), findsOneWidget);
    expect(find.text('Sedang Populer'), findsOneWidget);
    expect(find.text('Populer Satu'), findsOneWidget);

    // Blok duplikat: isinya sama dengan riwayat, jadi tidak boleh kembali.
    expect(find.text('Sering diputar'), findsNothing);

    await tester.pump(const Duration(milliseconds: 350)); // flush timer persist
    NetworkMonitor.instance.stop(); // batalkan probe berkala
  });
}
