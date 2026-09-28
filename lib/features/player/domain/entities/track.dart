import 'package:equatable/equatable.dart';

/// Pure Dart. Tanpa import Flutter di domain.
/// id = videoId YouTube, streamUrl bisa kosong -> resolve lazy via getAudioUrlFast.
class Track extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String streamUrl;
  final Duration duration;
  final String? genre;
  final String? album;
  final String? year;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.streamUrl = '',
    this.artworkUrl,
    this.duration = Duration.zero,
    this.genre,
    this.album,
    this.year,
  });

  bool get hasStream => streamUrl.isNotEmpty;

  @override
  List<Object?> get props => [id, title, artist, streamUrl, artworkUrl, duration, genre, album, year];
}
