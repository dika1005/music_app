import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/core/utils/formatters.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/player/domain/usecases/track_usecases.dart';
import 'package:music_app/features/player/presentation/bloc/player_cubit.dart';
import 'package:music_app/features/player/presentation/bloc/player_state.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/widgets/album_art.dart';

// Lirik di-cache di YtMusicDataSource (memori + disk, item 5.3) supaya tidak
// berulang kali memanggil network DAN tetap ada setelah app dibuka ulang.
// Fungsi ini dipertahankan untuk tombol "Hapus Cache" (lihat cache_sheet.dart).
void clearLyricsCache() {
  try {
    sl<YtMusicDataSource>().clearLyricsCache();
  } catch (_) {}
}

/// Menampilkan Modal Sheet Lirik Sinkron Real-time
void showLyricsModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LyricsModalSheet(),
  );
}

/// Menampilkan Modal Sheet Up Next & Rekomendasi Genre
void showUpNextModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _UpNextModalSheet(),
  );
}

/// Menampilkan Modal Sheet Detail Lagu
void showDetailModal(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DetailModalSheet(track: track),
  );
}

// ==========================================
// 1. MODAL SHEET LIRIK SINKRON
// ==========================================
class _LyricsModalSheet extends StatefulWidget {
  const _LyricsModalSheet();

  @override
  State<_LyricsModalSheet> createState() => _LyricsModalSheetState();
}

