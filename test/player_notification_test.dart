// Notifikasi/sistem -> aplikasi: perubahan tombol acak/ulang dari notifikasi
// (atau panel media sistem / Android Auto) harus tercermin di state Cubit.
// Tes ini hanya memakai callback yang diekspos AppAudioHandler (jalur yang sama
// dengan listener stream di init()), tanpa memanggil player sungguhan supaya
// tidak butuh platform channel.
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/shared/audio_service/audio_handler.dart';

class _Repo implements TrackRepository {
  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => const Right([]);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tombol acak di notifikasi menyalakan/mematikan state shuffle Cubit', () async {
    final audio = AppAudioHandler();
    final cubit = PlayerCubit(audio, _Repo());
    addTearDown(cubit.close);

    expect(cubit.state.shuffle, isFalse);

    // Simulasi: pengguna mengetuk tombol acak di notifikasi -> handler service
    // mengubah mode -> stream player memancarkan nilai baru.
    audio.onShuffleChanged?.call(true);
    expect(cubit.state.shuffle, isTrue);

    audio.onShuffleChanged?.call(false);
    expect(cubit.state.shuffle, isFalse);
  });

  test('tombol ulang bawaan sistem menyinkronkan state repeat Cubit (off/all/one)', () async {
    final audio = AppAudioHandler();
    final cubit = PlayerCubit(audio, _Repo());
    addTearDown(cubit.close);

    expect(cubit.state.repeat, 'off');

    audio.onRepeatChanged?.call('all');
    expect(cubit.state.repeat, 'all');

    audio.onRepeatChanged?.call('one');
    expect(cubit.state.repeat, 'one');

    audio.onRepeatChanged?.call('off');
    expect(cubit.state.repeat, 'off');
  });

  test('callback dengan nilai sama tidak mengubah state (anti duplikat event)', () async {
    final audio = AppAudioHandler();
    final cubit = PlayerCubit(audio, _Repo());
    addTearDown(cubit.close);

    audio.onShuffleChanged?.call(false);
    expect(cubit.state.shuffle, isFalse);

    audio.onRepeatChanged?.call('off');
    expect(cubit.state.repeat, 'off');
  });
}
