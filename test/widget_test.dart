// Smoke test: widget murni tanpa jaringan/DI.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:music_app/shared/routing/app_router.dart';
import 'package:music_app/shared/widgets/album_art.dart';
import 'package:music_app/shared/widgets/loading_states.dart';

class FakeRepo implements TrackRepository {
  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
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
  testWidgets('AppShell + NavigationBar builds', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final player = PlayerCubit(AppAudioHandler(), FakeRepo());
    final library = LibraryCubit();
    addTearDown(() async {
      await player.close();
      await library.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: player),
          BlocProvider.value(value: library),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AlbumArt), findsNothing);
  });

  testWidgets('Skeleton + AlbumArt fallback render', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SkeletonList(count: 2)),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AlbumArt(url: null, size: 56)),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });
}
