import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/shared/audio_service/local_audio_stream_server.dart';

/// Bungkus just_audio: queue gapless, lockscreen & notification metadata,
/// audio focus (call/notif), pre-buffer lagu berikutnya, dan loopback server
/// untuk memastikan semua tombol navigasi (next/prev) di notifikasi selalu aktif.
class AppAudioHandler {
  AppAudioHandler();

  AudioPlayer? _player;
  AudioPlayer get player {
    final p = _player;
    if (p == null) {
      throw StateError(
        'AppAudioHandler belum di-init (AudioPlayer dibuat setelah '
        'JustAudioBackground.init agar tidak premature).',
      );
    }
    return p;
  }

  /// Null-safe untuk pemakaian UI sebelum init selesai.
  AudioPlayer? get playerOrNull => _player;
  final LocalAudioStreamServer _server = LocalAudioStreamServer();

  void Function(Duration pos, Duration dur)? onPosition;
  void Function(bool playing, bool buffering)? onStatus;
  void Function(int index)? onIndexChanged;
  void Function()? onCompleted;
  // Tombol next/prev di notifikasi ditangani langsung oleh audio service
  // (lihat third_party/just_audio_background/VENDOR_PATCH.md); aplikasi hanya
  // mengikuti perubahannya lewat onIndexChanged di bawah. Yang perlu disambung
  // manual adalah tombol acak/ulang: bisa berubah dari notifikasi, panel media
  // sistem (Android 13+), atau Android Auto.
  /// Mode acak berubah dari luar UI aplikasi (notifikasi/sistem).
  void Function(bool enabled)? onShuffleChanged;
  /// Mode ulang ('off' | 'all' | 'one') berubah dari luar UI aplikasi.
  void Function(String mode)? onRepeatChanged;
  /// Urutan putar engine berubah (playlist dimuat ulang / acak diaktifkan /
  /// playlist dimutasi). Isinya indeks [queue] untuk tiap posisi putar.
  void Function(List<int> order)? onShuffleOrderChanged;
  String _repeat = 'off';

  LocalAudioStreamServer get server => _server;
  int get playlistLength => _player?.audioSources.length ?? 0;

  /// Urutan putar yang sedang dipakai engine (indeks di dalam playlist).
  ///
  /// Saat acak aktif, urutan ini adalah urutan acak NYATA yang dijalankan
  /// ExoPlayer — bukan urutan posisi playlist. UI "BERIKUTNYA DALAM ANTREAN"
  /// memakainya supaya tidak menampilkan lagu yang belum tentu diputar
  /// berikutnya. Kosong bila playlist belum dimuat.
  List<int> get shuffleOrder => _player?.shuffleIndices ?? const [];

