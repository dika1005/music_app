import 'package:equatable/equatable.dart';
import 'package:music_app/features/player/domain/entities/track.dart';

/// Kumpulan lagu yang dianggap satu "album".
/// Utamakan metadata `Track.album` (ada di Android via YT plugin);
/// kalau kosong, lagu dikelompokkan per artis jadi `Koleksi <artis>`.
class AlbumGroup extends Equatable {
  final String title;
  final String artist;
  final String? artworkUrl;
  final List<Track> tracks;
  final bool isRealAlbum;

  const AlbumGroup({
    required this.title,
    required this.artist,
    required this.tracks,
    this.artworkUrl,
    this.isRealAlbum = false,
  });

  String get subtitle => isRealAlbum ? artist : '${tracks.length} lagu';

  @override
  List<Object?> get props => [title, artist];

  /// Bikin grup dari daftar lagu. Metadata album dipakai dulu, sisanya per artis.
  static List<AlbumGroup> fromTracks(List<Track> tracks, {int max = 6}) {
    final byAlbum = <String, List<Track>>{};
    final byArtist = <String, List<Track>>{};
    for (final t in tracks) {
      final album = t.album?.trim() ?? '';
      if (album.isNotEmpty) {
        byAlbum.putIfAbsent('$album\u0000${t.artist}', () => []).add(t);
      } else {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }
    }
    final groups = <AlbumGroup>[];
    byAlbum.forEach((key, list) {
      final parts = key.split('\u0000');
      groups.add(AlbumGroup(
        title: parts.first,
        artist: parts.length > 1 ? parts[1] : list.first.artist,
        tracks: list,
        artworkUrl: list.first.artworkUrl,
        isRealAlbum: true,
      ));
    });
    byArtist.forEach((artist, list) {
      groups.add(AlbumGroup(
        title: 'Koleksi $artist',
        artist: artist,
        tracks: list,
        artworkUrl: list.first.artworkUrl,
      ));
    });
    groups.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    return groups.take(max).toList();
  }
}
