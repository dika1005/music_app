// Regresi untuk audit performa/UX MelodyFlow:
// - 4.1 PlayerState bebas dari posisi/durasi (tidak memicu rebuild per tick)
// - 4.3 isFav O(1) + 4.4 memoization getter turunan LibraryState
// - 5.4 degradasi anggun Home + banner offline
// - 5.3 cache lirik persisten (disk) di YtMusicDataSource
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/home/presentation/bloc/home_cubit.dart';
import 'package:music_app/features/home/presentation/bloc/home_state.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/widgets/connectivity_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

Track _t(String id, String artist, {String title = ''}) =>
    Track(id: id, title: title.isEmpty ? 'Lagu $id' : title, artist: artist);

/// Repo scripted: hasil `trending` diambil berurutan lalu yang terakhir diulang.
class _ScriptedRepo implements TrackRepository {
  _ScriptedRepo(this._trending);
  final List<Either<Failure, List<Track>>> _trending;
  int trendingCalls = 0;

  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async {
    final res = _trending[trendingCalls.clamp(0, _trending.length - 1)];
    trendingCalls++;
    return res;
  }

  @override
  Future<Either<Failure, List<Track>>> search(String query, {int limit = 20}) async =>
      const Right([]);

  @override
  Future<Either<Failure, List<Track>>> related(Track track, {int limit = 10}) async =>
      const Right([]);

  @override
  Future<Either<Failure, String>> audioUrl(String videoId) async => const Left(ServerFailure('x'));

  @override
  Future<Either<Failure, String>> lyrics({required String title, required String artist, Duration? duration}) async =>
      const Left(ServerFailure('x'));

  @override
  Future<Either<Failure, List<Track>>> artistSongs(String artist, {int limit = 25}) async =>
      const Right([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerState (item 4.1)', () {
    test('props tidak memuat posisi/durasi', () {
      const state = PlayerState(
        status: PlayerStatus.playing,
        queue: [Track(id: 'a', title: 'A', artist: 'B')],
      );
      expect(state.props.whereType<Duration>(), isEmpty);
      expect(state.props.length, 7, reason: 'status, queue, index, upNext, shuffle, repeat, message');
    });

    test('PositionData: progress 0..1 dan aman saat durasi 0', () {
      expect(PositionData.zero.progress, 0);
      expect(const PositionData(Duration(seconds: 30), Duration(minutes: 1)).progress, 0.5);
      expect(const PositionData(Duration(seconds: 99), Duration.zero).progress, 0);
      expect(const PositionData(Duration(seconds: 999), Duration(seconds: 10)).progress, 1.0);
    });
  });

  group('LibraryState (item 4.3 & 4.4)', () {
    test('isFav benar dan tidak ada cache basi setelah copyWith', () {
      final state = LibraryState(favorites: [_t('v1', 'A')]);
      expect(state.isFav('v1'), isTrue);
      expect(state.isFav('v2'), isFalse);

      final updated = state.copyWith(favorites: [_t('v2', 'A')]);
      expect(updated.isFav('v2'), isTrue);
      expect(updated.isFav('v1'), isFalse, reason: 'cache lama tidak boleh bocor ke state baru');
    });

    test('getter turunan dihitung sekali (memoized)', () {
      final state = LibraryState(
        favorites: [_t('1', 'Coldplay')],
        recents: [_t('2', 'SZA')],
        searchResults: [_t('3', 'SZA')],
        playCounts: const {'2': 5, '1': 1},
      );
      expect(identical(state.libraryPool, state.libraryPool), isTrue);
      expect(identical(state.mostPlayed, state.mostPlayed), isTrue);
      expect(identical(state.topArtists, state.topArtists), isTrue);
      expect(identical(state.libraryArtists, state.libraryArtists), isTrue);
      expect(identical(state.tastePool, state.tastePool), isTrue);

      expect(state.libraryPool.map((t) => t.id).toList(), ['1', '2']);
      expect(state.tastePool.map((t) => t.id).toList(), ['2', '3']);
      expect(state.mostPlayed.first.id, '2');
      expect(state.libraryArtists.first, 'Coldplay', reason: 'favorit berbobot 5 > riwayat 3');
    });
  });

  group('HomeCubit (item 3.1 & 5.4)', () {
    tearDown(NetworkMonitor.instance.stop);

    test('load() kedua tidak fetch ulang', () async {
      final repo = _ScriptedRepo([Right([_t('1', 'A')])]);
      final cubit = HomeCubit(GetTrendingTracks(repo), SearchTracks(repo));
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.load();

      expect(repo.trendingCalls, 1, reason: 'load() harus idempoten saat sudah loaded');
      expect(cubit.state.status, HomeStatus.loaded);
      expect(cubit.state.message, isNull);
    });

    test('gagal fetch saat sudah ada cache -> tetap loaded + catatan offline', () async {
      final repo = _ScriptedRepo([
        Right([_t('1', 'A'), _t('2', 'B')]),
        const Left(NetworkFailure()),
      ]);
      final cubit = HomeCubit(GetTrendingTracks(repo), SearchTracks(repo));
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.refresh();

      expect(cubit.state.status, HomeStatus.loaded, reason: 'jangan ganti ke layar error');
      expect(cubit.state.tracks.length, 2);
      expect(cubit.state.message, contains('Mode offline'));
    });

    test('gagal tanpa cache sama sekali -> error', () async {
      final repo = _ScriptedRepo([const Left(NetworkFailure())]);
      final cubit = HomeCubit(GetTrendingTracks(repo), SearchTracks(repo));
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, HomeStatus.error);
      expect(cubit.state.message, isNotNull);
    });
  });

  group('Banner offline (item 5.4)', () {
    testWidgets('muncul saat offline dan hilang saat online', (tester) async {
      final online = ValueNotifier<bool>(false);
      addTearDown(online.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: Column(children: [ConnectivityBanner(notifier: online)])),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Tidak ada koneksi'), findsOneWidget);

      online.value = true;
      await tester.pumpAndSettle();
      expect(find.textContaining('Tidak ada koneksi'), findsNothing);
    });

    testWidgets('StaleDataNotice menampilkan pesan cache', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: StaleDataNotice(message: 'Mode offline — menampilkan data tersimpan.'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.textContaining('data tersimpan'), findsOneWidget);
    });
  });

  group('Cache lirik disk (item 5.3)', () {
    test('lirik diambil dari cache disk tanpa menyentuh jaringan', () async {
      SharedPreferences.setMockInitialValues({
        'lyrics.cache.v1': jsonEncode({'lagu test_artis test_0': 'Baris lirik dari cache'}),
      });
      final ds = YtMusicDataSource(YtFlutterMusicapi());
      addTearDown(ds.dispose);

      expect(await ds.lyrics(title: 'Lagu Test', artist: 'Artis Test'), 'Baris lirik dari cache');
      // Akses kedua murni dari memori.
      expect(await ds.lyrics(title: 'Lagu Test', artist: 'Artis Test'), 'Baris lirik dari cache');
    });
  });
}

