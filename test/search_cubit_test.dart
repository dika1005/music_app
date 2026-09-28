// Search: saran lokal dari riwayat, hasil kosong -> status empty, hasil -> loaded.
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/errors/failures.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/repositories/track_repository.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/search/presentation/bloc/search_cubit.dart';

class _Repo implements TrackRepository {
  _Repo({this.results = const []});
  final List<Track> results;

  @override
  Future<Either<Failure, List<Track>>> search(String q, {int limit = 20}) async => Right(results);
  @override
  Future<Either<Failure, List<Track>>> trending({int limit = 20}) async => const Right([]);
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
  test('query kosong mereset hasil dan suggestions', () {
    final cubit = SearchCubit(SearchTracks(_Repo()));
    cubit.onQueryChanged('co', const ['coldplay', 'jazz']);
    expect(cubit.state.suggestions, ['coldplay']);

    cubit.onQueryChanged('', const ['coldplay']);
    expect(cubit.state.suggestions, isEmpty);
    expect(cubit.state.status, SearchStatus.initial);
    cubit.close();
  });

  test('search tanpa hasil -> empty', () async {
    final cubit = SearchCubit(SearchTracks(_Repo()));
    await cubit.search('zzz');
    expect(cubit.state.status, SearchStatus.empty);
    expect(cubit.state.results, isEmpty);
    cubit.close();
  });

  test('search dengan hasil -> loaded', () async {
    final cubit = SearchCubit(
      SearchTracks(_Repo(results: const [Track(id: 'v1', title: 'Lagu', artist: 'Artis')])),
    );
    await cubit.search('lofi');
    expect(cubit.state.status, SearchStatus.loaded);
    expect(cubit.state.results.single.id, 'v1');
    cubit.close();
  });
}
