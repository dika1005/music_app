import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/core/utils/formatters.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';

/// Satu-satunya sumber kebenaran playback. UI hanya membaca state ini.
class PlayerCubit extends Cubit<PlayerState> {
  final AppAudioHandler audio;
  final TrackRepository repo;
  void Function(Track track)? onTrackPlayed;

  /// Notifier posisi & durasi terpisah agar UI scrubber tidak memicu full rebuild state Cubit
  final ValueNotifier<PositionData> positionNotifier =
      ValueNotifier<PositionData>(PositionData.zero);

  PositionData get positionData => positionNotifier.value;
  Duration get position => positionNotifier.value.position;
  Duration get duration => positionNotifier.value.duration;
  double get progress => positionNotifier.value.progress;

  /// Jumlah lagu berikutnya yang URL-nya di-resolve di background (item 5.2).
  static const int _preResolveAhead = 3;

  PlayerCubit(this.audio, this.repo) : super(const PlayerState()) {
    // Hubungkan server loopback ke resolver repo untuk lazy resolution URL audio
    audio.server.onResolveUrl = (videoId) async {
      final res = await repo.audioUrl(videoId);
      return res.fold(
        (f) {
          NetworkMonitor.instance.markOffline();
          debugPrint('resolveUrl gagal: ${f.message}');
          return null;
        },
        (url) {
          NetworkMonitor.instance.markOnline();
          return url;
        },
      );
    };

    audio.onPosition = (pos, dur) {
      if (isClosed) return;
      positionNotifier.value = PositionData(pos, dur);
    };

    audio.onStatus = (playing, buffering) {
      if (isClosed) return;
      final s = buffering
          ? PlayerStatus.buffering
          : playing
              ? PlayerStatus.playing
              : PlayerStatus.paused;
      emit(state.copyWith(status: s));
    };

    // Sinkronisasi perpindahan lagu dari notifikasi / bluetooth / auto-next ExoPlayer
    audio.onIndexChanged = (index) {
      if (isClosed) return;
      if (index >= 0 && index < state.queue.length && index != state.index) {
        final current = state.queue[index];
        positionNotifier.value = PositionData.zero;
        emit(state.copyWith(index: index));
        onTrackPlayed?.call(current);
        unawaited(_loadRelated(current));
        unawaited(_preResolveSurrounding(state.queue, index));
        unawaited(repo.lyrics(title: current.title, artist: current.artist, duration: current.duration));
      }
    };

    audio.onCompleted = () {
      if (isClosed) return;
      _autoNext();
    };

    // Tombol next/prev di notifikasi diproses langsung oleh audio service
    // (_PlayerAudioHandler.skipToNext/skipToPrevious, termasuk wrap-around saat
    // antrean habis); di sini kita hanya mengikuti lewat onIndexChanged di atas.
    // Sebaliknya perubahan acak/ulang dari notifikasi / panel media sistem harus
    // disambung manual supaya tombol di UI aplikasi tetap sinkron.
    audio.onShuffleChanged = (enabled) {
      if (isClosed || state.shuffle == enabled) return;
      emit(state.copyWith(shuffle: enabled));
    };
    audio.onRepeatChanged = (mode) {
      if (isClosed || state.repeat == mode) return;
      emit(state.copyWith(repeat: mode));
    };
  }

