import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sebuah playlist buatan pengguna
class UserPlaylist extends Equatable {
  final String id;
  final String name;
  final List<Track> tracks;
  final DateTime createdAt;

  const UserPlaylist({
    required this.id,
    required this.name,
    this.tracks = const [],
    required this.createdAt,
  });

  UserPlaylist copyWith({String? name, List<Track>? tracks}) => UserPlaylist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, name, tracks, createdAt];
}

class LibraryState extends Equatable {
  final List<Track> favorites;
  final List<Track> recents;
  final List<String> queries;
  final Map<String, int> playCounts;
  /// Hasil pencarian terakhir. Dipakai home untuk blok "Dari pencarianmu".
  final List<Track> searchResults;
  final String lastQuery;
  /// Custom playlists buatan pengguna
  final List<UserPlaylist> playlists;
  LibraryState({
    this.favorites = const [],
    this.recents = const [],
    this.queries = const [],
    this.playCounts = const {},
    this.searchResults = const [],
    this.lastQuery = '',
    this.playlists = const [],
  });

  // ---- Memoization (item 4.3 & 4.4) --------------------------------------
  // State ini dibuat baru pada setiap emit dan tidak pernah dimutasi dari luar,
  // jadi cache di bawah tidak perlu invalidasi manual: instance baru = cache
  // baru. Sebelumnya `isFav` linear search dan getter seperti `mostPlayed`
  // men-sort ulang setiap kali diakses (termasuk setiap build Home).
  // Cache disimpan di objek terpisah supaya semua field LibraryState tetap final.
  final _LibraryMemo _memo = _LibraryMemo();

  /// O(1) setelah akses pertama (dulu O(n) untuk setiap track tile).
  bool isFav(String id) {
    _memo.favIds ??= {for (final t in favorites) t.id};
    return _memo.favIds!.contains(id);
  }

  /// Semua lagu yang pernah dilihat user: riwayat putar + hasil pencarian (dipakai untuk rekomendasi Home).
  List<Track> get tastePool => _memo.tastePool ??= _dedupe([...recents, ...searchResults]);

  /// Koleksi murni user (hanya favorit dan riwayat putar).
  /// Menjamin koleksi kosong jika belum pernah ada lagu yang diputar atau difavoritkan.
  List<Track> get libraryPool => _memo.libraryPool ??= _dedupe([...favorites, ...recents]);

  /// Artis murni dari koleksi lagu yang pernah diputar / difavoritkan.
  List<String> get libraryArtists =>
      _memo.libraryArtists ??= _rankArtists(favorites, 5, recents, 3);

  /// Artis tersering dari histori putar + hasil pencarian. Untuk blok Home "Artis top".
  List<String> get topArtists => _memo.topArtists ??= _rankArtists(recents, 3, searchResults, 1);

  /// Lagu tersering diputar dari riwayat. Untuk blok "Sering diputar".
  List<Track> get mostPlayed {
    return _memo.mostPlayed ??= () {
      final sorted = List<Track>.from(recents);
      sorted.sort((a, b) => (playCounts[b.id] ?? 0).compareTo(playCounts[a.id] ?? 0));
      return sorted.take(10).toList();
    }();
  }

  static List<Track> _dedupe(List<Track> tracks) {
    final seen = <String>{};
    final out = <Track>[];
    for (final t in tracks) {
      if (seen.add(t.id)) out.add(t);
    }
    return out;
  }

  /// Bobot artis: daftar [a] bernilai [weightA], daftar [b] bernilai [weightB]. Ambil 8 teratas.
  static List<String> _rankArtists(List<Track> a, int weightA, List<Track> b, int weightB) {
    final byArtist = <String, int>{};
    for (final t in a) {
      byArtist[t.artist] = (byArtist[t.artist] ?? 0) + weightA;
    }
    for (final t in b) {
      byArtist[t.artist] = (byArtist[t.artist] ?? 0) + weightB;
    }
    final sorted = byArtist.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return sorted.take(8).map((e) => e.key).toList();
  }

  LibraryState copyWith({
    List<Track>? favorites,
    List<Track>? recents,
    List<String>? queries,
    Map<String, int>? playCounts,
    List<Track>? searchResults,
    String? lastQuery,
    List<UserPlaylist>? playlists,
  }) =>
      LibraryState(
        favorites: favorites ?? this.favorites,
        recents: recents ?? this.recents,
        queries: queries ?? this.queries,
        playCounts: playCounts ?? this.playCounts,
        searchResults: searchResults ?? this.searchResults,
        lastQuery: lastQuery ?? this.lastQuery,
        playlists: playlists ?? this.playlists,
      );

