import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

/// Sumber data tunggal YouTube Music menggunakan yt_flutter_musicapi
/// (Kotlin + Python Chaquopy backend: ytmusicapi + yt-dlp).
/// Menangani pencarian, trending/charts, pemutaran (audioUrl), antrean (related), dan lirik.
class YtMusicDataSource {
  final YtFlutterMusicapi api;
  bool _initDone = false;

  /// In-memory cache untuk URL streaming audio
  final Map<String, String> _audioUrlCache = {};

  /// Timestamps for cache entries (for 24h TTL)
  final Map<String, DateTime> _audioUrlCacheTimes = {};

  /// In-flight requests agar request ganda untuk video yang sama tidak menduplikasi beban
  final Map<String, Future<String>> _inFlightAudioUrls = {};

  /// In-memory cache untuk trending charts per negara
  final Map<String, List<Track>> _chartsCache = {};
  final Map<String, DateTime> _chartsCacheTimes = {};
  final Map<String, String> _lyricsMemoryCache = {};

  /// Cache lirik persisten (item 5.3): lirik yang sudah pernah diunduh tidak
  /// perlu request ulang setelah app ditutup / pindah device restart.
  static const String _lyricsPrefsKey = 'lyrics.cache.v1';
  static const int _lyricsDiskLimit = 80; // ~80 lagu, hemat SharedPreferences
  Map<String, String>? _lyricsDiskCache;
  bool _lyricsDiskLoaded = false;
  Future<void>? _lyricsDiskLoading;

  /// Cache TTL audio URL: 4 jam (URL CDN YouTube valid ~6 jam)
  static const _cacheTtl = Duration(hours: 4);

