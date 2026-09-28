import 'package:dartz/dartz.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';

class GetTrendingTracks {
  final TrackRepository repo;
  const GetTrendingTracks(this.repo);

  Future<Either<Failure, List<Track>>> call({int limit = 20}) =>
      repo.trending(limit: limit);
}

class SearchTracks {
  final TrackRepository repo;
  const SearchTracks(this.repo);

  Future<Either<Failure, List<Track>>> call(String query, {int limit = 20}) {
    if (query.trim().isEmpty) return Future.value(const Right([]));
    return repo.search(query.trim(), limit: limit);
  }
}

class GetRelatedTracks {
  final TrackRepository repo;
  const GetRelatedTracks(this.repo);

  Future<Either<Failure, List<Track>>> call(Track track, {int limit = 10}) =>
      repo.related(track, limit: limit);
}

class GetLyrics {
  final TrackRepository repo;
  const GetLyrics(this.repo);

  Future<Either<Failure, String>> call({
    required String title,
    required String artist,
    Duration? duration,
  }) =>
      repo.lyrics(title: title, artist: artist, duration: duration);
}
