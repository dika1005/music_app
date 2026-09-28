import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/home/presentation/bloc/home_state.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';

class HomeCubit extends Cubit<HomeState> {
  final GetTrendingTracks getTrending;
  final SearchTracks searchTracks;
  HomeCubit(this.getTrending, this.searchTracks) : super(const HomeState());

  /// Cache trending agar tidak perlu fetch ulang setiap kali
  List<Track>? _cachedTrending;

  /// Cache hasil lagu per mood agar switching instan (0ms)
  final Map<String, List<Track>> _moodCache = {};

  /// Catatan saat data yang tampil berasal dari cache memori (item 5.4).
  static const String _staleNote = 'Mode offline — menampilkan data tersimpan.';

  Future<void> load({bool forceRefresh = false}) async {
    // Jika data sudah loaded dan tidak dipaksa refresh, jangan lakukan fetch ulang
    if (!forceRefresh && state.status == HomeStatus.loaded && state.tracks.isNotEmpty) {
      return;
    }

    // Jika sudah ada cache memori, gunakan langsung tanpa loading state
    if (!forceRefresh && _cachedTrending != null && _cachedTrending!.isNotEmpty) {
      emit(state.copyWith(
        status: HomeStatus.loaded,
        tracks: _cachedTrending!,
        message: NetworkMonitor.instance.online ? null : _staleNote,
      ));
      return;
    }

    emit(state.copyWith(status: HomeStatus.loading, message: null));
    final res = await getTrending(limit: 20);
    if (isClosed) return;
    res.fold(
      (f) {
        NetworkMonitor.instance.markOffline();
        final cached = _cachedTrending;
        if (cached != null && cached.isNotEmpty) {
          // Degradasi anggun: jangan ganti layar jadi error kalau masih ada data
          // tersimpan — tampilkan cache plus catatan offline.
          emit(state.copyWith(status: HomeStatus.loaded, tracks: cached, message: '$_staleNote ${f.message}'));
        } else {
          emit(state.copyWith(status: HomeStatus.error, message: f.message));
        }
      },
      (tracks) {
        NetworkMonitor.instance.markOnline();
        _cachedTrending = tracks;
        emit(state.copyWith(
          status: tracks.isEmpty ? HomeStatus.empty : HomeStatus.loaded,
          tracks: tracks,
          message: null,
        ));
      },
    );
  }

  Future<void> _refreshBackground() async {
    final res = await getTrending(limit: 20);
    if (isClosed) return;
    res.fold(
      (f) {
        NetworkMonitor.instance.markOffline();
        if (_cachedTrending != null && _cachedTrending!.isNotEmpty) {
          emit(state.copyWith(message: '$_staleNote ${f.message}'));
        }
      },
      (tracks) {
        NetworkMonitor.instance.markOnline();
        if (tracks.isNotEmpty) {
          _cachedTrending = tracks;
          emit(state.copyWith(tracks: tracks, message: null));
        }
      },
    );
  }

  Future<void> refresh() async {
    _moodCache.clear();
    // Item 5.4/UX: kalau sudah ada data, pull-to-refresh tidak perlu
    // mengosongkan layar jadi skeleton — tampilkan data sekarang, perbarui di
    // background (dan tandai kalau gagal / offline).
    if (state.status == HomeStatus.loaded && state.tracks.isNotEmpty) {
      await _refreshBackground();
      return;
    }
    _cachedTrending = null; // Invalidate cache
    await load(forceRefresh: true);
  }

  /// Pilih mood/genre: search via API YouTube Music dengan memory caching
  Future<void> selectMood(String mood) async {
    if (mood == state.activeMood) return;

    if (mood == 'All') {
      emit(state.copyWith(activeMood: 'All', moodTracks: const [], isMoodLoading: false));
      return;
    }

    // Jika sudah ada di cache, tampilkan instan tanpa delay
    if (_moodCache.containsKey(mood) && _moodCache[mood]!.isNotEmpty) {
      emit(state.copyWith(
        activeMood: mood,
        moodTracks: _moodCache[mood]!,
        isMoodLoading: false,
      ));
      return;
    }

    emit(state.copyWith(activeMood: mood, isMoodLoading: true));

    final String query;
    switch (mood.toLowerCase()) {
      case 'chill':
        query = 'Chill Acoustic Music';
        break;
      case 'focus':
        query = 'Instrumental Study Focus';
        break;
      case 'energize':
        query = 'Upbeat Dance Pop';
        break;
      case 'pop':
        query = 'Top Pop Hits Indonesia';
        break;
      case 'lo-fi':
        query = 'Lofi Hip Hop Beats';
        break;
      default:
        query = '$mood songs';
    }

    final res = await searchTracks(query, limit: 15);
    if (isClosed) return;
    res.fold(
      (_) {
        NetworkMonitor.instance.markOffline();
        emit(state.copyWith(isMoodLoading: false));
      },
      (tracks) {
        NetworkMonitor.instance.markOnline();
        if (tracks.isNotEmpty) {
          _moodCache[mood] = tracks;
          emit(state.copyWith(moodTracks: tracks, isMoodLoading: false));
        } else {
          emit(state.copyWith(isMoodLoading: false));
        }
      },
    );
  }
}
