// Regresi audit UX antrean:
// - Paket B: ReorderableListView harus jadi SATU-SATUNYA scrollable di sheet
//   "DAFTAR PUTAR & UP NEXT" (tidak lagi bersarang di ListView ber-
//   NeverScrollableScrollPhysics) supaya auto-scroll saat drag bekerja.
// - Paket C: saat acak aktif, daftar "BERIKUTNYA DALAM ANTREAN" menampilkan
//   urutan putar engine (shuffleOrder), bukan urutan posisi queue.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:music_app/shared/widgets/full_player_tabs.dart';

class _Repo implements TrackRepository {
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
      const Right('Lyrics');
  @override
  Future<Either<Failure, List<Track>>> artistSongs(String a, {int limit = 25}) async => const Right([]);
}

Track _track(String id) => Track(id: id, title: 'Song $id', artist: 'Artist $id');

List<Track> _queue(int n) => List.generate(n, (i) => _track('$i'));

/// `UpNextTab` hanya pembungkus `_UpNextModalSheet`; datanya dibaca dari
/// PlayerCubit, jadi parameter konstruktornya sengaja dibiarkan kosong.
Future<PlayerCubit> _pumpSheet(WidgetTester tester, PlayerState state) async {
  final cubit = PlayerCubit(AppAudioHandler(), _Repo());
  cubit.emit(state);
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: BlocProvider<PlayerCubit>.value(
          value: cubit,
          child: const UpNextTab(queue: [], index: 0, upNext: []),
        ),
      ),
    ),
  );
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Paket B: antrean memakai ReorderableListView sebagai satu-satunya scrollable',
      (tester) async {
    await _pumpSheet(
      tester,
      PlayerState(
        status: PlayerStatus.playing,
        queue: _queue(12),
        index: 0,
      ),
    );

    final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(list.physics, isNull,
        reason: 'fisika scroll default diperlukan agar list auto-scroll saat drag');
    expect(find.byType(ListView), findsNothing,
        reason: 'tidak boleh ada scrollable bersarang ber-NeverScrollableScrollPhysics');

    // Judul + tombol tutup di luar list scrollable → tetap terlihat walau
    // antrean sudah digulir jauh (dulu keduanya ikut tergulir bersama list).
    expect(find.text('DAFTAR PUTAR & UP NEXT'), findsOneWidget);
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('DAFTAR PUTAR & UP NEXT'), findsOneWidget,
        reason: 'header harus pinned, bukan ikut tergulir');
    expect(find.text('Rekomendasi Acak Genre Serupa'), findsOneWidget);
    expect(find.text('Song 11'), findsOneWidget,
        reason: 'item jauh harus tercapai setelah scroll');
  });

  testWidgets('Paket C: daftar berikutnya mengikuti urutan acak engine', (tester) async {
    await _pumpSheet(
      tester,
      PlayerState(
        status: PlayerStatus.playing,
        queue: _queue(4),
        index: 0,
        shuffle: true,
        // Urutan putar: index 1, 0(aktif), 3, 2 → setelah lagu aktif datang
        // Song 3 lalu Song 2. Song 1 sudah lewat (posisi pertama).
        shuffleOrder: [1, 0, 3, 2],
      ),
    );

    expect(find.text('URUTAN ACAK'), findsOneWidget);
    expect(find.text('Song 0'), findsOneWidget, reason: 'sedang diputar');
    expect(find.text('Song 3'), findsOneWidget);
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Song 1'), findsNothing,
        reason: 'Song 1 sudah lewat di urutan acak, bukan bagian dari "berikutnya"');
    expect(
      tester.getTopLeft(find.text('Song 3')).dy < tester.getTopLeft(find.text('Song 2')).dy,
      isTrue,
      reason: 'urutan tampil harus mengikuti urutan putar engine',
    );
    expect(find.byIcon(Icons.shuffle_rounded), findsNWidgets(2));
    expect(find.byType(ReorderableDragStartListener), findsNothing,
        reason: 'reorder urutan acak tidak didukung engine → drag dimatikan');
  });

  testWidgets('Paket C: saat acak nonaktif daftar kembali ke urutan posisi + drag handle',
      (tester) async {
    await _pumpSheet(
      tester,
      PlayerState(
        status: PlayerStatus.playing,
        queue: _queue(4),
        index: 0,
      ),
    );

    expect(find.text('URUTAN ACAK'), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(3));
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
    expect(
      tester.getTopLeft(find.text('Song 1')).dy < tester.getTopLeft(find.text('Song 2')).dy,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('Song 2')).dy < tester.getTopLeft(find.text('Song 3')).dy,
      isTrue,
    );
  });
}
