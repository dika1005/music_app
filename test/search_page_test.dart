// Halaman Cari versi polos: hanya riwayat + daftar hasil.
// Blok "Artis Musik" / "Album Musik Pilihan" sudah dihapus, jadi test ini juga
// menjaga supaya elemen tersebut tidak balik lagi.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:music_app/features/search/presentation/pages/search_page.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';

class _Repo implements TrackRepository {
  _Repo({this.results = const []});
  final List<Track> results;

  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => Right(results);
  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
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

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() => sl.reset());
  tearDown(() => sl.reset());
  // SearchCubit.search() memanggil NetworkMonitor.markOnline() yang menjadwalkan
  // probe berkala (20 detik). testWidgets memeriksa timer menggantung SEBELUM
  // tearDown jalan, jadi probe-nya dihentikan di akhir body test.
  tearDown(NetworkMonitor.instance.stop);

  testWidgets('polos: ada riwayat pencarian, tanpa blok artis/album pilihan', (tester) async {
    _phone(tester);
    sl.registerSingleton<SearchCubit>(SearchCubit(SearchTracks(_Repo())));

    final lib = LibraryCubit();
    addTearDown(lib.close);
    lib.pushQuery('lofi');
    lib.pushQuery('coldplay');

    await tester.pumpWidget(
      BlocProvider.value(
        value: lib,
        child: MaterialApp(theme: AppTheme.light(), home: const SearchPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350)); // flush timer persist

    expect(find.text('Cari'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Pencarian terakhir'), findsOneWidget);
    expect(find.text('coldplay'), findsOneWidget);
    expect(find.text('lofi'), findsOneWidget);

    // Elemen yang sengaja dihapus: tidak boleh muncul lagi.
    expect(find.text('Artis Musik'), findsNothing);
    expect(find.text('Album Musik Pilihan'), findsNothing);
    expect(find.text('Tulus'), findsNothing);
    expect(find.text('Fabula'), findsNothing);

    // Tombol Hapus mengosongkan riwayat dan memunculkan hint singkat.
    await tester.tap(find.text('Hapus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(lib.state.queries, isEmpty);
    expect(find.text('coldplay'), findsNothing);
    expect(find.text('Cari lagu favoritmu'), findsOneWidget);
  });

  testWidgets('menekan tombol cari menyimpan riwayat dan menampilkan hasil', (tester) async {
    _phone(tester);
    sl.registerSingleton<SearchCubit>(
      SearchCubit(
        SearchTracks(
          _Repo(results: const [Track(id: 'v1', title: 'Lagu Satu', artist: 'Artis A')]),
        ),
      ),
    );

    final lib = LibraryCubit();
    final player = PlayerCubit(AppAudioHandler(), _Repo());
    addTearDown(() async {
      await player.close();
      await lib.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: player),
          BlocProvider.value(value: lib),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SearchPage()),
      ),
    );

    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(lib.state.queries, ['lofi']);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('1 lagu'), findsOneWidget);
    expect(find.text('Lagu Satu'), findsOneWidget);
    expect(find.text('Artis A'), findsOneWidget);

    NetworkMonitor.instance.stop();
  });
}
