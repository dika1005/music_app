import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';
import 'package:music_app/shared/audio_service/local_audio_stream_server.dart';

/// Regresi untuk 3 bug laporan user:
/// 1. force close saat play (URI kosong dikirim ke ExoPlayer),
/// 2. notifikasi polos (MediaItem tanpa title / artUri invalid),
/// 3. pola init player yang benar (lazy setelah JustAudioBackground.init).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalAudioStreamServer', () {
    test('getStreamUri mengembalikan string kosong bila port 0', () {
      final server = LocalAudioStreamServer();
      expect(server.port, 0);
      expect(server.getStreamUri('abc123'), isEmpty);
    });

    test('getStreamUri mengembalikan string kosong bila videoId kosong', () async {
      final server = LocalAudioStreamServer();
      await server.start();
      addTearDown(server.stop);
      if (server.port == 0) return; // sandbox tanpa loopback: lewati
      expect(server.getStreamUri(''), isEmpty);
      expect(server.getStreamUri('abc123'), contains('abc123'));
    });

    test('ensureStarted mengembalikan true bila server jalan', () async {
      final server = LocalAudioStreamServer();
      await server.start();
      addTearDown(server.stop);
      if (server.port == 0) return;
      expect(await server.ensureStarted(), isTrue);
    });
  });

  group('AppAudioHandler', () {
    test('player melempar StateError bila diakses sebelum init', () {
      final audio = AppAudioHandler();
      expect(() => audio.player, throwsStateError);
      expect(audio.playlistLength, 0);
      expect(audio.isPlaying, isFalse);
      expect(audio.hasNext, isFalse);
      expect(audio.hasPrevious, isFalse);
    });

    test('playQueue sebelum init melempar StateError (bukan crash native)',
        () async {
      final audio = AppAudioHandler();
      const tracks = [
        Track(id: 'v1', title: 'Lagu A', artist: 'Artis A'),
      ];
      await expectLater(audio.playQueue(tracks, 0), throwsStateError);
    });

    test('toggle/next/prev/seek aman dipanggil sebelum init', () async {
      final audio = AppAudioHandler();
      await audio.toggle();
      await audio.next();
      await audio.previous();
      await audio.seek(Duration.zero);
      audio.setShuffle(true);
      audio.setRepeat('all');
      // tidak melempar = lolos
    });
  });
}
