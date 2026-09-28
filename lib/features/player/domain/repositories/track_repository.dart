import 'package:dartz/dartz.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';

abstract class TrackRepository {
  Future<Either<Failure, List<Track>>> trending({int limit = 20});
  Future<Either<Failure, List<Track>>> search(String query, {int limit = 20});
  Future<Either<Failure, List<Track>>> related(Track track, {int limit = 10});
  Future<Either<Failure, String>> audioUrl(String videoId);
  /// [duration] opsional dipakai memvalidasi lirik dari LRCLIB (versi lain
  /// seperti live/remix punya durasi berbeda → lirik selalu geser).
  Future<Either<Failure, String>> lyrics({
    required String title,
    required String artist,
    Duration? duration,
  });
  Future<Either<Failure, List<Track>>> artistSongs(String artist, {int limit = 25});
}
