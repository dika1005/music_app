import 'package:equatable/equatable.dart';
import 'package:music_app/features/player/domain/entities/track.dart';

enum PlayerStatus { initial, loading, playing, paused, buffering, completed, error }

class PositionData {
  final Duration position;
  final Duration duration;

  const PositionData(this.position, this.duration);

  static const zero = PositionData(Duration.zero, Duration.zero);

  double get progress =>
      duration.inMilliseconds == 0 ? 0.0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionData &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          duration == other.duration;

  @override
  int get hashCode => position.hashCode ^ duration.hashCode;
}

/// State playback TANPA posisi/durasi.
///
/// `position`/`duration` sengaja TIDAK ikut di sini (lihat item 4.1): posisi berubah
/// ~5x per detik, jadi kalau masuk Equatable.props maka seluruh widget yang mendengar
/// PlayerCubit ikut rebuild 5x/detik. Posisi diangkut lewat
/// `PlayerCubit.positionNotifier` (ValueNotifier&lt;PositionData&gt;) yang hanya
/// didengar scrubber/progress bar.
class PlayerState extends Equatable {
  final PlayerStatus status;
  final List<Track> queue;
  final int index;
  final List<Track> upNext;
  final bool shuffle;
  final String repeat; // off | one | all
  final String? message;

  /// Urutan putar yang sedang dipakai engine audio saat acak aktif:
  /// [shuffleOrder]\[i] = indeks di dalam [queue] untuk posisi putar ke-i.
  ///
  /// Daftar "BERIKUTNYA DALAM ANTREAN" memakai ini supaya saat acak aktif ia
  /// menampilkan lagu yang benar-benar akan diputar (urutan posisi [queue] bisa
  /// berbeda dari urutan putar engine). Kosong bila acak tidak aktif / playlist
  /// belum dimuat.
  final List<int> shuffleOrder;

  const PlayerState({
    this.status = PlayerStatus.initial,
    this.queue = const [],
    this.index = 0,
    this.upNext = const [],
    this.shuffle = false,
    this.repeat = 'off',
    this.message,
    this.shuffleOrder = const [],
  });

  Track? get current => queue.isEmpty || index >= queue.length ? null : queue[index];

  PlayerState copyWith({
    PlayerStatus? status,
    List<Track>? queue,
    int? index,
    List<Track>? upNext,
    bool? shuffle,
    String? repeat,
    String? message,
    List<int>? shuffleOrder,
  }) =>
      PlayerState(
        status: status ?? this.status,
        queue: queue ?? this.queue,
        index: index ?? this.index,
        upNext: upNext ?? this.upNext,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        message: message ?? this.message,
        shuffleOrder: shuffleOrder ?? this.shuffleOrder,
      );

  @override
  List<Object?> get props =>
      [status, queue, index, upNext, shuffle, repeat, message, shuffleOrder];
}