class _LyricsModalSheetState extends State<_LyricsModalSheet> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<int> _activeIndexNotifier = ValueNotifier<int>(-1);
  List<_LyricItem> _parsedLyrics = [];

  /// Satu GlobalKey per baris lirik. Dipakai oleh [Scrollable.ensureVisible] agar
  /// posisi scroll dihitung dari geometri NYATA baris (termasuk baris yang wrap
  /// dan baris aktif yang lebih besar) — bukan dari estimasi tinggi tetap.
  final List<GlobalKey> _rowKeys = [];

  /// Re-center yang ditunda saat user sedang menggulir manual.
  Timer? _recenterTimer;

  /// Token request lirik: mencegah respons lagu lama menimpa lirik lagu baru
  /// saat user berpindah lagu cepat.
  int _lyricsRequestId = 0;

  /// Kompensasi latensi output audio Android (~150 ms) + toleransi metadata LRC.
  /// Tanpa ini baris lirik tampil sedikit lebih awal dari suara yang terdengar.
  static const Duration _lyricLatency = Duration(milliseconds: 150);

  /// Jeda sebelum auto-scroll boleh merebut kembali posisi setelah user scroll.
  static const Duration _userFollowPause = Duration(milliseconds: 2500);

  bool _hasSyncedLyrics = false;
  DateTime _lastUserInteraction = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = false;
  String? _loadedLyrics;
  String _currentTrackId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PlayerCubit>().positionNotifier.addListener(_onPositionChanged);
      }
    });
  }

  void _onPositionChanged() {
    if (!mounted) return;
    _syncActivePosition(context.read<PlayerCubit>().position);
  }

  @override
  void dispose() {
    _recenterTimer?.cancel();
    try {
      context.read<PlayerCubit>().positionNotifier.removeListener(_onPositionChanged);
    } catch (_) {}
    _scrollController.dispose();
    _activeIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics(Track track, {bool force = false}) async {
    if (!force && _currentTrackId == track.id && _loadedLyrics != null) return;
    _currentTrackId = track.id;
    final requestId = ++_lyricsRequestId;

    setState(() {
      _loading = true;
      _loadedLyrics = null;
    });

    final res = await sl<GetLyrics>()(title: track.title, artist: track.artist, duration: track.duration);
    // Guard token: kalau user sudah pindah lagu, respons ini sudah basi.
    if (!mounted || requestId != _lyricsRequestId) return;

    if (res.isRight()) {
      final lyricsText = res.getOrElse(() => '');
      if (lyricsText.isNotEmpty && !lyricsText.startsWith('Lirik tidak')) {
        setState(() {
          _loading = false;
          _loadedLyrics = lyricsText;
        });
        _parseLyrics(lyricsText);
        return;
      }
    }

    // Auto-retry sekali langsung tanpa delay buatan (Item 1.6)
    if (!force) {
      if (!mounted || requestId != _lyricsRequestId || _currentTrackId != track.id) return;

      final retryRes = await sl<GetLyrics>()(title: track.title, artist: track.artist, duration: track.duration);
      if (!mounted || requestId != _lyricsRequestId) return;
      if (retryRes.isRight()) {
        final lyricsText = retryRes.getOrElse(() => '');
        if (lyricsText.isNotEmpty && !lyricsText.startsWith('Lirik tidak')) {
          setState(() {
            _loading = false;
            _loadedLyrics = lyricsText;
          });
          _parseLyrics(lyricsText);
          return;
        }
      }
    }

    // Jika tetap gagal, bersihkan parsed lyrics dan jangan simpan kegagalan ke cache
    setState(() {
      _loading = false;
      _loadedLyrics = null;
      _parsedLyrics = [];
      _rowKeys.clear();
      _hasSyncedLyrics = false;
    });
  }

  /// Regex LRC. Dipegang sebagai field statik agar tidak dibuat ulang tiap parse.
  static final RegExp _timeTagAll = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _offsetTag =
      RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
  static final RegExp _metaTag = RegExp(
    r'^\[(ti|ar|al|by|length|re|ve|au|tool|encoding|offset):.*\]$',
    caseSensitive: false,
  );
  static final RegExp _wordTag = RegExp(r'<\d{1,2}:\d{2}(?:[.:]\d{1,3})?>');

  /// Parser lirik LRC yang tahan terhadap bentuk file nyata (LRCLIB/YouTube):
  /// - banyak timestamp dalam satu baris: `[00:12.00][00:24.00]Teks`,
  /// - tag `[offset:±ms]` yang harus menggeser SEMUA timestamp,
  /// - tag metadata (`[ti:]`, `[ar:]`, `[al:]`, `[by:]`, `[length:]`) yang tidak
  ///   boleh ikut tampil sebagai baris lirik di UI,
  /// - tag kata enhanced-LRC `<00:12.34>`, dan
  /// - baris polos tanpa timestamp (lirik non-sinkron) yang tetap ditampilkan.
  ///
  /// Versi lama memakai `lrcRegex.firstMatch` + `group(4)` sehingga tag waktu
  /// kedua ikut tercetak sebagai teks dan `[offset:...]` diabaikan.
  void _parseLyrics(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      setState(() {
        _parsedLyrics = [];
        _rowKeys.clear();
        _hasSyncedLyrics = false;
        _activeIndexNotifier.value = -1;
      });
      return;
    }

    final offsetMs = int.tryParse(_offsetTag.firstMatch(raw)?.group(1) ?? '') ?? 0;
    final items = <_LyricItem>[];
    int syncedCount = 0;

    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _metaTag.hasMatch(trimmed)) continue;

      final matches = _timeTagAll.allMatches(trimmed).toList();
      if (matches.isEmpty) {
        // Baris tanpa timestamp: header bagian ([Chorus]) atau lirik polos.
        // Tag kata enhanced-LRC tetap harus dibersihkan di jalur ini juga.
        final plainText = trimmed.replaceAll(_wordTag, '').trim();
        if (plainText.isEmpty) continue;
        items.add(_LyricItem(
          text: plainText,
          isHeader: plainText.startsWith('[') && plainText.endsWith(']'),
        ));
        continue;
      }

      final text =
          trimmed.replaceAll(_timeTagAll, '').replaceAll(_wordTag, '').trim();
      if (text.isEmpty) continue; // baris instrumen murni → tidak perlu ditampilkan

      for (final match in matches) {
        final fraction = match.group(3);
        final ms = fraction != null
            ? int.parse(fraction.padRight(3, '0').substring(0, 3))
            : 0;
        items.add(_LyricItem(
          time: Duration(
            minutes: int.parse(match.group(1)!),
            seconds: int.parse(match.group(2)!),
            milliseconds: ms,
          ) +
              Duration(milliseconds: offsetMs),
          text: text,
        ));
        syncedCount++;
      }
    }

    // Urutkan berdasarkan waktu (perlu setelah ekspansi multi-timestamp + offset).
    // Baris tanpa waktu (header) mewarisi waktu baris sebelumnya agar posisinya
    // tidak meloncat; indeks asli dipakai sebagai tie-breaker supaya hasilnya
    // deterministik (List.sort Dart tidak stabil).
    final sorted = _sortByTime(items);

    setState(() {
      _parsedLyrics = sorted;
      _rowKeys
        ..clear()
        ..addAll(List.generate(sorted.length, (_) => GlobalKey()));
      _hasSyncedLyrics = syncedCount >= 2;
      _activeIndexNotifier.value = -1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActivePosition(context.read<PlayerCubit>().position, force: true);
    });
  }

  List<_LyricItem> _sortByTime(List<_LyricItem> items) {
    Duration cursor = Duration.zero;
    final entries = <({Duration time, int index, _LyricItem item})>[];
    for (var i = 0; i < items.length; i++) {
      final t = items[i].time;
      if (t != null) cursor = t;
      entries.add((time: cursor, index: i, item: items[i]));
    }
    entries.sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.index.compareTo(b.index);
    });
    return entries.map((e) => e.item).toList();
  }

  void _syncActivePosition(Duration position, {bool force = false}) {
    if (_parsedLyrics.isEmpty || !_hasSyncedLyrics) return;

    // Kompensasi latensi output audio + toleransi LRC.
    final effective = position + _lyricLatency;

    int activeIdx = -1;
    for (int i = 0; i < _parsedLyrics.length; i++) {
      final t = _parsedLyrics[i].time;
      if (t != null && t <= effective) {
        activeIdx = i;
      }
    }
    if (activeIdx < 0) return;

    final changed = activeIdx != _activeIndexNotifier.value;
    if (changed) _activeIndexNotifier.value = activeIdx;
    if (!changed && !force) return;

    // User sedang menggulir manual: jangan rebut scroll-nya, tapi jadwalkan
    // re-center setelah user berhenti. (Dulu tidak ada, jadi fokus ke baris aktif
    // tidak pernah kembali sampai baris berikutnya berganti.)
    if (DateTime.now().difference(_lastUserInteraction) < _userFollowPause) {
      _recenterTimer?.cancel();
      _recenterTimer = Timer(_userFollowPause, () {
        if (mounted && activeIdx < _parsedLyrics.length) _centerOn(activeIdx);
      });
      return;
    }

    _centerOn(activeIdx);
  }

  /// Geser daftar agar baris [index] berada di ~35% tinggi viewport.
  ///
  /// Memakai geometri NYATA hasil layout ([Scrollable.ensureVisible]) sehingga
  /// tidak ada lagi drift "lirik makin ke atas lalu hilang": baris yang wrap,
  /// baris aktif yang font-nya lebih besar, dan header semuanya ikut terhitung.
  /// Versi lama memakai `activeIdx * 54.0 - 100.0` (tinggi baris sebenarnya
  /// hanya ~40 px) sehingga tiap baris menambah galat ~14 px yang menumpuk.
  void _centerOn(int index) {
    if (index < 0 || index >= _rowKeys.length) return;
    final rowContext = _rowKeys[index].currentContext;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      alignment: 0.35,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  /// Satu baris lirik. Dipisah dari builder agar daftar bisa memakai Column
  /// (semua baris ter-build → GlobalKey selalu resolve untuk ensureVisible).
  Widget _buildLyricRow(int index, PlayerCubit cubit) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final item = _parsedLyrics[index];

    if (item.isHeader) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          item.text,
          style: text.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: _activeIndexNotifier,
      builder: (context, activeIdx, _) {
        final isActive = _hasSyncedLyrics && index == activeIdx;
        return InkWell(
          onTap: item.time != null
              ? () {
                  cubit.seek(item.time!);
                  _lastUserInteraction = DateTime.fromMillisecondsSinceEpoch(0);
                  _recenterTimer?.cancel();
                  _activeIndexNotifier.value = index;
                  // Pakai geometri nyata, bukan lagi `i * 52.0 - 120.0`.
                  _centerOn(index);
                }
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: isActive
                  ? TextStyle(
                      color: scheme.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                    )
                  : TextStyle(
                      color: _hasSyncedLyrics
                          ? scheme.onSurface.withAlpha(90)
                          : scheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
              child: Text(item.text),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.current?.id != curr.current?.id || prev.status != curr.status,
      builder: (context, state) {
        final track = state.current;
        if (track == null) return const SizedBox.shrink();

        // Trigger fetch if not yet started
        if (_currentTrackId != track.id && !_loading && _loadedLyrics == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLyrics(track));
        }

        final cubit = context.read<PlayerCubit>();
        final playing = state.status == PlayerStatus.playing;

        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withAlpha(120),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'LIRIK SINKRON',
                                style: text.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (_hasSyncedLyrics) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'LRC REAL-TIME',
                                    style: text.labelSmall?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.title,
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Lyrics List Area
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: scheme.primary),
                            const SizedBox(height: 16),
                            Text('Mencari & menyinkronkan lirik...', style: text.bodyMedium),
                          ],
                        ),
                      )
                    : _parsedLyrics.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.music_off_rounded, size: 48, color: scheme.outline),
                                const SizedBox(height: 12),
                                Text('Lirik tidak tersedia', style: text.titleSmall),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => _fetchLyrics(track, force: true),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          )
                        : NotificationListener<UserScrollNotification>(
                            onNotification: (notif) {
                              if (notif.direction != ScrollDirection.idle) {
                                _lastUserInteraction = DateTime.now();
                              }
                              return false;
                            },
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Semua baris dibangun eagerly (lirik biasanya < 200
                                  // baris) supaya setiap GlobalKey punya BuildContext →
                                  // ensureVisible selalu presisi, termasuk saat melompat
                                  // jauh karena tap/seek. Inilah yang menghapus drift
                                  // lama: tinggi baris diukur, bukan diasumsikan.
                                  for (var i = 0; i < _parsedLyrics.length; i++)
                                    KeyedSubtree(
                                      key: _rowKeys[i],
                                      child: _buildLyricRow(i, cubit),
                                    ),
                                ],
                              ),
                            ),
                          ),
              ),

              // Bottom mini-player bar inside lyrics sheet (isolated scrubber)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  border: Border(top: BorderSide(color: scheme.outlineVariant.withAlpha(60))),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: cubit.previous,
                    ),
                    IconButton(
                      icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                      iconSize: 42,
                      color: scheme.primary,
                      onPressed: cubit.toggle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: cubit.next,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueListenableBuilder<PositionData>(
                        valueListenable: cubit.positionNotifier,
                        builder: (context, pos, _) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                  activeTrackColor: scheme.primary,
                                  thumbColor: scheme.primary,
                                ),
                                child: Slider(
                                  value: pos.progress,
                                  onChanged: (v) => cubit.seek(pos.duration * v),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(formatDuration(pos.position), style: text.labelSmall),
                                  Text(formatDuration(pos.duration), style: text.labelSmall),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 2. MODAL SHEET UP NEXT & GENRE RECOMMS
// ==========================================
class _UpNextModalSheet extends StatelessWidget {
  const _UpNextModalSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return BlocBuilder<PlayerCubit, PlayerState>(
      buildWhen: (prev, curr) =>
          prev.current?.id != curr.current?.id ||
          prev.index != curr.index ||
          prev.queue != curr.queue ||
          prev.upNext != curr.upNext ||
          prev.status != curr.status,
      builder: (context, state) {
        final current = state.current;
        final cubit = context.read<PlayerCubit>();
        final currentTitle = current?.title.toLowerCase() ?? '';
        final currentArtist = current?.artist.toLowerCase() ?? '';

        // Remaining queue
        final remainingQueue = <Track>[];
        if (state.index >= 0 && state.index < state.queue.length - 1) {
          remainingQueue.addAll(state.queue.sublist(state.index + 1));
        }

        // Filter and ensure diverse genre recommendations without same-title covers
        final seen = <String>{};
        for (final t in state.queue) {
          seen.add(t.id);
        }

        final filteredRecomms = <Track>[];
        for (final t in state.upNext) {
          if (seen.contains(t.id)) continue;
          if (t.title.toLowerCase() == currentTitle) continue;
          if (t.artist.toLowerCase() == currentArtist && isSimilarTitle(t.title, current?.title ?? '')) {
            continue;
          }
          if (seen.add(t.id)) filteredRecomms.add(t);
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withAlpha(120),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DAFTAR PUTAR & UP NEXT',
                            style: text.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rekomendasi Acak Genre Serupa',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Sedang Diputar
                    if (current != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(
                          'SEDANG DIPUTAR',
                          style: text.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AlbumArt(url: current.artworkUrl, size: 50, radius: 8),
                        ),
                        title: Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                        subtitle: Text(
                          current.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Antrean Berikutnya
                    if (remainingQueue.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(
                          'BERIKUTNYA DALAM ANTREAN (${remainingQueue.length})',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      Theme(
                        data: Theme.of(context).copyWith(
                          canvasColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: remainingQueue.length,
                          onReorderItem: (oldIdx, newIdx) {
                            final actualOld = state.index + 1 + oldIdx;
                            final actualNew = state.index + 1 + newIdx;
                            cubit.reorderQueue(actualOld, actualNew);
                          },
                          itemBuilder: (context, idx) {
                            final t = remainingQueue[idx];
                            final trackIndexInQueue = state.index + 1 + idx;
                            return Dismissible(
                              key: ValueKey('queue-${t.id}-$trackIndexInQueue'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: scheme.errorContainer,
                                child: Icon(Icons.delete_outline_rounded, color: scheme.error),
                              ),
                              onDismissed: (_) {
                                cubit.removeFromQueue(trackIndexInQueue);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Dihapus dari antrean: ${t.title}'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AlbumArt(url: t.artworkUrl, size: 44, radius: 8),
                                ),
                                title: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.close_rounded, size: 18, color: scheme.outline),
                                      tooltip: 'Hapus dari antrean',
                                      onPressed: () => cubit.removeFromQueue(trackIndexInQueue),
                                    ),
                                    ReorderableDragStartListener(
                                      index: idx,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Icon(Icons.drag_handle_rounded, size: 20, color: scheme.outline),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => cubit.playQueue(state.queue, trackIndexInQueue),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Rekomendasi Genre Terkait
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Row(
                        children: [
                          Text(
                            'REKOMENDASI GENRE TERKAIT',
                            style: text.labelSmall?.copyWith(
                              color: scheme.secondary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Acak & Beragam',
                            style: text.labelSmall?.copyWith(color: scheme.outline),
                          ),
                        ],
                      ),
                    ),

                    if (filteredRecomms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Sedang menyiapkan rekomendasi genre serupa...',
                            style: text.bodySmall?.copyWith(color: scheme.outline),
                          ),
                        ),
                      )
                    else
                      ...filteredRecomms.map((t) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AlbumArt(url: t.artworkUrl, size: 44, radius: 8),
                            ),
                            title: Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: Icon(Icons.playlist_add_rounded, color: scheme.primary),
                              tooltip: 'Tambah ke antrean',
                              onPressed: () {
                                cubit.playUpNext(t);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Ditambahkan ke antrean: ${t.title}'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                            onTap: () async {
                              // Sisipkan tepat setelah lagu aktif lalu lompat ke
                              // sana. Sebelumnya memakai
                              // playQueue([...queue, t], queue.length) yang
                              // membangun ulang seluruh playlist ExoPlayer
                              // (audio terputus + media session/notifikasi reset).
                              await cubit.playUpNext(t);
                              await cubit.next();
                            },
                          )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ==========================================
// 3. MODAL SHEET DETAIL LAGU
// ==========================================
class _DetailModalSheet extends StatelessWidget {
  final Track track;
  const _DetailModalSheet({required this.track});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final rows = <List<String>>[
      ['Judul Lagu', track.title],
      ['Artis', track.artist],
      if (track.album != null && track.album!.isNotEmpty) ['Album', track.album!],
      if (track.year != null && track.year!.isNotEmpty) ['Tahun Rilis', track.year!],
      ['Durasi', formatDuration(track.duration)],
      ['ID YouTube', track.id],
      ['Format Audio', 'Opus / AAC High Bitrate (160 kbps)'],
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.60,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Detail Lagu',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Info Rows
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 20),
              itemBuilder: (context, i) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      rows[i][0],
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      rows[i][1],
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TABS KEBERLANJUTAN (Compatibility)
// ==========================================
class _LyricItem {
  final Duration? time;
  final String text;
  final bool isHeader;

  const _LyricItem({this.time, required this.text, this.isHeader = false});
}

class UpNextTab extends StatelessWidget {
  final List<Track> queue;
  final int index;
  final List<Track> upNext;
  const UpNextTab({super.key, required this.queue, required this.index, required this.upNext});

  @override
  Widget build(BuildContext context) => const _UpNextModalSheet();
}

class LyricsTab extends StatelessWidget {
  final bool busy;
  final String? lyrics;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback onLoad;

  const LyricsTab({
    super.key,
    required this.busy,
    required this.lyrics,
    required this.position,
    this.onSeek,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) => const _LyricsModalSheet();
}

class DetailTab extends StatelessWidget {
  final Track track;
  const DetailTab({super.key, required this.track});

  @override
  Widget build(BuildContext context) => _DetailModalSheet(track: track);
}
