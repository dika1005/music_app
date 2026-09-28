import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:music_app/shared/widgets/full_player_tabs.dart';

class _FakeRepo implements TrackRepository {
  _FakeRepo(this.lyricsText);

  final String lyricsText;

  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> related(Track t, {int limit = 10}) async => const Right([]);
  @override
  Future<Either<Failure, String>> audioUrl(String id) async => Right('http://stream/$id');
  @override
  Future<Either<Failure, String>> lyrics({required String title, required String artist, Duration? duration}) async =>
      Right(lyricsText);
  @override
  Future<Either<Failure, List<Track>>> artistSongs(String a, {int limit = 25}) async => const Right([]);
}

String _lineLabel(int i) => 'Baris ${i.toString().padLeft(2, '0')}';

/// LRC sinkron sederhana: satu baris tiap 2 detik (tanpa offset).
String _plainLrc({int lines = 60}) {
  final buffer = StringBuffer();
  for (var i = 0; i < lines; i++) {
    final total = i * 2;
    final mm = (total ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    buffer.writeln('[$mm:$ss.00]${_lineLabel(i)}');
  }
  return buffer.toString();
}

Track _track() => const Track(
      id: 'v1',
      title: 'Lagu Uji',
      artist: 'Artis Uji',
      streamUrl: 'http://test/v1.mp3',
    );

Future<PlayerCubit> _pumpLyricsSheet(WidgetTester tester, String lrcText) async {
  final repo = _FakeRepo(lrcText);
  sl.registerSingleton<TrackRepository>(repo);
  sl.registerSingleton<GetLyrics>(GetLyrics(repo));
  addTearDown(sl.reset);

  final cubit = PlayerCubit(AppAudioHandler(), repo);
  addTearDown(cubit.close);
  cubit.emit(cubit.state.copyWith(
    queue: [_track()],
    index: 0,
    status: PlayerStatus.playing,
  ));

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<PlayerCubit>.value(
        value: cubit,
        child: Scaffold(
          body: LyricsTab(
            busy: false,
            lyrics: null,
            position: Duration.zero,
            onLoad: () {},
          ),
        ),
      ),
    ),
  );
  // Selesaikan fetch lirik + layout awal.
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('auto-scroll memakai geometri nyata: baris aktif tetap terlihat sampai baris akhir',
      (tester) async {
    final cubit = await _pumpLyricsSheet(tester, _plainLrc());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    // Posisi di tengah lagu → baris aktif ke-20 lewat perhitungan `t * 54.0`.
    // Dengan formula lama (54 px/baris, sementara tinggi nyata ~40 px) baris ini
    // berada ~160 px DI ATAS viewport sehingga test ini gagal.
    cubit.positionNotifier.value = const PositionData(
      Duration(seconds: 40),
      Duration(minutes: 3),
    );
    await tester.pumpAndSettle();

    final middle = tester.getRect(find.text(_lineLabel(20)));
    expect(middle.top, greaterThan(0), reason: 'baris aktif tidak boleh keluar ke atas');
    expect(middle.bottom, lessThan(screen.height), reason: 'baris aktif harus di dalam layar');

    // Posisi di baris terakhir → tetap terlihat (dulu ikut terlempar jauh ke atas).
    cubit.positionNotifier.value = const PositionData(
      Duration(seconds: 118),
      Duration(minutes: 3),
    );
    await tester.pumpAndSettle();

    final last = tester.getRect(find.text(_lineLabel(59)));
    expect(last.top, greaterThanOrEqualTo(0));
    expect(last.bottom, lessThanOrEqualTo(screen.height));
  });

  testWidgets('parser LRC: tag metadata tidak dirender, tag waktu kedua & tag kata dibersihkan',
      (tester) async {
    const lrc = '[ar: Artis Uji]\n'
        '[ti: Lagu Uji]\n'
        '[offset:-100]\n'
        '[Chorus]\n'
        '[00:01.00]Baris awal\n'
        '[00:03.00][00:05.00]Baris ulang\n'
        '<00:01.50>Baris kata\n'
        '[00:07.00]Baris akhir\n';

    await _pumpLyricsSheet(tester, lrc);

    expect(find.text('[ar: Artis Uji]'), findsNothing);
    expect(find.text('[ti: Lagu Uji]'), findsNothing);
    expect(find.text('[offset:-100]'), findsNothing);
    expect(find.textContaining('[00:'), findsNothing);

    // Header bagian tanpa timestamp tetap tampil sebagai header.
    expect(find.text('[Chorus]'), findsOneWidget);

    // Satu baris dengan dua timestamp → dua item lirik.
    expect(find.text('Baris ulang'), findsNWidgets(2));

    // Tag kata enhanced-LRC dibersihkan walau tidak ada timestamp di barisnya.
    expect(find.text('Baris kata'), findsOneWidget);
    expect(find.textContaining('<00:'), findsNothing);
  });
}