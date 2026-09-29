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
  int nextCalls = 0;
  int previousCalls = 0;
  int reshuffleCalls = 0;
  bool? lastShuffleSet;

  /// Meniru `hasNext` engine (urutan acak + mode ulang).
  bool hasNextResult = true;

  @override
  bool get hasNext => hasNextResult;

  List<int> _shuffleOrder = const [];

  @override
  List<int> get shuffleOrder => _shuffleOrder;

  @override
  void setShuffle(bool enabled) => lastShuffleSet = enabled;

  @override
  Future<void> reshuffle() async {
    reshuffleCalls++;
  }

  @override
  Future<void> next() async {
    nextCalls++;
  }

  @override
  Future<void> previous() async {
    previousCalls++;
  }

  /// Meniru `shuffleIndicesStream` engine: PlayerCubit mengikuti urutan acak
  /// baru lewat callback ini.
  void emitShuffleOrder(List<int> order) {
    _shuffleOrder = order;
    onShuffleOrderChanged?.call(order);
  }

  /// Set urutan acak engine TANPA memancarkan callback — untuk menguji jalur
  /// sinkronisasi eksplisit cubit setelah playlist dimuat.
  void seedShuffleOrder(List<int> order) => _shuffleOrder = order;

  @override
  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= sources.length) return;
    sources.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex -= 1;
    } else if (index == _currentIndex) {
      _currentIndex = sources.isEmpty ? 0 : _currentIndex.clamp(0, sources.length - 1);
    }
  }

  @override
  Future<void> moveTrack(int currentIndex, int newIndex) async {
    if (currentIndex < 0 || currentIndex >= sources.length) return;
    if (newIndex < 0 || newIndex >= sources.length) return;
    final moved = sources.removeAt(currentIndex);
    sources.insert(newIndex, moved);
  }

  @override
  Future<void> insertTrack(int index, Track track) async {
    sources.insert(index.clamp(0, sources.length), track);
  }

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

  group('urutan acak engine vs daftar UI', () {
    test('next saat acak aktif mengikuti engine, bukan lompatan posisi', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(4, (i) => _track('$i', 'Song $i'));
      cubit.emit(cubit.state.copyWith(queue: tracks, index: 0, shuffle: true));
      audio.seed(tracks);

      await cubit.next();

      expect(audio.nextCalls, 1,
          reason: 'urutan acak dipegang engine; cubit tidak boleh melompat ke index+1');
      expect(audio.skipToCalls, 0);
    });

    test('previous saat acak aktif mengikuti engine', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(4, (i) => _track('$i', 'Song $i'));
      cubit.emit(cubit.state.copyWith(queue: tracks, index: 2, shuffle: true));
      audio.seed(tracks);

      await cubit.previous();

      expect(audio.previousCalls, 1);
      expect(audio.skipToCalls, 0);
    });

    test('next tanpa acak tetap memakai lompatan posisi', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(3, (i) => _track('$i', 'Song $i'));
      cubit.emit(cubit.state.copyWith(queue: tracks, index: 0, shuffle: false));
      audio.seed(tracks);

      await cubit.next();

      expect(audio.nextCalls, 0);
      expect(audio.skipToCalls, 1);
      expect(cubit.state.index, 1);
    });

    test('saat acak aktif, next tidak lompat ke rekomendasi selama urutan acak belum habis',
        () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(3, (i) => _track('$i', 'Song $i'));
      final rec = _track('rec', 'Rekomendasi');
      // index 2 = posisi terakhir, tapi itu urutan POSISI — di urutan acak
      // engine masih punya sisa lagu.
      cubit.emit(cubit.state.copyWith(
        queue: tracks,
        index: 2,
        shuffle: true,
        upNext: [rec],
      ));
      audio.seed(tracks);
      audio.hasNextResult = true;

      await cubit.next();

      expect(audio.nextCalls, 1, reason: 'engine masih punya sisa urutan acak');
      expect(audio.addTrackCalls, 0);
      expect(cubit.state.queue.length, 3,
          reason: 'rekomendasi belum boleh disisipkan selama urutan acak belum habis');
    });

    test('saat acak aktif di akhir urutan acak, next melanjutkan ke rekomendasi', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(3, (i) => _track('$i', 'Song $i'));
      final rec = _track('rec', 'Rekomendasi');
      cubit.emit(cubit.state.copyWith(
        queue: tracks,
        index: 2,
        shuffle: true,
        upNext: [rec],
      ));
      audio.seed(tracks);
      audio.hasNextResult = false;

      await cubit.next();

      expect(audio.nextCalls, 0);
      expect(audio.addTrackCalls, 1);
      expect(cubit.state.queue.map((t) => t.id).toList(), ['0', '1', '2', 'rec']);
    });

    test('urutan acak engine tersimpan di state tanpa emit berulang', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final emissions = <PlayerState>[];
      final sub = cubit.stream.listen(emissions.add);
      addTearDown(sub.cancel);

      audio.emitShuffleOrder([2, 0, 1]);
      audio.emitShuffleOrder([2, 0, 1]); // nilai sama → harus diabaikan
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(cubit.state.shuffleOrder, [2, 0, 1]);
      expect(emissions.length, 1,
          reason: 'urutan yang sama tidak boleh memicu rebuild UI');
    });
    test('playQueue menyinkronkan urutan acak engine ke state', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(3, (i) => _track('$i', 'Song $i'));
      // Urutan diset tanpa callback supaya yang menguji hanya jalur sinkron
      // eksplisit di playQueue.
      audio.seedShuffleOrder([1, 2, 0]);

      await cubit.playQueue(tracks, 0);

      expect(cubit.state.shuffleOrder, [1, 2, 0]);
    });

    test('playRecommendationNow memutar lagu yang disisipkan walau acak aktif', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final t1 = _track('1', 'Song 1');
      final t2 = _track('2', 'Song 2');
      final rec = _track('rec', 'Rekomendasi');
      cubit.emit(cubit.state.copyWith(
        queue: [t1, t2],
        index: 0,
        shuffle: true,
        upNext: [rec],
      ));
      audio.seed([t1, t2]);

      await cubit.playRecommendationNow(rec);

      expect(cubit.state.current?.id, 'rec',
          reason: 'harus memutar lagu yang baru disisipkan, bukan urutan acak');
      expect(audio.nextCalls, 0);
      expect(audio.skipToCalls, 1);
    });

    test('toggleShuffle mengacak ulang dan meneruskan urutan baru ke state', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(3, (i) => _track('$i', 'Song $i'));
      cubit.emit(cubit.state.copyWith(queue: tracks, index: 0));
      audio.seed(tracks);
      audio.emitShuffleOrder([2, 1, 0]);

      cubit.toggleShuffle();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.shuffle, isTrue);
      expect(audio.lastShuffleSet, isTrue);
      expect(audio.reshuffleCalls, 1,
          reason: 'urutan acak harus dibuat ulang tiap kali Acak dinyalakan');
      expect(cubit.state.shuffleOrder, [2, 1, 0]);

      cubit.toggleShuffle();

      expect(cubit.state.shuffle, isFalse);
      expect(audio.lastShuffleSet, isFalse);
      expect(cubit.state.shuffleOrder, isEmpty,
          reason: 'saat acak nonaktif UI kembali ke urutan posisi');
    });

    test('menghapus lagu saat acak aktif memakai indeks playlist yang benar', () async {
      final audio = _FakeAudio();
      final cubit = PlayerCubit(audio, _FakeRepo());
      addTearDown(cubit.close);

      final tracks = List.generate(4, (i) => _track('$i', 'Song $i'));
      cubit.emit(cubit.state.copyWith(queue: tracks, index: 0, shuffle: true));
      audio.seed(tracks);
      // Urutan putar 2,0,3,1 → lagu "berikutnya" yang tampil adalah playlist
      // index 3, bukan index 1. UI harus menghapus lagu yang benar-benar tampil.
      audio.emitShuffleOrder([2, 0, 3, 1]);

      await cubit.removeFromQueue(3);

      expect(cubit.state.queue.map((t) => t.id).toList(), ['0', '1', '2']);
      expect(audio.sources.map((t) => t.id).toList(), ['0', '1', '2']);
      expect(cubit.state.index, 0);
      expect(cubit.state.current?.id, '0');
    });
  });
}
