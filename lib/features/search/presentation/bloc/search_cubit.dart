import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:music_app/core/utils/network_monitor.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';

enum SearchStatus { initial, loading, loaded, empty, error }

class SearchState extends Equatable {
  final SearchStatus status;
  final List<Track> results;
  final List<String> suggestions;
  final String query;
  final String? message;
  const SearchState({
    this.status = SearchStatus.initial,
    this.results = const [],
    this.suggestions = const [],
    this.query = '',
    this.message,
  });
  SearchState copyWith({
    SearchStatus? status,
    List<Track>? results,
    List<String>? suggestions,
    String? query,
    String? message,
  }) =>
      SearchState(
        status: status ?? this.status,
        results: results ?? this.results,
        suggestions: suggestions ?? this.suggestions,
        query: query ?? this.query,
        message: message,
      );
  @override
  List<Object?> get props => [status, results, suggestions, query, message];
}

class SearchCubit extends Cubit<SearchState> {
  final SearchTracks searchTracks;
  Timer? _debounce;
  int _seq = 0;

  SearchCubit(this.searchTracks) : super(const SearchState());

  /// Dipanggil tiap ketikan: update suggestions lokal langsung, tembak API 300ms setelah berhenti.
  void onQueryChanged(String q, List<String> history) {
    final query = q.trim();
    final sug = query.isEmpty
        ? <String>[]
        : history.where((h) => h.toLowerCase().contains(query.toLowerCase())).take(5).toList();
    emit(state.copyWith(query: q, suggestions: sug));
    if (query.isEmpty) {
      _debounce?.cancel();
      emit(state.copyWith(status: SearchStatus.initial, results: []));
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => search(q));
  }

  Future<void> search(String q) async {
    _debounce?.cancel(); // Batalkan timer debounce yang tertunda agar tidak ada 2 request bersamaan
    final query = q.trim();
    if (query.isEmpty) {
      emit(state.copyWith(status: SearchStatus.initial, results: []));
      return;
    }
    final mySeq = ++_seq;
    emit(state.copyWith(status: SearchStatus.loading, query: q));
    final res = await searchTracks(query);
    if (isClosed) return;
    if (mySeq != _seq) return; // Abaikan hasil basi

    res.fold(
      (f) {
        NetworkMonitor.instance.markOffline();
        emit(state.copyWith(status: SearchStatus.error, message: f.message));
      },
      (tracks) {
        NetworkMonitor.instance.markOnline();
        emit(state.copyWith(
          status: tracks.isEmpty ? SearchStatus.empty : SearchStatus.loaded,
          results: tracks,
        ));
      },
    );
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