  Future<void> init({Future<String?> Function(String videoId)? onResolveUrl}) async {
    _server.onResolveUrl = onResolveUrl;
    await _server.start();

    // Player dibuat LAZY di sini (setelah JustAudioBackground.init di main).
    final p = AudioPlayer();
    _player = p;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) {
      try {
        p.pause();
      } catch (_) {}
    });
    session.interruptionEventStream.listen((e) {
      try {
        if (e.begin) {
          p.pause();
        } else if (e.type == AudioInterruptionType.pause ||
            e.type == AudioInterruptionType.duck) {
          p.play();
        }
      } catch (_) {}
    });

    p.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('playbackEvent error: $e');
        onStatus?.call(false, false);
      },
    );
    p.positionStream.listen((pos) {
      onPosition?.call(pos, p.duration ?? Duration.zero);
    });
    p.playerStateStream.listen((s) {
      final buffering = s.processingState == ProcessingState.loading ||
          s.processingState == ProcessingState.buffering;
      onStatus?.call(s.playing, buffering);
      if (s.processingState == ProcessingState.completed) onCompleted?.call();
    });

    if (kDebugMode) {
      // Jejak diagnosa notifikasi: processingState `idle` membuat audio_service
      // menutup media session + notifikasi (lihat AudioService.setState() di
      // audio_service 0.18.19: `if (oldState != idle && state == idle) stop()`).
      // Cek lewat `adb logcat | grep "\[audio\]"` kalau notifikasi hilang.
      p.processingStateStream.distinct().listen(
            (state) => debugPrint(
              '[audio] processingState=$state',
            ),
          );
    }
    p.currentIndexStream.listen((idx) {
      if (idx != null) {
        onIndexChanged?.call(idx);
      }
    });
    // Perubahan acak/ulang dari notifikasi / panel media sistem mengalir ke
    // client just_audio lewat playerDataMessageStream, lalu ke stream ini.
    p.shuffleModeEnabledStream.distinct().listen((enabled) {
      onShuffleChanged?.call(enabled);
    });
    p.loopModeStream.distinct().listen((mode) {
      onRepeatChanged?.call(
        mode == LoopMode.one ? 'one' : mode == LoopMode.all ? 'all' : 'off',
      );
    });
    // Urutan putar (acak) engine ikut dipancarkan ke UI. Tidak di-`distinct()`
    // karena perbandingan List memakai identity; deduplikasi dilakukan di
    // PlayerCubit dengan membandingkan isi.
    p.shuffleIndicesStream.listen((order) {
      onShuffleOrderChanged?.call(order);
    });
  }

  static const _streamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Encoding': 'identity',
  };

  AudioSource _createAudioSource(Track t) {
    final uriString = t.streamUrl.isNotEmpty
        ? t.streamUrl
        : _server.getStreamUri(t.id);
    // Guard anti force-close: URI kosong JANGAN dikirim ke ExoPlayer.
    if (uriString.isEmpty) {
      throw ArgumentError(
        'Tidak ada streamUri untuk "${t.title}" (id=${t.id}, '
        'serverPort=${_server.port})',
      );
    }
    Uri? artUri;
    final rawArt = t.artworkUrl?.trim() ?? '';
    if (rawArt.isNotEmpty) {
      final parsed = Uri.tryParse(rawArt);
      if (parsed != null && parsed.hasScheme) artUri = parsed;
    }
    final title = t.title.trim().isEmpty ? 'Unknown title' : t.title.trim();
    final artist =
        t.artist.trim().isEmpty ? 'Unknown artist' : t.artist.trim();
    return AudioSource.uri(
      Uri.parse(uriString),
      headers: _streamHeaders,
      tag: MediaItem(
        id: t.id.isEmpty ? uriString : t.id,
        title: title,
        artist: artist,
        album: (t.album == null || t.album!.trim().isEmpty)
            ? 'MelodyFlow'
            : t.album!.trim(),
        duration: t.duration == Duration.zero ? null : t.duration,
        artUri: artUri,
      ),
    );
  }

  Future<void> playQueue(List<Track> tracks, int start) async {
    final p = _player;
    if (p == null) {
      onStatus?.call(false, false);
      throw StateError('AudioPlayer belum di-init.');
    }
    try {
      if (tracks.isEmpty) {
        onStatus?.call(false, false);
        return;
      }
      final serverOk = await _server.ensureStarted();
      if (!serverOk) {
        onStatus?.call(false, false);
        throw StateError('LocalAudioStreamServer gagal start (port 0).');
      }
      final safeStart = start.clamp(0, tracks.length - 1);
      final sources = <AudioSource>[];

      for (var i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        sources.add(_createAudioSource(t));
      }

      if (sources.isEmpty) {
        onStatus?.call(false, false);
        return;
      }

      await p.setAudioSources(sources, initialIndex: safeStart);
      await p.play();
    } catch (_) {
      onStatus?.call(false, false);
      rethrow;
    }
  }

  /// Masukkan lagu baru ke dalam playlist antrean tepat di posisi targetIndex
  Future<void> insertTrack(int index, Track track) async {
    final p = _player;
    if (p == null) return;
    try {
      if (p.audioSources.isEmpty) {
        return;
      }
      final source = _createAudioSource(track);
      final safeIndex = index.clamp(0, p.audioSources.length);
      await p.insertAudioSource(safeIndex, source);
    } catch (e) {
      debugPrint('Error inserting track to playlist: $e');
    }
  }

  /// Tambahkan lagu ke ujung akhir playlist antrean
  Future<void> addTrack(Track track) async {
    final p = _player;
    if (p == null) return;
    try {
      if (p.audioSources.isEmpty) {
        return;
      }
      final source = _createAudioSource(track);
      await p.addAudioSource(source);
    } catch (e) {
      debugPrint('Error adding track to playlist: $e');
    }
  }

  /// Hapus lagu dari antrean audio berdasarkan indeks
  Future<void> removeTrackAt(int index) async {
    final p = _player;
    if (p == null) return;
    try {
      if (index < 0 || index >= p.audioSources.length) return;
      await p.removeAudioSourceAt(index);
    } catch (e) {
      debugPrint('Error removing track from playlist: $e');
    }
  }

  /// Pindahkan urutan lagu di dalam antrean audio
  Future<void> moveTrack(int currentIndex, int newIndex) async {
    final p = _player;
    if (p == null) return;
    try {
      if (currentIndex < 0 ||
          currentIndex >= p.audioSources.length ||
          newIndex < 0 ||
          newIndex >= p.audioSources.length) {
        return;
      }
      await p.moveAudioSource(currentIndex, newIndex);
    } catch (e) {
      debugPrint('Error moving track in playlist: $e');
    }
  }


  Future<void> stopImmediately() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  /// Kosongkan playlist engine. Dipakai saat antrean benar-benar dikosongkan.
  ///
  /// Kalau hanya di-pause, lagu terakhir tetap tersimpan di playlist ExoPlayer
  /// sehingga notifikasi/lockscreen masih bisa memutarnya lagi. `stop()` membuat
  /// processingState menjadi `idle`, dan audio_service memang menutup media
  /// session + notifikasi saat idle — persis yang diinginkan di kasus ini.
  Future<void> clearQueue() async {
    final p = _player;
    if (p == null) return;
    try {
      if (p.audioSources.isEmpty) return;
      await p.stop();
      await p.clearAudioSources();
    } catch (e) {
      debugPrint('Error clearing playlist: $e');
    }
  }

  /// Buang sebagian lagu dari playlist engine (dipakai untuk memangkas riwayat
  /// antrean yang sudah terlalu panjang).
  Future<void> removeTrackRange(int start, int end) async {
    final p = _player;
    if (p == null) return;
    try {
      if (start < 0 || end <= start || end > p.audioSources.length) return;
      await p.removeAudioSourceRange(start, end);
    } catch (e) {
      debugPrint('Error removing track range from playlist: $e');
    }
  }

  Future<void> toggle() async {
    final p = _player;
    if (p == null) return;
    try {
      await (p.playing ? p.pause() : p.play());
    } catch (e) {
      debugPrint('toggle error: $e');
      onStatus?.call(false, false);
    }
  }

  Future<void> skipTo(int index) async {
    final p = _player;
    if (p == null) return;
    if (index < 0 || index >= p.audioSources.length) return;
    await p.seek(Duration.zero, index: index);
    if (!p.playing) {
      await p.play();
    }
  }

  Future<void> next() async {
    try {
      await _player?.seekToNext();
    } catch (e) {
      debugPrint('next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await _player?.seekToPrevious();
    } catch (e) {
      debugPrint('previous error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _player?.seek(pos);
    } catch (e) {
      debugPrint('seek error: $e');
    }
  }

  void setShuffle(bool enabled) {
    try {
      _player?.setShuffleModeEnabled(enabled);
    } catch (e) {
      debugPrint('setShuffle error: $e');
    }
  }

  /// Acak ulang urutan putar playlist tanpa menghentikan lagu aktif maupun
  /// membangun ulang media session/notifikasi.
  ///
  /// just_audio memakai satu urutan acak yang dibuat saat playlist dimuat, jadi
  /// tanpa ini mengaktifkan Acak berulang kali selalu memberi urutan yang sama.
  Future<void> reshuffle() async {
    try {
      await _player?.shuffle();
    } catch (e) {
      debugPrint('reshuffle error: $e');
    }
  }

  void setRepeat(String mode) {
    _repeat = mode;
    try {
      _player?.setLoopMode(mode == 'one'
          ? LoopMode.one
          : mode == 'all'
              ? LoopMode.all
              : LoopMode.off);
    } catch (e) {
      debugPrint('setRepeat error: $e');
    }
  }

  bool get hasNext => _player?.hasNext ?? false;
  bool get hasPrevious => _player?.hasPrevious ?? false;
  bool get isPlaying => _player?.playing ?? false;

  String get repeat => _repeat;

  /// Dipanggil saat aplikasi di-swipe tutup (detached) dalam keadaan pause:
  /// hentikan service supaya notifikasi tidak nyangkut.
  Future<void> stopService() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _server.stop();
    } catch (_) {}
  }
}
