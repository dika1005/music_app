import 'package:dartz/dartz.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';

/// Implementasi TrackRepository yang 100% menggunakan YtMusicDataSource
/// (didukung oleh plugin yt_flutter_musicapi: Chaquopy Python ytmusicapi + yt-dlp).
/// Seluruh fitur pencarian, streaming audio, sampul album, antrean lagu, tangga lagu,
/// dan lirik dikelola murni melalui API ini.
class TrackRepositoryImpl implements TrackRepository {
  final YtMusicDataSource yt;
  const TrackRepositoryImpl(this.yt);

  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async {
    try {
      final tracks = await yt.charts(limit: limit);
      if (tracks.isNotEmpty) return Right(tracks);
      final fallback = await yt.search('Top Hits', limit: limit);
      if (fallback.isNotEmpty) return Right(fallback);
      return const Left(EmptyFailure('Belum ada tangga lagu saat ini. Tarik untuk menyegarkan.'));
    } catch (e) {
      try {
        final fallback = await yt.search('Top Hits', limit: limit);
        if (fallback.isNotEmpty) return Right(fallback);
      } catch (_) {}
      return Left(ServerFailure('Gagal memuat tangga lagu dari YouTube Music: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Track>>> search(String query, {int limit = 20}) async {
    try {
      final tracks = await yt.search(query, limit: limit);
      if (tracks.isNotEmpty) return Right(tracks);
      return Left(EmptyFailure('Tidak ditemukan lagu untuk "$query". Coba kata kunci lain.'));
    } catch (e) {
      return Left(ServerFailure('Pencarian "$query" gagal: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Track>>> related(Track track, {int limit = 10}) async {
    try {
      final tracks = await yt.related(track, limit: limit);
      return Right(tracks);
    } catch (_) {
      return const Right([]);
    }
  }

  @override
  Future<Either<Failure, String>> audioUrl(String videoId) async {
    try {
      final url = await yt.audioUrl(videoId);
      if (url.isNotEmpty) return Right(url);
      return const Left(ServerFailure('URL audio tidak ditemukan.'));
    } catch (e) {
      return Left(ServerFailure('Audio tidak dapat diputar: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> lyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    try {
      final text = await yt.lyrics(title: title, artist: artist, duration: duration);
      if (text.isNotEmpty) return Right(text);
      return const Left(ServerFailure('Lirik tidak tersedia untuk lagu ini.'));
    } catch (e) {
      return Left(ServerFailure('Gagal memuat lirik: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Track>>> artistSongs(String artist, {int limit = 25}) async {
    try {
      final tracks = await yt.artistSongs(artist, limit: limit);
      if (tracks.isNotEmpty) return Right(tracks);
      return Left(EmptyFailure('Tidak ditemukan lagu untuk $artist.'));
    } catch (e) {
      return Left(ServerFailure('Gagal memuat lagu artis: $e'));
    }
  }
}