  /// Shared HttpClient untuk reuse connection pool, DNS, dan TLS keep-alive
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 30);

  int get cachedAudioCount => _audioUrlCache.length;
  int get cachedChartsCount => _chartsCache.length;

  void invalidateAudioUrl(String videoId) {
    _audioUrlCache.remove(videoId);
    _audioUrlCacheTimes.remove(videoId);
  }

  /// Bersihkan cache lirik (memori + disk). Dipakai tombol "Hapus Cache".
  void clearLyricsCache() {
    _lyricsMemoryCache.clear();
    _clearLyricsDiskCache();
  }

  void clearAllCache() {
    _audioUrlCache.clear();
    _audioUrlCacheTimes.clear();
    _chartsCache.clear();
    _chartsCacheTimes.clear();
    _lyricsMemoryCache.clear();
    _inFlightAudioUrls.clear();
    _clearLyricsDiskCache();
  }

  void dispose() {
    _httpClient.close(force: true);
    clearAllCache();
  }

  YtMusicDataSource(this.api);

  // ---- Lirik: cache memori + disk (item 5.3) ------------------------------

  /// Muat cache lirik dari disk sekali saja (lazy, hasilnya di-merge ke memori).
  Future<void> _ensureLyricsDiskLoaded() async {
    if (_lyricsDiskLoaded) return;
    return _lyricsDiskLoading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_lyricsPrefsKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = <String, String>{};
            decoded.forEach((k, v) {
              if (v is String && v.isNotEmpty) map[k.toString()] = v;
            });
            _lyricsDiskCache = map;
            for (final e in map.entries) {
              _lyricsMemoryCache.putIfAbsent(e.key, () => e.value);
            }
          }
        }
      } catch (e) {
        debugPrint('Lyrics disk cache load error: $e');
      } finally {
        _lyricsDiskLoaded = true;
        _lyricsDiskLoading = null;
      }
    }();
  }

  /// Simpan lirik ke disk (write-through, dibatasi [_lyricsDiskLimit] lagu).
  Future<void> _persistLyrics(String cacheKey, String text) async {
    try {
      await _ensureLyricsDiskLoaded();
      final cache = _lyricsDiskCache ??= <String, String>{};
      cache[cacheKey] = text;
      // Map menjaga urutan insert → buang yang paling lama saat kepenuhan.
      while (cache.length > _lyricsDiskLimit) {
        cache.remove(cache.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lyricsPrefsKey, jsonEncode(cache));
    } catch (e) {
      debugPrint('Lyrics disk cache save error: $e');
    }
  }

  void _rememberLyrics(String cacheKey, String text) {
    _lyricsMemoryCache[cacheKey] = text;
    unawaited(_persistLyrics(cacheKey, text));
  }

  void _clearLyricsDiskCache() {
    _lyricsDiskCache = null;
    _lyricsDiskLoaded = false;
    _lyricsDiskLoading = null;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_lyricsPrefsKey);
      } catch (_) {}
    }());
  }

  Future<void>? _initFuture;

  Future<void> ensureInit() {
    if (_initDone || api.isInitialized) {
      _initDone = true;
      return Future.value();
    }
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      final res = await api.initialize(country: 'ID');
      if (!res.success) {
        debugPrint('YtMusicDataSource init: ${res.error ?? res.message}');
      }
      _initDone = true;
    } catch (e) {
      debugPrint('YtMusicDataSource initialize error: $e');
    } finally {
      _initFuture = null;
    }
  }

  /// Ambil tangga lagu / trending dari YouTube Music
  Future<List<Track>> charts({int limit = 20, String country = 'ID'}) async {
    // Return cache jika ada dan belum kadaluarsa (24 jam)
    if (_chartsCache.containsKey(country) && _chartsCache[country]!.isNotEmpty) {
      final cachedAt = _chartsCacheTimes[country];
      if (cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl) {
        return _chartsCache[country]!;
      } else {
        _chartsCache.remove(country);
        _chartsCacheTimes.remove(country);
      }
    }

    await ensureInit();
    try {
      final res = await api.getCharts(
        limit: limit,
        country: country,
        audioQuality: AudioQuality.high,
        thumbQuality: ThumbnailQuality.veryHigh,
        includeAudioUrl: false,
        includeAlbumArt: true,
      );

      if (res.success && res.data != null && res.data!.isNotEmpty) {
        final list = res.data!.map((item) {
          return Track(
            id: item.videoId,
            title: item.title,
            artist: item.artists,
            streamUrl: item.audioUrl ?? '',
            artworkUrl: item.albumArt,
            duration: _parseDuration(item.duration),
            genre: item.chartType.isNotEmpty ? item.chartType : 'Trending',
          );
        }).where((t) => t.id.isNotEmpty).toList();

        if (list.isNotEmpty) {
          _chartsCache[country] = list;
          _chartsCacheTimes[country] = DateTime.now();
          return list;
        }
      }
    } catch (e) {
      debugPrint('getCharts failed: $e, falling back to search');
    }

    // Fallback otomatis jika charts kosong atau gagal
    try {
      final fallback = await search('Top Hits Indonesia', limit: limit);
      if (fallback.isNotEmpty) {
        _chartsCache[country] = fallback;
        _chartsCacheTimes[country] = DateTime.now();
        return fallback;
      }
    } catch (e) {
      debugPrint('Top Hits fallback failed: $e');
    }
    return [];
  }

  /// Pencarian lagu di YouTube Music - menyaring video kompilasi/mix panjang
  Future<List<Track>> search(String query, {int limit = 20}) async {
    await ensureInit();
    final res = await api.searchMusic(
      query: query,
      limit: limit + 5, // ambil cadangan untuk filter
      audioQuality: AudioQuality.veryHigh,
      thumbQuality: ThumbnailQuality.veryHigh,
      includeAudioUrl: false,
      includeAlbumArt: true,
      useCache: false,
    );

    if (!res.success || res.data == null) {
      if (res.error != null && res.error!.isNotEmpty) {
        throw Exception(res.error);
      }
      return [];
    }

    final tracks = res.data!.map((item) {
      return Track(
        id: item.videoId,
        title: item.title,
        artist: item.artists,
        streamUrl: item.audioUrl ?? '',
        artworkUrl: item.albumArt,
        duration: _parseDuration(item.duration),
        year: item.year,
      );
    }).where((t) {
      if (t.id.isEmpty) return false;
      // Saring kompilasi campuran panjang (> 10 menit) agar hasil murni lagu satuan yang relevan
      if (t.duration.inSeconds > 600) return false;
      final lowerTitle = t.title.toLowerCase();
      if (lowerTitle.contains('full album') ||
          lowerTitle.contains('nonstop') ||
          lowerTitle.contains('compilation') ||
          lowerTitle.contains('1 hour') ||
          lowerTitle.contains('1 jam') ||
          lowerTitle.contains('kumpulan lagu')) {
        return false;
      }
      return true;
    }).take(limit).toList();

    return tracks;
  }

  /// Rekomendasi lagu terkait untuk antrean putar (up next)
  Future<List<Track>> related(Track track, {int limit = 10}) async {
    await ensureInit();
    final res = await api.getRelatedSongs(
      songName: track.title,
      artistName: track.artist,
      limit: limit,
      audioQuality: AudioQuality.veryHigh,
      thumbQuality: ThumbnailQuality.veryHigh,
      includeAudioUrl: false,
      includeAlbumArt: true,
    );

    if (!res.success || res.data == null) {
      return [];
    }

    return res.data!.map((item) {
      return Track(
        id: item.videoId,
        title: item.title,
        artist: item.artists,
        streamUrl: item.audioUrl ?? '',
        artworkUrl: item.albumArt,
        duration: _parseDuration(item.duration),
      );
    }).where((t) => t.id.isNotEmpty && t.duration.inSeconds <= 600).toList();
  }

  /// Ambil URL audio streaming secara langsung dan cepat dengan memory cache & request deduplication
  Future<String> audioUrl(String videoId, {String? title, String? artist}) async {
    // 1. Periksa memory cache (dengan TTL 24 jam)
    final cached = _audioUrlCache[videoId];
    final cachedAt = _audioUrlCacheTimes[videoId];
    if (cached != null && cached.isNotEmpty) {
      if (cachedAt == null || DateTime.now().difference(cachedAt) < _cacheTtl) {
        return cached;
      } else {
        _audioUrlCache.remove(videoId);
        _audioUrlCacheTimes.remove(videoId);
      }
    }

    // 2. Request deduplication: jika sudah ada request berjalan untuk videoId ini, tunggu hasilnya
    if (_inFlightAudioUrls.containsKey(videoId)) {
      return await _inFlightAudioUrls[videoId]!;
    }

    final future = _fetchAudioUrl(videoId, title: title, artist: artist);
    _inFlightAudioUrls[videoId] = future;
    try {
      final url = await future;
      _audioUrlCache[videoId] = url;
      _audioUrlCacheTimes[videoId] = DateTime.now();
      return url;
    } finally {
      _inFlightAudioUrls.remove(videoId);
    }
  }

  Future<String> _fetchAudioUrl(String videoId, {String? title, String? artist}) async {
    await ensureInit();

    // 1. Coba getAudioUrlFast
    try {
      final res = await api.getAudioUrlFast(videoId: videoId);
      final url = res.data;
      if (res.success && url != null && url.isNotEmpty) {
        return url;
      }
    } catch (e) {
      debugPrint('Fast audio URL failed, trying flexible: $e');
    }

    // 2. Fallback internal ke getAudioUrlFlexible dari yt_flutter_musicapi
    final flex = await api.getAudioUrlFlexible(
      videoId: videoId,
      title: title,
      artist: artist,
      audioQuality: AudioQuality.high,
    );
    if (flex.success && flex.data?.audioUrl != null && flex.data!.audioUrl!.isNotEmpty) {
      return flex.data!.audioUrl!;
    }

    throw Exception(flex.error ?? 'Gagal mendapatkan URL audio untuk video $videoId');
  }

  /// Ambil lirik lagu — prioritaskan lirik tersinkronisasi (LRC) dari LRCLIB,
  /// dengan multi-fallback ke YouTube Music API dan OVH open lyrics.
  ///
  /// [duration] (opsional) dipakai memvalidasi hasil LRCLIB: lirik dari versi
  /// lain (radio edit / remix / live) punya durasi berbeda, dan kalau dipakai
  /// akan selalu geser beberapa detik dari audio yang diputar.
  ///
  /// Sumber dijalankan **paralel** dalam dua gelombang (LRCLIB dulu, lalu
  /// YTMusic + OVH). Versi lama memanggil 4 sumber berurutan dengan timeout
  /// 6/6/5 detik sehingga worst case >20 detik.
  Future<String> lyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _cleanSongTitle(title);
    final cleanArtist = _cleanArtistName(artist);
    // Bucket durasi per 5 detik (sinkron dengan toleransi validasi LRCLIB):
    // versi lain (radio edit / remix / live) tidak boleh memakai cache silang.
    final durationBucket = duration == null || duration == Duration.zero
        ? 0
        : duration.inSeconds ~/ 5;
    final cacheKey =
        '${cleanTitle.toLowerCase()}_${cleanArtist.toLowerCase()}_$durationBucket';

    // 0. Periksa memory cache lokal
    final cached = _lyricsMemoryCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // 0b. Cache disk: lirik yang pernah diunduh di sesi sebelumnya (item 5.3)
    await _ensureLyricsDiskLoaded();
    final fromDisk = _lyricsDiskCache?[cacheKey];
    if (fromDisk != null && fromDisk.isNotEmpty) {
      _lyricsMemoryCache[cacheKey] = fromDisk;
      return fromDisk;
    }

    // 1. LRCLIB (exact + search) paralel — sumber terbaik untuk LRC.
    final lrclib = await Future.wait<String?>([
      _safely(_fetchLrclibExact(cleanTitle, cleanArtist,
          expectedDuration: duration)),
      _safely(_fetchLrclibSearch(cleanTitle, cleanArtist,
          expectedDuration: duration)),
    ]);
    final fromLrclib = lrclib.firstWhere(
      (t) => t != null && t.isNotEmpty,
      orElse: () => null,
    );
    if (fromLrclib != null) {
      _rememberLyrics(cacheKey, fromLrclib);
      return fromLrclib;
    }

    // 2. Fallback lain (YouTube Music API + OVH) juga paralel.
    final fallbacks = await Future.wait<String?>([
      _safely(_ytMusicLyrics(cleanTitle, cleanArtist)),
      _safely(_fetchOvhLyrics(cleanTitle, cleanArtist)),
    ]);
    final fromFallback = fallbacks.firstWhere(
      (t) => t != null && t.isNotEmpty,
      orElse: () => null,
    );
    if (fromFallback != null) {
      _rememberLyrics(cacheKey, fromFallback);
      return fromFallback;
    }

    // 3. Terakhir: YouTube Music API dengan judul & artis mentah.
    final raw = await _safely(_ytMusicLyrics(title, artist));
    if (raw != null && raw.isNotEmpty) {
      _rememberLyrics(cacheKey, raw);
      return raw;
    }

    throw Exception('Lirik tidak ditemukan untuk $title');
  }

  /// Menjalankan pencarian opsional: kegagalan satu sumber tidak membatalkan
  /// sumber lain yang berjalan paralel.
  Future<String?> _safely(Future<String?> task) async {
    try {
      return await task;
    } catch (e) {
      debugPrint('Lyrics source error: $e');
      return null;
    }
  }

  Future<String?> _ytMusicLyrics(String songName, String artistName) async {
    await ensureInit();
    final res = await api.fetchLyrics(songName: songName, artistName: artistName);
    final text = res.data?.text ?? '';
    return text.isEmpty ? null : text;
  }

  /// Pencarian "exact" LRCLIB. Bila durasi lagu diketahui, permintaan pertama
  /// menyertakan `duration` (LRCLIB menolak bila tidak cocok) supaya lirik dari
  /// versi lain tidak terpakai; kalau kosong, baru coba tanpa durasi.
  Future<String?> _fetchLrclibExact(
    String cleanTitle,
    String cleanArtist, {
    Duration? expectedDuration,
  }) async {
    final base =
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanArtist)}'
        '&track_name=${Uri.encodeComponent(cleanTitle)}';
    final seconds = (expectedDuration == null || expectedDuration == Duration.zero)
        ? null
        : expectedDuration.inSeconds;

    if (seconds != null) {
      final strict = await _lrclibGet('$base&duration=$seconds');
      if (strict != null) return strict;
    }
    return _lrclibGet(base);
  }

  Future<String?> _lrclibGet(String url) async {
    final request = await _httpClient.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'MelodyFlow/1.0');
    final response = await request.close().timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final synced = json['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) {
      return synced;
    }
    final plain = json['plainLyrics'] as String?;
    if (plain != null && plain.trim().isNotEmpty) {
      return plain;
    }
    return null;
  }

  /// Cari di LRCLIB. Bila [expectedDuration] diketahui, hanya kandidat dengan
  /// durasi ±5 detik yang dipakai supaya lirik tidak geser dari audio yang
  /// diputar (dulu: kandidat pertama ber-syncedLyrics diambil apa adanya).
  Future<String?> _fetchLrclibSearch(
    String cleanTitle,
    String cleanArtist, {
    Duration? expectedDuration,
  }) async {
    final query = '$cleanTitle $cleanArtist'.trim();
    final uri = Uri.parse(
      'https://lrclib.net/api/search?q=${Uri.encodeComponent(query)}',
    );
    final request = await _httpClient.getUrl(uri);
    request.headers.set('User-Agent', 'MelodyFlow/1.0');
    final response = await request.close().timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    final list = jsonDecode(body);
    if (list is! List || list.isEmpty) return null;

    final candidates = list.whereType<Map<String, dynamic>>().toList();
    final expected =
        (expectedDuration == null || expectedDuration == Duration.zero)
            ? null
            : expectedDuration.inSeconds;

    bool durationMatches(Map<String, dynamic> item) {
      if (expected == null) return true;
      final raw = item['duration'];
      if (raw is! num) return false;
      return (raw.toInt() - expected).abs() <= 5;
    }

    // 1. Prioritaskan yang punya lirik tersinkronisasi & durasinya cocok.
    for (final item in candidates) {
      if (!durationMatches(item)) continue;
      final synced = item['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) return synced;
    }

    // 2. Tanpa durasi yang diketahui, lirik biasa boleh dipakai apa adanya.
    //    Kalau durasi diketahui tapi tidak ada yang cocok, lebih baik tidak ada
    //    lirik sama sekali daripada lirik versi lain yang selalu geser.
    if (expected != null) return null;
    for (final item in candidates) {
      final plain = item['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) return plain;
    }
    return null;
  }

  Future<String?> _fetchOvhLyrics(String cleanTitle, String cleanArtist) async {
    final uri = Uri.parse(
      'https://api.lyrics.ovh/v1/${Uri.encodeComponent(cleanArtist)}/${Uri.encodeComponent(cleanTitle)}',
    );
    final request = await _httpClient.getUrl(uri);
    request.headers.set('User-Agent', 'MelodyFlow/1.0');
    final response = await request.close().timeout(const Duration(seconds: 4));
    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final lyrics = json['lyrics'] as String?;
      if (lyrics != null && lyrics.trim().isNotEmpty) {
        return lyrics.trim();
      }
    }
    return null;
  }

  String _cleanSongTitle(String title) {
    var t = title;
    // Hapus pola "Artis - Judul" jika nama artis terulang di judul
    if (t.contains(' - ')) {
      final parts = t.split(' - ');
      if (parts.length >= 2 && parts.last.trim().isNotEmpty) {
        t = parts.last.trim();
      }
    }
    return t
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(
          RegExp(
            r'\(.*?(official|video|audio|mv|remix|lyric|lyrics|lirik|feat|ft|visualizer|live|clip|klip|4k|hd).*?\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\|.*$'), '')
        .replaceAll(RegExp(r'#.*$'), '')
        .replaceAll(RegExp(r'["“”]'), '')
        .trim();
  }

  String _cleanArtistName(String artist) {
    return artist
        .replaceAll(RegExp(r' - Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r',.*$'), '')
        .replaceAll(RegExp(r'\s*(&|feat\.?|ft\.?)\s*.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'["“”]'), '')
        .trim();
  }

  /// Ambil lagu-lagu berdasarkan artis
  Future<List<Track>> artistSongs(String artist, {int limit = 25}) async {
    await ensureInit();
    final res = await api.getArtistSongs(
      artistName: artist,
      limit: limit,
      audioQuality: AudioQuality.high,
      thumbQuality: ThumbnailQuality.veryHigh,
      includeAudioUrl: false,
      includeAlbumArt: true,
    );

    if (!res.success || res.data == null) {
      return [];
    }

    return res.data!.map((item) {
      return Track(
        id: item.videoId,
        title: item.title,
        artist: item.artistName.isNotEmpty ? item.artistName : item.artists,
        streamUrl: item.audioUrl ?? '',
        artworkUrl: item.albumArt,
        duration: _parseDuration(item.duration),
      );
    }).where((t) => t.id.isNotEmpty && t.duration.inSeconds <= 600).toList();
  }

  /// Hapus semua cache yang sudah kadaluarsa (> 24 jam)
  void clearExpiredCache() {
    final now = DateTime.now();
    _audioUrlCache.removeWhere((id, _) {
      final t = _audioUrlCacheTimes[id];
      if (t == null) return false;
      return now.difference(t) > _cacheTtl;
    });
    _audioUrlCacheTimes.removeWhere((id, t) => now.difference(t) > _cacheTtl);
    _chartsCache.removeWhere((c, _) {
      final t = _chartsCacheTimes[c];
      if (t == null) return false;
      return now.difference(t) > _cacheTtl;
    });
    _chartsCacheTimes.removeWhere((c, t) => now.difference(t) > _cacheTtl);
  }
}

Duration _parseDuration(dynamic raw) {
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