  @override
  List<Object?> get props => [favorites, recents, queries, playCounts, searchResults, lastQuery, playlists];
}

/// Holder cache lazily-computed milik [LibraryState].
///
/// Dipisah dari LibraryState supaya semua field state tetap `final` (Equatable
/// ditandai @immutable) sambil tetap bisa memoize hasil perhitungan.
class _LibraryMemo {
  Set<String>? favIds;
  List<Track>? tastePool;
  List<Track>? libraryPool;
  List<String>? libraryArtists;
  List<String>? topArtists;
  List<Track>? mostPlayed;
}

/// Favorit + riwayat + query + hitung putar + custom playlists.
/// Disimpan ke disk supaya personalisasi Home tetap ada setelah app dibuka ulang.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit() : super(LibraryState());

  static const _kFavs = 'lib.favorites';
  static const _kRecents = 'lib.recents';
  static const _kQueries = 'lib.queries';
  static const _kCounts = 'lib.playCounts';
  static const _kPlaylists = 'lib.playlists';

  SharedPreferences? _prefs;
  Future<void> _saveQueue = Future<void>.value();
  bool _restored = false;

  /// Selesai kalau semua penyimpanan selesai. Dipakai test biar deterministik.
  Future<void> get saved async {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer?.cancel();
      await _writeToPrefs();
    }
    await _saveQueue;
  }

  /// Muat data lama. Dipanggil sekali saat startup (lihat injection.dart).
  /// Kalau storage tidak tersedia (web privat/test), jalan in-memory saja.
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      final counts = <String, int>{};
      final raw = p.getString(_kCounts);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) => counts[k] = v is num ? v.toInt() : int.tryParse('$v') ?? 0);
      }
      emit(state.copyWith(
        favorites: _decodeTracks(p.getString(_kFavs)),
        recents: _decodeTracks(p.getString(_kRecents)),
        queries: p.getStringList(_kQueries) ?? const [],
        playCounts: counts,
        playlists: _decodePlaylists(p.getString(_kPlaylists)),
      ));
    } catch (_) {
      _prefs = null;
    }
  }

  void toggleFavorite(Track track) {
    final favs = List<Track>.from(state.favorites);
    if (favs.any((t) => t.id == track.id)) {
      favs.removeWhere((t) => t.id == track.id);
    } else {
      favs.insert(0, track);
    }
    emit(state.copyWith(favorites: favs));
    _persist();
  }

  void pushRecent(Track track) {
    final recents = List<Track>.from(state.recents)..removeWhere((t) => t.id == track.id);
    recents.insert(0, track);
    final counts = Map<String, int>.from(state.playCounts);
    counts[track.id] = (counts[track.id] ?? 0) + 1;
    emit(state.copyWith(recents: recents.take(30).toList(), playCounts: counts));
    _persist();
  }

  void pushQuery(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    final queries = List<String>.from(state.queries)..removeWhere((e) => e.toLowerCase() == query.toLowerCase());
    queries.insert(0, query);
    emit(state.copyWith(queries: queries.take(10).toList()));
    _persist();
  }

  /// Hapus seluruh riwayat pencarian (tombol "Hapus" di halaman Cari).
  void clearQueries() {
    if (state.queries.isEmpty) return;
    emit(state.copyWith(queries: const []));
    _persist();
  }

  /// Simpan hasil pencarian supaya home bisa menampilkan blok personal.
  void pushSearchResults(String query, List<Track> results) {
    emit(state.copyWith(searchResults: results.take(30).toList(), lastQuery: query.trim()));
  }

  /// Lagu tersering diputar. Data saja: blok "Sering diputar" di Home dihapus
  /// karena isinya sama dengan riwayat (hanya diurutkan ulang per play count).
  List<Track> get mostPlayed => state.mostPlayed;

  /// Campuran riwayat + hasil pencarian, untuk blok album/artis.
  List<Track> get tasteTracks => state.tastePool;

  // === Custom Playlist Methods ===

  /// Buat playlist baru
  UserPlaylist createPlaylist(String name) {
    final playlist = UserPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
    );
    final playlists = List<UserPlaylist>.from(state.playlists)..insert(0, playlist);
    emit(state.copyWith(playlists: playlists));
    _persist();
    return playlist;
  }

  /// Hapus playlist
  void deletePlaylist(String playlistId) {
    final playlists = List<UserPlaylist>.from(state.playlists)
      ..removeWhere((p) => p.id == playlistId);
    emit(state.copyWith(playlists: playlists));
    _persist();
  }

  /// Tambah lagu ke playlist
  void addToPlaylist(String playlistId, Track track) {
    final playlists = List<UserPlaylist>.from(state.playlists);
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final playlist = playlists[idx];
    if (playlist.tracks.any((t) => t.id == track.id)) return; // sudah ada
    playlists[idx] = playlist.copyWith(
      tracks: [...playlist.tracks, track],
    );
    emit(state.copyWith(playlists: playlists));
    _persist();
  }

  /// Hapus lagu dari playlist
  void removeFromPlaylist(String playlistId, String trackId) {
    final playlists = List<UserPlaylist>.from(state.playlists);
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final playlist = playlists[idx];
    playlists[idx] = playlist.copyWith(
      tracks: playlist.tracks.where((t) => t.id != trackId).toList(),
    );
    emit(state.copyWith(playlists: playlists));
    _persist();
  }

  /// Rename playlist
  void renamePlaylist(String playlistId, String newName) {
    final playlists = List<UserPlaylist>.from(state.playlists);
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    playlists[idx] = playlists[idx].copyWith(name: newName);
    emit(state.copyWith(playlists: playlists));
    _persist();
  }

  /// Hapus riwayat lagu yang baru diputar
  void clearHistory() {
    emit(state.copyWith(recents: const []));
    _persist();
  }

  Timer? _debounceTimer;

  Future<void> _writeToPrefs() {
    final p = _prefs;
    if (p == null) return Future.value();
    return _saveQueue = _saveQueue.then((_) async {
      try {
        await p.setString(_kFavs, _encodeTracks(state.favorites));
        await p.setString(_kRecents, _encodeTracks(state.recents));
        await p.setStringList(_kQueries, state.queries);
        await p.setString(_kCounts, jsonEncode(state.playCounts));
        await p.setString(_kPlaylists, _encodePlaylists(state.playlists));
      } catch (_) {}
    });
  }

  /// Simpan berurutan dan ter-debounce untuk menghemat I/O disk.
  void _persist() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _writeToPrefs();
    });
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _writeToPrefs();
    return super.close();
  }

  /// streamUrl sengaja tidak disimpan: URL YouTube cepat kedaluwarsa,
  /// jadi lebih aman resolve ulang saat diputar.
  static String _encodeTracks(List<Track> tracks) => jsonEncode(tracks.map(_toJson).toList());

  static Map<String, Object?> _toJson(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'artworkUrl': t.artworkUrl,
        'duration': t.duration.inSeconds,
        'genre': t.genre,
        'album': t.album,
        'year': t.year,
      };

  static List<Track> _decodeTracks(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.whereType<Map>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return Track(
          id: '${map['id'] ?? ''}',
          title: '${map['title'] ?? 'Unknown title'}',
          artist: '${map['artist'] ?? 'Unknown artist'}',
          artworkUrl: map['artworkUrl'] as String?,
          duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
          genre: map['genre'] as String?,
          album: map['album'] as String?,
          year: map['year'] as String?,
        );
      }).where((t) => t.id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _encodePlaylists(List<UserPlaylist> playlists) => jsonEncode(
    playlists.map((p) => {
      'id': p.id,
      'name': p.name,
      'tracks': p.tracks.map(_toJson).toList(),
      'createdAt': p.createdAt.millisecondsSinceEpoch,
    }).toList(),
  );

  static List<UserPlaylist> _decodePlaylists(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.whereType<Map>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return UserPlaylist(
          id: '${map['id'] ?? ''}',
          name: '${map['name'] ?? 'Playlist'}',
          tracks: (map['tracks'] as List?)
              ?.whereType<Map>()
              .map((t) {
                final tm = Map<String, dynamic>.from(t);
                return Track(
                  id: '${tm['id'] ?? ''}',
                  title: '${tm['title'] ?? 'Unknown'}',
                  artist: '${tm['artist'] ?? 'Unknown'}',
                  artworkUrl: tm['artworkUrl'] as String?,
                  duration: Duration(seconds: (tm['duration'] as num?)?.toInt() ?? 0),
                  genre: tm['genre'] as String?,
                  album: tm['album'] as String?,
                  year: tm['year'] as String?,
                );
              })
              .where((t) => t.id.isNotEmpty)
              .toList() ?? const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as num?)?.toInt() ?? 0,
          ),
        );
      }).where((p) => p.id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}
