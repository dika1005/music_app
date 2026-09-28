import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';

class _FakeRepo implements TrackRepository {
  List<Track> relatedTracks = [];

  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> related(Track t, {int limit = 10}) async =>
      Right(relatedTracks);
  @override
  Future<Either<Failure, String>> audioUrl(String id) async => Right('http://stream/$id');
  @override
  Future<Either<Failure, String>> lyrics({required String title, required String artist, Duration? duration}) async =>
      const Right('Lyrics');
  @override
  Future<Either<Failure, List<Track>>> artistSongs(String a, {int limit = 25}) async => const Right([]);
}

Track _track(String id, String title) => Track(
      id: id,
      title: title,
      artist: 'Artist $id',
      streamUrl: 'http://test/$id.mp3',
    );

/// Audio handler palsu: mencatat mutasi playlist sehingga test bisa memastikan
/// antrean TIDAK dibangun ulang (`playQueue`) saat menambah/mengganti lagu.
class _FakeAudio extends AppAudioHandler {
  final List<Track> sources = [];
  int playQueueCalls = 0;
  int addTrackCalls = 0;
  int skipToCalls = 0;
  int clearQueueCalls = 0;
  int removeRangeCalls = 0;

  void seed(List<Track> tracks) {
    sources
      ..clear()
      ..addAll(tracks);
  }

  @override
  int get playlistLength => sources.length;

  @override
  Future<void> playQueue(List<Track> tracks, int start) async {
    playQueueCalls++;
    final safe = start.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    seed(tracks);
    _currentIndex = tracks.isEmpty ? -1 : safe;
  }

  @override
  Future<void> addTrack(Track track) async {
    addTrackCalls++;
    sources.add(track);
  }

  @override
  Future<void> skipTo(int index) async {
    skipToCalls++;
    _currentIndex = index;
  }

  @override
  Future<void> clearQueue() async {
    clearQueueCalls++;
    sources.clear();
    _currentIndex = -1;
  }

  @override
  Future<void> removeTrackRange(int start, int end) async {
    removeRangeCalls++;
    final s = start.clamp(0, sources.length);
    final e = end.clamp(0, sources.length);
    if (e > s) {
      sources.removeRange(s, e);
      // Engine just_audio menggeser currentIndex saat item sebelum lagu aktif
      // dihapus — tiru di sini supaya nextIndex cubit tetap valid.
      if (_currentIndex >= e) {
        _currentIndex -= (e - s);
      } else if (_currentIndex >= s) {
        _currentIndex = s;
      }
    }
  }

  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  /// Meniru `currentIndexStream` just_audio: PlayerCubit mengikuti perpindahan
  /// lagu lewat callback ini.
  void emitIndex(int index) => onIndexChanged?.call(index);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playUpNext menyisipkan track tepat setelah current index dan memfilter upNext', () async {
    final audio = AppAudioHandler();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final t2 = _track('2', 'Song 2');
    final t3 = _track('3', 'Song 3');
    final nextTrack = _track('next', 'Next Song');

    cubit.emit(cubit.state.copyWith(
      queue: [t1, t2, t3],
      index: 0,
      upNext: [nextTrack, _track('rec1', 'Rec 1')],
    ));

