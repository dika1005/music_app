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
  AppAudioHandler() : _player = AudioPlayer();

  final AudioPlayer _player;
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
  String _repeat = 'off';

  LocalAudioStreamServer get server => _server;
  AudioPlayer get player => _player;
  int get playlistLength => _player.audioSources.length;

  Future<void> init({Future<String?> Function(String videoId)? onResolveUrl}) async {
    _server.onResolveUrl = onResolveUrl;
    await _server.start();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    session.becomingNoisyEventStream.listen((_) => _player.pause());
    session.interruptionEventStream.listen((e) {
      if (e.begin) {
        _player.pause();
      } else if (e.type == AudioInterruptionType.pause ||
          e.type == AudioInterruptionType.duck) {
        _player.play();
      }
    });

    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        onStatus?.call(false, false);
      },
    );
    _player.positionStream.listen((pos) {
      onPosition?.call(pos, _player.duration ?? Duration.zero);
    });
    _player.playerStateStream.listen((s) {
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
      _player.processingStateStream.distinct().listen(
            (state) => debugPrint(
              '[audio] processingState=$state',
            ),
          );
    }
    _player.currentIndexStream.listen((idx) {
      if (idx != null) {
        onIndexChanged?.call(idx);
      }
    });
    // Perubahan acak/ulang dari notifikasi / panel media sistem mengalir ke
    // client just_audio lewat playerDataMessageStream, lalu ke stream ini.
    _player.shuffleModeEnabledStream.distinct().listen((enabled) {
      onShuffleChanged?.call(enabled);
    });
    _player.loopModeStream.distinct().listen((mode) {
      onRepeatChanged?.call(
        mode == LoopMode.one ? 'one' : mode == LoopMode.all ? 'all' : 'off',
      );
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
    return AudioSource.uri(
      Uri.parse(uriString),
      headers: _streamHeaders,
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album ?? 'MelodyFlow',
        duration: t.duration == Duration.zero ? null : t.duration,
        artUri: t.artworkUrl == null ? null : Uri.tryParse(t.artworkUrl!),
      ),
    );
  }

  Future<void> playQueue(List<Track> tracks, int start) async {
    try {
      if (tracks.isEmpty) {
        onStatus?.call(false, false);
        return;
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

      await _player.setAudioSources(sources, initialIndex: safeStart);
      await _player.play();
    } catch (_) {
      onStatus?.call(false, false);
      rethrow;
    }
  }

  /// Masukkan lagu baru ke dalam playlist antrean tepat di posisi targetIndex
  Future<void> insertTrack(int index, Track track) async {
    try {
      if (_player.audioSources.isEmpty) {
        return;
      }
      final source = _createAudioSource(track);
      final safeIndex = index.clamp(0, _player.audioSources.length);
      await _player.insertAudioSource(safeIndex, source);
    } catch (e) {
      debugPrint('Error inserting track to playlist: $e');
    }
  }

  /// Tambahkan lagu ke ujung akhir playlist antrean
  Future<void> addTrack(Track track) async {
    try {
      if (_player.audioSources.isEmpty) {
        return;
      }
      final source = _createAudioSource(track);
      await _player.addAudioSource(source);
    } catch (e) {
      debugPrint('Error adding track to playlist: $e');
    }
  }

  /// Hapus lagu dari antrean audio berdasarkan indeks
  Future<void> removeTrackAt(int index) async {
    try {
      if (index < 0 || index >= _player.audioSources.length) return;
      await _player.removeAudioSourceAt(index);
    } catch (e) {
      debugPrint('Error removing track from playlist: $e');
    }
  }

  /// Pindahkan urutan lagu di dalam antrean audio
  Future<void> moveTrack(int currentIndex, int newIndex) async {
    try {
      if (currentIndex < 0 ||
          currentIndex >= _player.audioSources.length ||
          newIndex < 0 ||
          newIndex >= _player.audioSources.length) {
        return;
      }
      await _player.moveAudioSource(currentIndex, newIndex);
    } catch (e) {
      debugPrint('Error moving track in playlist: $e');
    }
  }


  /// Matikan audio secara instan (<1ms) saat user berpindah lagu
  Future<void> stopImmediately() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  /// Kosongkan playlist engine. Dipakai saat antrean benar-benar dikosongkan.
  ///
  /// Kalau hanya di-pause, lagu terakhir tetap tersimpan di playlist ExoPlayer
  /// sehingga notifikasi/lockscreen masih bisa memutarnya lagi. `stop()` membuat
  /// processingState menjadi `idle`, dan audio_service memang menutup media
  /// session + notifikasi saat idle — persis yang diinginkan di kasus ini.
  Future<void> clearQueue() async {
    try {
      if (_player.audioSources.isEmpty) return;
      await _player.stop();
      await _player.clearAudioSources();
    } catch (e) {
      debugPrint('Error clearing playlist: $e');
    }
  }

  /// Buang sebagian lagu dari playlist engine (dipakai untuk memangkas riwayat
  /// antrean yang sudah terlalu panjang).
  Future<void> removeTrackRange(int start, int end) async {
    try {
      if (start < 0 || end <= start || end > _player.audioSources.length) return;
      await _player.removeAudioSourceRange(start, end);
    } catch (e) {
      debugPrint('Error removing track range from playlist: $e');
    }
  }

  Future<void> toggle() => _player.playing ? _player.pause() : _player.play();

  Future<void> skipTo(int index) async {
    if (index < 0 || index >= _player.audioSources.length) return;
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) {
      await _player.play();
    }
  }

  Future<void> next() => _player.seekToNext();
  Future<void> previous() => _player.seekToPrevious();
  Future<void> seek(Duration pos) => _player.seek(pos);

  void setShuffle(bool enabled) {
    _player.setShuffleModeEnabled(enabled);
  }

  void setRepeat(String mode) {
    _repeat = mode;
    _player.setLoopMode(mode == 'one' ? LoopMode.one : mode == 'all' ? LoopMode.all : LoopMode.off);
  }

  bool get hasNext => _player.hasNext;
  bool get hasPrevious => _player.hasPrevious;
  bool get isPlaying => _player.playing;

  String get repeat => _repeat;
}
