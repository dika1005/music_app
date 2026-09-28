import 'package:equatable/equatable.dart';
import 'package:music_app/features/player/domain/entities/track.dart';

enum HomeStatus { initial, loading, loaded, error, empty }

class HomeState extends Equatable {
  final HomeStatus status;
  final List<Track> tracks;
  final String? message;
  /// Lagu hasil pencarian mood/genre dari API
  final List<Track> moodTracks;
  final String activeMood;
  final bool isMoodLoading;

  const HomeState({
    this.status = HomeStatus.initial,
    this.tracks = const [],
    this.message,
    this.moodTracks = const [],
    this.activeMood = 'All',
    this.isMoodLoading = false,
  });

  HomeState copyWith({
    HomeStatus? status,
    List<Track>? tracks,
    String? message,
    List<Track>? moodTracks,
    String? activeMood,
    bool? isMoodLoading,
  }) =>
      HomeState(
        status: status ?? this.status,
        tracks: tracks ?? this.tracks,
        message: message,
        moodTracks: moodTracks ?? this.moodTracks,
        activeMood: activeMood ?? this.activeMood,
        isMoodLoading: isMoodLoading ?? this.isMoodLoading,
      );

  @override
  List<Object?> get props => [status, tracks, message, moodTracks, activeMood, isMoodLoading];
}