  Future<void> playQueue(List<Track> tracks, int start) async {
    if (tracks.isEmpty) return;
    final safe = start.clamp(0, tracks.length - 1);

    // 1. Matikan lagu yang sedang berputar segera tanpa menunggu network
    await audio.stopImmediately();

    // Jika antrean yang sama persis, gunakan _jumpTo
    if (identical(state.queue, tracks) || _isSameQueue(state.queue, tracks)) {
      await _jumpTo(safe);
      return;
    }

    // 2. Ganti UI langsung ke lagu baru
    positionNotifier.value = PositionData.zero;
    emit(state.copyWith(
      status: PlayerStatus.loading,
      queue: tracks,
      index: safe,
    ));

    final current = tracks[safe];
    onTrackPlayed?.call(current);
    unawaited(_loadRelated(current));
    unawaited(repo.lyrics(title: current.title, artist: current.artist, duration: current.duration));

    try {
      // Pastikan lagu yang langsung dipilih sudah memiliki URL sebelum play
      if (!current.hasStream && !audio.server.hasCachedUrl(current.id)) {
        final res = await repo.audioUrl(current.id);
        res.fold(
          (err) {
            NetworkMonitor.instance.markOffline();
            debugPrint('Initial audioUrl resolve failed: ${err.message}');
          },
          (url) => audio.server.cacheUrl(current.id, url),
        );
      }

      await audio.playQueue(tracks, safe);

      // Pre-resolve lagu berikutnya di background agar pergantian instan
      unawaited(_preResolveSurrounding(tracks, safe));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(status: PlayerStatus.error, message: '$e'));
    }
  }

  /// Pindah ke indeks tertentu di dalam antrean yang sudah dimuat.
  ///
  /// Jalur cepat dipakai bila playlist engine sudah sinkron DAN URL lagu target
  /// sudah siap (di-pre-resolve 3 lagu ke depan, atau lagu lama yang sudah
  /// diputar). Tanpa jeda `pause()` seperti versi lama, sehingga pindah lagu dari
  /// daftar antrean terasa instan dan media session/notifikasi tidak ter-reset.
  Future<void> _jumpTo(int targetIdx) async {
    if (state.queue.isEmpty) return;
    final safe = targetIdx.clamp(0, state.queue.length - 1);
    final current = state.queue[safe];
    final urlReady = current.hasStream || audio.server.hasCachedUrl(current.id);

    if (audio.playlistLength == state.queue.length && urlReady) {
      positionNotifier.value = PositionData.zero;
      emit(state.copyWith(index: safe, status: PlayerStatus.buffering));
      onTrackPlayed?.call(current);
      try {
        await audio.skipTo(safe);
        unawaited(_loadRelated(current));
        unawaited(_preResolveSurrounding(state.queue, safe));
        unawaited(repo.lyrics(title: current.title, artist: current.artist, duration: current.duration));
      } catch (e) {
        if (!isClosed) emit(state.copyWith(status: PlayerStatus.error, message: '$e'));
      }
      return;
    }

    // Jalur lambat: hentikan audio lama seketika (<1ms), ganti UI langsung, lalu putar
    await audio.stopImmediately();

    positionNotifier.value = PositionData.zero;
    emit(state.copyWith(
      index: safe,
      status: PlayerStatus.loading,
    ));

    onTrackPlayed?.call(current);
    unawaited(_loadRelated(current));

    try {
      // 3. Pastikan URL lagu target sudah siap di cache
      if (!current.hasStream && !audio.server.hasCachedUrl(current.id)) {
        final res = await repo.audioUrl(current.id);
        res.fold(
          (err) {
            NetworkMonitor.instance.markOffline();
            debugPrint('JumpTo audioUrl failed: ${err.message}');
          },
          (url) => audio.server.cacheUrl(current.id, url),
        );
      }

      // 4. Putar lagu target (jika playlist tidak sinkron, reload antrean)
      if (audio.playlistLength != state.queue.length) {
        await audio.playQueue(state.queue, safe);
      } else {
        await audio.skipTo(safe);
      }

      // 5. Pre-resolve lagu berikutnya di antrean & lirik
      unawaited(_preResolveSurrounding(state.queue, safe));
      unawaited(repo.lyrics(title: current.title, artist: current.artist, duration: current.duration));
    } catch (e) {
      if (!isClosed) emit(state.copyWith(status: PlayerStatus.error, message: '$e'));
    }
  }

  bool _isSameQueue(List<Track> a, List<Track> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// Jumlah maksimum lagu di antrean. Auto-lanjut rekomendasi menambah satu lagu
  /// setiap lagu selesai; tanpa batas, antrean bisa tumbuh ratusan item dan
  /// panel Up Next menjadi berat karena merender semua item sekaligus.
  static const int _maxQueueLength = 100;

  /// Jumlah lagu lama (sudah dilewati) yang tetap disimpan sebagai riwayat.
  static const int _keepHistoryBehind = 20;

  /// Pre-resolve 3 lagu berikutnya secara paralel di memori cache agar Next instan.
  ///
  /// Item 5.2: dulu hanya 2 lagu. Menambah satu target lagi membuat skip cepat
  /// (mis. user menekan Next dua kali dalam sekejap) tetap tanpa jeda resolve.
  Future<void> _preResolveSurrounding(List<Track> queue, int currentIndex) async {
    if (queue.isEmpty) return;
    final targets = <int>{};
    for (var step = 1; step <= _preResolveAhead; step++) {
      var idx = currentIndex + step;
      if (idx >= queue.length) {
        // Tanpa repeat 'all' lagu pertama tidak akan diputar setelah lagu
        // terakhir, jadi jangan buang bandwidth untuk me-resolve-nya.
        if (state.repeat != 'all') break;
        idx -= queue.length;
      }
      if (idx == currentIndex) continue;
      targets.add(idx);
    }

    await Future.wait(
      targets.map((idx) async {
        if (idx < 0 || idx >= queue.length) return;
        final t = queue[idx];
        if (t.hasStream || audio.server.hasCachedUrl(t.id)) return;

        final res = await repo.audioUrl(t.id);
        if (isClosed) return;
        res.fold(
          (_) => null,
          (url) => audio.server.cacheUrl(t.id, url),
        );
      }),
    );
  }

  Future<void> toggle() => audio.toggle();

  Future<void> next() async {
    if (state.queue.isEmpty) return;

    // Jika antrean utama habis dan ada lagu berikutnya dari rekomendasi upNext
    if (state.index >= state.queue.length - 1 && state.upNext.isNotEmpty) {
      await _appendAndPlayNext(state.upNext.first);
      return;
    }

    // Jika shuffle aktif, biarkan audio handler melompat sesuai shuffle sequence ExoPlayer
    if (state.shuffle && audio.hasNext) {
      await audio.next();
      return;
    }

    if (state.index < state.queue.length - 1) {
      await _jumpTo(state.index + 1);
    } else if (state.repeat == 'all') {
      await _jumpTo(0);
    }
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (state.shuffle && audio.hasPrevious) {
      await audio.previous();
      return;
    }

    if (state.index > 0) {
      await _jumpTo(state.index - 1);
    } else if (state.repeat == 'all') {
      await _jumpTo(state.queue.length - 1);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration pos) async {
    positionNotifier.value = PositionData(pos, positionNotifier.value.duration);
    await audio.seek(pos);
  }

  void toggleShuffle() {
    final newShuffle = !state.shuffle;
    emit(state.copyWith(shuffle: newShuffle));
    audio.setShuffle(newShuffle);
  }

  void cycleRepeat() {
    const order = ['off', 'all', 'one'];
    final nextMode = order[(order.indexOf(state.repeat) + 1) % order.length];
    emit(state.copyWith(repeat: nextMode));
    audio.setRepeat(nextMode);
  }

  Future<void> _loadRelated(Track track) async {
    final res = await repo.related(track, limit: 15);
    if (isClosed) return;
    res.fold(
      (_) => null,
      (list) {
        final currentTitle = track.title.toLowerCase();
        final queueIds = state.queue.map((t) => t.id).toSet();

        // 1. Filter out same id, tracks already in queue, & songs with identical or very similar title
        final filtered = list.where((t) {
          if (t.id == track.id || queueIds.contains(t.id)) return false;
          final tTitle = t.title.toLowerCase();
          if (tTitle == currentTitle) return false;
          if (isSimilarTitle(t.title, track.title)) return false;
          return true;
        }).toList();

        // 2. Randomize / shuffle based on same genre/mood
        filtered.shuffle(Random());

        if (filtered.isNotEmpty) emit(state.copyWith(upNext: filtered));
      },
    );
  }

  Future<void> playUpNext(Track track) async {
    if (state.queue.isEmpty) {
      await playQueue([track], 0);
      return;
    }
    final insertIdx = (state.index + 1).clamp(0, state.queue.length);
    final q = List<Track>.from(state.queue)..insert(insertIdx, track);
    final updatedUpNext = state.upNext.where((t) => t.id != track.id).toList();
    emit(state.copyWith(queue: q, upNext: updatedUpNext));

    // Sinkronkan ke playlist ExoPlayer secara dinamis
    await audio.insertTrack(insertIdx, track);

    // Pre-resolve URL audio & lirik di background
    if (!track.hasStream && !audio.server.hasCachedUrl(track.id)) {
      unawaited(
        repo.audioUrl(track.id).then((res) {
          res.fold((_) => null, (url) => audio.server.cacheUrl(track.id, url));
        }),
      );
    }
    unawaited(repo.lyrics(title: track.title, artist: track.artist, duration: track.duration));
    await _ensureEngineMatchesQueue();
  }

  Future<void> addToQueue(Track track) async {
    if (state.queue.isEmpty) {
      await playQueue([track], 0);
      return;
    }
    final q = List<Track>.from(state.queue)..add(track);
    final updatedUpNext = state.upNext.where((t) => t.id != track.id).toList();
    emit(state.copyWith(queue: q, upNext: updatedUpNext));

    // Sinkronkan ke playlist ExoPlayer secara dinamis
    await audio.addTrack(track);

    // Pre-resolve URL audio & lirik di background
    if (!track.hasStream && !audio.server.hasCachedUrl(track.id)) {
      unawaited(
        repo.audioUrl(track.id).then((res) {
          res.fold((_) => null, (url) => audio.server.cacheUrl(track.id, url));
        }),
      );
    }
    unawaited(repo.lyrics(title: track.title, artist: track.artist, duration: track.duration));
    await _ensureEngineMatchesQueue();
  }

  /// Hapus track dari antrean berdasarkan indeks
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    // Jika antrean hanya 1 dan dihapus, matikan pemutaran dan kosongkan juga
    // playlist engine. Kalau hanya pause, ExoPlayer masih memegang lagu terakhir
    // sehingga notifikasi/lockscreen masih bisa memutar lagu yang sudah dihapus
    // dari UI.
    if (state.queue.length <= 1) {
      await audio.clearQueue();
      emit(state.copyWith(
        queue: const [],
        index: 0,
        status: PlayerStatus.initial,
      ));
      return;
    }

    final newQueue = List<Track>.from(state.queue)..removeAt(index);
    int newIndex = state.index;

    if (index < state.index) {
      // Menghapus lagu sebelum lagu yang sedang diputar
      newIndex = state.index - 1;
      emit(state.copyWith(queue: newQueue, index: newIndex));
      await audio.removeTrackAt(index);
    } else if (index == state.index) {
      // Menghapus lagu yang sedang diputar -> beralih ke lagu berikutnya (atau indeks yang sama di antrean baru)
      newIndex = index >= newQueue.length ? newQueue.length - 1 : index;
      emit(state.copyWith(queue: newQueue, index: newIndex));
      await audio.removeTrackAt(index);
      if (newQueue.isNotEmpty) {
        await _jumpTo(newIndex);
      }
    } else {
      // Menghapus lagu setelah lagu yang sedang diputar
      emit(state.copyWith(queue: newQueue));
      await audio.removeTrackAt(index);
    }
    await _ensureEngineMatchesQueue();
  }

  /// Reorder urutan track dalam antrean
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex >= state.queue.length ||
        oldIndex == newIndex) {
      return;
    }

    final newQueue = List<Track>.from(state.queue);
    final movedItem = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, movedItem);

    // Sesuaikan currentIndex agar tetap menunjuk ke lagu yang sama yang sedang berputar
    int updatedCurrentIndex = state.index;
    if (oldIndex == state.index) {
      updatedCurrentIndex = newIndex;
    } else if (oldIndex < state.index && newIndex >= state.index) {
      updatedCurrentIndex = state.index - 1;
    } else if (oldIndex > state.index && newIndex <= state.index) {
      updatedCurrentIndex = state.index + 1;
    }

    emit(state.copyWith(queue: newQueue, index: updatedCurrentIndex));
    await audio.moveTrack(oldIndex, newIndex);
    await _ensureEngineMatchesQueue();
  }

  void _autoNext() {
    if (state.repeat == 'one') {
      audio.seek(Duration.zero);
      if (!audio.isPlaying) audio.toggle();
      return;
    }
    // Jika antrean utama habis, otomatis lanjutkan ke lagu berikutnya dari rekomendasi genre yang sama
    if (state.index >= state.queue.length - 1 && state.upNext.isNotEmpty) {
      unawaited(_appendAndPlayNext(state.upNext.first));
      return;
    }
    next();
  }

  /// Tambahkan [nextTrack] ke ujung antrean lalu putar langsung.
  ///
  /// Memakai `addAudioSource` + `skipTo` supaya playlist ExoPlayer TIDAK dibangun
  /// ulang. Versi lama memakai `playQueue([...state.queue, nextTrack], ...)` →
  /// `setAudioSources()` yang menghentikan lagu yang sedang berjalan sejenak dan
  /// me-reset media session (notifikasi bisa ikut hilang).
  Future<void> _appendAndPlayNext(Track nextTrack) async {
    final engineInSync = audio.playlistLength == state.queue.length;
    final appended = List<Track>.from(state.queue)..add(nextTrack);
    final filteredUpNext =
        state.upNext.where((t) => t.id != nextTrack.id).toList();

    if (!engineInSync) {
      // Playlist engine tidak sinkron → muat ulang antrean.
      await playQueue(appended, appended.length - 1);
      return;
    }

    await audio.addTrack(nextTrack);
    if (audio.playlistLength != appended.length) {
      await playQueue(appended, appended.length - 1);
      return;
    }

    // Item Q3: pangkas riwayat paling lama supaya antrean tidak tumbuh tanpa
    // batas (auto-lanjut menambah 1 lagu setiap lagu selesai). Selain riwayat
    // 20 lagu, total antrean juga dibatasi [_maxQueueLength]: kalau masih
    // berlebih (mis. user menumpuk banyak lagu manual), buang yang paling
    // lama — tapi jangan pernah membuang lagu yang sedang diputar.
    final historyExcess = state.index - _keepHistoryBehind;
    final lengthExcess = appended.length - _maxQueueLength;
    final rawDrop = historyExcess > lengthExcess ? historyExcess : lengthExcess;
    final safeDrop = rawDrop.clamp(0, state.index);
    final trimmed = safeDrop > 0 ? appended.sublist(safeDrop) : appended;
    final nextIndex = appended.length - 1 - safeDrop;

    // Emit dulu (dengan index yang sudah digeser oleh pemangkasan) supaya
    // perubahan index dari engine saat remove/skip hanya diikuti lewat
    // onIndexChanged, tanpa menggandakan pemuatan data.
    emit(state.copyWith(
      queue: trimmed,
      index: state.index - safeDrop,
      upNext: filteredUpNext,
    ));

    if (safeDrop > 0) await audio.removeTrackRange(0, safeDrop);

    // Perpindahan index diikuti lewat audio.onIndexChanged (jalur yang sama
    // dengan tombol next di notifikasi), jadi state.index tetap sinkron.
    await audio.skipTo(nextIndex);
  }

  /// Pastikan antrean di UI dan playlist engine tidak berbeda.
  ///
  /// Mutasi playlist di [AppAudioHandler] menelan kegagalan platform (hanya
  /// debugPrint), jadi tanpa pemeriksaan ini UI bisa menampilkan antrean yang
  /// tidak ada di engine (atau sebaliknya) tanpa terdeteksi.
  Future<void> _ensureEngineMatchesQueue() async {
    if (isClosed || state.queue.isEmpty) return;
    // Engine belum memuat apa pun (sesi belum dimulai / mode test) → bukan desync.
    if (audio.playlistLength == 0) return;
    if (audio.playlistLength == state.queue.length) return;

    debugPrint('Antrean UI (${state.queue.length}) != playlist engine '
        '(${audio.playlistLength}); menyinkronkan ulang.');
    await playQueue(List<Track>.from(state.queue), state.index);
  }

  @override
  Future<void> close() {
    positionNotifier.dispose();
    return super.close();
  }
}