    await cubit.playUpNext(nextTrack);

    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', 'next', '2', '3']);
    expect(cubit.state.index, 0);
    expect(cubit.state.upNext.any((t) => t.id == 'next'), isFalse);
  });

  test('addToQueue menambahkan track ke ujung akhir antrean dan memfilter upNext', () async {
    final audio = AppAudioHandler();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final t2 = _track('2', 'Song 2');
    final endTrack = _track('end', 'End Song');

    cubit.emit(cubit.state.copyWith(
      queue: [t1, t2],
      index: 0,
      upNext: [endTrack, _track('rec1', 'Rec 1')],
    ));

    await cubit.addToQueue(endTrack);

    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', '2', 'end']);
    expect(cubit.state.index, 0);
    expect(cubit.state.upNext.any((t) => t.id == 'end'), isFalse);
  });

  test('removeFromQueue memperbarui antrean dan menyesuaikan index dengan benar', () async {
    final audio = AppAudioHandler();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final t2 = _track('2', 'Song 2');
    final t3 = _track('3', 'Song 3');
    final t4 = _track('4', 'Song 4');

    cubit.emit(cubit.state.copyWith(
      queue: [t1, t2, t3, t4],
      index: 2,
    ));

    await cubit.removeFromQueue(3);
    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', '2', '3']);
    expect(cubit.state.index, 2);

    await cubit.removeFromQueue(0);
    expect(cubit.state.queue.map((t) => t.id).toList(), ['2', '3']);
    expect(cubit.state.index, 1);
    expect(cubit.state.current?.id, '3');
  });

  test('reorderQueue memindahkan track dan menjaga track yang sedang diputar', () async {
    final audio = AppAudioHandler();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final t2 = _track('2', 'Song 2');
    final t3 = _track('3', 'Song 3');
    final t4 = _track('4', 'Song 4');

    cubit.emit(cubit.state.copyWith(
      queue: [t1, t2, t3, t4],
      index: 1,
    ));

    await cubit.reorderQueue(3, 2);
    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', '2', '4', '3']);
    expect(cubit.state.index, 1);
    expect(cubit.state.current?.id, '2');

    await cubit.reorderQueue(1, 3);
    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', '4', '3', '2']);
    expect(cubit.state.index, 3);
    expect(cubit.state.current?.id, '2');
  });

  test('loadRelated tidak memasukkan lagu yang sudah berada di dalam queue', () async {
    final audio = AppAudioHandler();
    final repo = _FakeRepo();
    final t1 = _track('1', 'Song 1');
    final t2 = _track('2', 'Song 2');
    final rec = _track('rec1', 'Rec 1');

    repo.relatedTracks = [t1, t2, rec];

    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    cubit.emit(cubit.state.copyWith(
      queue: [t1, t2],
      index: 1,
      upNext: [],
    ));

    audio.onIndexChanged?.call(0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state.upNext.any((t) => t.id == '1'), isFalse);
    expect(cubit.state.upNext.any((t) => t.id == '2'), isFalse);
    expect(cubit.state.upNext.any((t) => t.id == 'rec1'), isTrue);
  });

  test('next di ujung antrean menambah lagu ke engine tanpa rebuild playlist', () async {
    final audio = _FakeAudio();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final rec = _track('rec', 'Rekomendasi 1');

    cubit.emit(cubit.state.copyWith(queue: [t1], index: 0, upNext: [rec]));
    audio.seed([t1]);

    await cubit.next();

    // Lagu rekomendasi masuk ke antrean UI...
    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', 'rec']);
    expect(cubit.state.upNext.any((t) => t.id == 'rec'), isFalse);
    // ...dan ke playlist engine lewat addAudioSource + skipTo (bukan setAudioSources).
    expect(audio.addTrackCalls, 1);
    expect(audio.skipToCalls, 1);
    expect(audio.currentIndex, 1);
    expect(audio.playQueueCalls, 0,
        reason: 'playQueue membangun ulang playlist ExoPlayer → audio putus & media session reset');
  });

  test('indeks state mengikuti currentIndexStream setelah lagu rekomendasi diputar', () async {
    final audio = _FakeAudio();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final rec = _track('rec', 'Rekomendasi 1');
    cubit.emit(cubit.state.copyWith(queue: [t1], index: 0, upNext: [rec]));
    audio.seed([t1]);

    await cubit.next();
    audio.emitIndex(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(cubit.state.index, 1);
    expect(cubit.state.current?.id, 'rec');
  });

  test('menghapus lagu terakhir juga mengosongkan playlist engine', () async {
    final audio = _FakeAudio();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    cubit.emit(cubit.state.copyWith(queue: [t1], index: 0));
    audio.seed([t1]);

    await cubit.removeFromQueue(0);

    expect(cubit.state.queue, isEmpty);
    expect(cubit.state.status, PlayerStatus.initial);
    expect(audio.clearQueueCalls, 1,
        reason: 'hanya pause membuat ExoPlayer masih menyimpan lagu yang sudah dihapus');
    expect(audio.sources, isEmpty);
  });

  test('auto-lanjut memangkas riwayat lama agar antrean tidak tumbuh tanpa batas', () async {
    final audio = _FakeAudio();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    // Antrean 25 lagu, posisi di lagu terakhir → next() memicu auto-lanjut.
    final tracks = List.generate(25, (i) => _track('$i', 'Song $i'));
    final rec = _track('rec', 'Rekomendasi baru');
    cubit.emit(cubit.state.copyWith(queue: tracks, index: 24, upNext: [rec]));
    audio.seed(tracks);
    audio._currentIndex = 24;

    await cubit.next();

    // Riwayat: 24 - 20 = 4 lagu paling lama dibuang dari depan.
    expect(audio.removeRangeCalls, 1);
    expect(cubit.state.queue.length, 22);
    expect(cubit.state.queue.first.id, '4');
    expect(cubit.state.index, 20,
        reason: 'index harus digeser turun sejumlah lagu yang dibuang');
    expect(audio.sources.length, 22);
    expect(audio.currentIndex, 21);
    expect(audio.sources[audio.currentIndex].id, 'rec');

    // Engine melaporkan posisi baru → state mengikuti.
    audio.emitIndex(21);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cubit.state.index, 21);
    expect(cubit.state.current?.id, 'rec');
  });

  test('tidak ada lagu yang dibuang saat riwayat masih pendek', () async {
    final audio = _FakeAudio();
    final repo = _FakeRepo();
    final cubit = PlayerCubit(audio, repo);
    addTearDown(cubit.close);

    final t1 = _track('1', 'Song 1');
    final rec = _track('rec', 'Rekomendasi 1');
    cubit.emit(cubit.state.copyWith(queue: [t1], index: 0, upNext: [rec]));
    audio.seed([t1]);

    await cubit.next();

    expect(audio.removeRangeCalls, 0);
    expect(cubit.state.queue.map((t) => t.id).toList(), ['1', 'rec']);
    // Index menjadi 1 setelah engine melaporkan perpindahan (seperti produksi
    // lewat currentIndexStream).
    audio.emitIndex(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cubit.state.index, 1);
    expect(cubit.state.current?.id, 'rec');
  });
}
