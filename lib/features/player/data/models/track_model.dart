import 'package:music_app/features/player/domain/entities/track.dart';

/// Data Model Track untuk serialisasi & mapping YouTube Music.
class TrackModel extends Track {
  const TrackModel({
    required super.id,
    required super.title,
    required super.artist,
    super.streamUrl = '',
    super.artworkUrl,
    super.duration,
    super.genre,
    super.album,
    super.year,
  });

  factory TrackModel.fromMap(Map<String, dynamic> m) {
    return TrackModel(
      id: '${m['videoId'] ?? m['id'] ?? ''}',
      title: (m['title'] as String?) ?? 'Unknown title',
      artist: (m['artists'] as String?) ??
          (m['artist'] as String?) ??
          (m['author'] as String?) ??
          'Unknown artist',
      streamUrl: (m['audioUrl'] as String?) ?? '',
      artworkUrl: (m['albumArt'] as String?) ?? (m['artwork'] as String?),
      duration: _parseDuration(m['duration'] ?? m['lengthSeconds']),
      album: m['album'] as String?,
      genre: m['genre'] as String?,
      year: '${m['year'] ?? ''}'.isEmpty ? null : '${m['year']}',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'streamUrl': streamUrl,
        'artworkUrl': artworkUrl,
        'duration': duration.inSeconds,
        'album': album,
        'genre': genre,
        'year': year,
      };

  static Duration _parseDuration(dynamic raw) {
    if (raw == null) return Duration.zero;
    if (raw is Duration) return raw;
    if (raw is num) return Duration(seconds: raw.toInt());
    final s = '$raw'.trim();
    if (s.isEmpty) return Duration.zero;
    final parts = s.split(':').map(int.tryParse).toList();
    if (parts.any((e) => e == null)) return Duration.zero;
    final nums = parts.cast<int>();
    if (nums.length == 1) return Duration(seconds: nums[0]);
    if (nums.length == 2) return Duration(minutes: nums[0], seconds: nums[1]);
    if (nums.length == 3) return Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
    return Duration.zero;
  }
}
