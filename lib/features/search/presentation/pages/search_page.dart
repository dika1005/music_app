import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:music_app/injection.dart';
import 'package:music_app/shared/widgets/loading_states.dart';
import 'package:music_app/shared/widgets/track_tile.dart';
import 'package:music_app/shared/widgets/voice_search_dialog.dart';

class SearchPage extends StatelessWidget {
  final String? initialQuery;
  const SearchPage({super.key, this.initialQuery});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      // Penting: SearchCubit adalah singleton GetIt. Kalau dipakai lewat
      // `BlocProvider(create: ...)`, BlocProvider akan men-close singleton itu
      // saat halaman dilepas (pindah tab) sehingga kunjungan berikutnya mati.
      value: sl<SearchCubit>(),
      child: BlocListener<SearchCubit, SearchState>(
        // Simpan hasil pencarian lagu untuk rekomendasi personalisasi di Home
        listenWhen: (p, c) =>
            c.status == SearchStatus.loaded && !identical(p.results, c.results),
        listener: (context, s) {
          final lib = context.read<LibraryCubit>();
          if (s.results.isNotEmpty) lib.pushSearchResults(s.query, s.results);
        },
        child: _SearchView(initialQuery: initialQuery),
      ),
    );
  }
}

/// Halaman Cari versi ringkas: kotak cari + riwayat pencarian + daftar hasil.
///
/// Blok "Artis Musik" dan "Album Musik Pilihan" dihapus supaya halamannya polos
/// (tanpa kartu artis/album pilihan), jadi user melihat: riwayat -> hasil.
class _SearchView extends StatefulWidget {
  final String? initialQuery;
  const _SearchView({this.initialQuery});

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery ?? '');

  /// Urutan hasil: relevance | title | artist | duration_desc | duration_asc
  String _searchSort = 'relevance';

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery ?? '';
    if (q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _submit(q);
      });
      return;
    }
    // Item 3.2: SearchCubit singleton bertahan antar tab, jadi query terakhir
    // dipulihkan ke kolom pencarian saat halaman dibuka ulang.
    final last = context.read<SearchCubit>().state.query;
    if (last.isNotEmpty) _ctrl.text = last;
  }

  @override
  void didUpdateWidget(covariant _SearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home bisa kirim query baru lewat URL (/search?q=...) saat halaman ini hidup.
    final q = widget.initialQuery ?? '';
    if (q.isNotEmpty && q != oldWidget.initialQuery) {
      _ctrl.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(q);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _sortLabel => switch (_searchSort) {
        'title' => 'Judul',
        'artist' => 'Artis',
        'duration_desc' || 'duration_asc' => 'Durasi',
        _ => 'Relevan',
      };

  List<Track> _applySearchSort(List<Track> raw) {
    final list = List<Track>.from(raw);
    switch (_searchSort) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'artist':
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case 'duration_desc':
        list.sort((a, b) => b.duration.compareTo(a.duration));
      case 'duration_asc':
        list.sort((a, b) => a.duration.compareTo(b.duration));
    }
    return list;
  }

  Future<void> _startVoiceSearch() async {
    HapticFeedback.selectionClick();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const VoiceSearchDialog(),
    );
    if (text != null && text.trim().isNotEmpty) {
      _ctrl.text = text.trim();
      _submit(text.trim());
    }
  }

  void _submit(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    HapticFeedback.selectionClick();
    context.read<LibraryCubit>().pushQuery(query);
    context.read<SearchCubit>().search(query);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Cari',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: _SearchBar(
                controller: _ctrl,
                onSubmit: _submit,
                onMic: _startVoiceSearch,
              ),
            ),
            Expanded(
              child: BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) => _content(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SearchState state) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Saat mengetik: saran lokal dari riwayat (tanpa panggilan jaringan).
    if (state.suggestions.isNotEmpty && state.status != SearchStatus.loaded) {
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: state.suggestions.length,
        itemBuilder: (context, i) => ListTile(
          leading: Icon(Icons.history_rounded, color: scheme.primary),
          title: Text(state.suggestions[i]),
          onTap: () {
            _ctrl.text = state.suggestions[i];
            _submit(state.suggestions[i]);
          },
        ),
      );
    }

    switch (state.status) {
      case SearchStatus.initial:
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: [
            BlocBuilder<LibraryCubit, LibraryState>(
              buildWhen: (p, c) => !identical(p.queries, c.queries),
              builder: (context, lib) {
                if (lib.queries.isEmpty) return const _SearchHint();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pencarian terakhir',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            context.read<LibraryCubit>().clearQueries();
                          },
                          child: const Text('Hapus'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: lib.queries
                          .map(
                            (q) => ActionChip(
                              avatar: const Icon(Icons.history_rounded, size: 16),
                              label: Text(q),
                              side: BorderSide.none,
                              backgroundColor: scheme.surfaceContainerHigh,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              onPressed: () {
                                _ctrl.text = q;
                                _submit(q);
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      case SearchStatus.loading:
        return const SkeletonList(count: 5);
      case SearchStatus.error:
        return ErrorView(
          message: state.message ?? 'Pencarian gagal',
          onRetry: () => _submit(state.query),
        );
      case SearchStatus.empty:
        return EmptyView(message: 'Tidak ketemu "${state.query}". Coba kata lain.');
      case SearchStatus.loaded:
        final results = _applySearchSort(state.results);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${results.length} lagu',
                      style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  PopupMenuButton<String>(
                    color: scheme.surfaceContainerHigh,
                    initialValue: _searchSort,
                    tooltip: 'Urutkan hasil',
                    onSelected: (val) => setState(() => _searchSort = val),
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(
                        value: 'relevance',
                        checked: _searchSort == 'relevance',
                        child: const Text('Paling relevan'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'title',
                        checked: _searchSort == 'title',
                        child: const Text('Judul (A - Z)'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'artist',
                        checked: _searchSort == 'artist',
                        child: const Text('Artis (A - Z)'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'duration_desc',
                        checked: _searchSort == 'duration_desc',
                        child: const Text('Durasi terpanjang'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'duration_asc',
                        checked: _searchSort == 'duration_asc',
                        child: const Text('Durasi terpendek'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sort_rounded, size: 16, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            _sortLabel,
                            style: text.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: results.length,
                itemBuilder: (context, i) =>
                    TrackTile(track: results[i], queue: results, queueIndex: i),
              ),
            ),
          ],
        );
    }
  }

}


/// Kotak pencarian bentuk pill: ikon cari, input, tombol bersihkan, dan mic.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onMic;
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              style: text.bodyLarge?.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Cari lagu, artis, atau album',
                hintStyle: text.bodyMedium?.copyWith(color: scheme.outline),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (q) => context
                  .read<SearchCubit>()
                  .onQueryChanged(q, context.read<LibraryCubit>().state.queries),
              onSubmitted: onSubmit,
            ),
          ),
          BlocBuilder<SearchCubit, SearchState>(
            buildWhen: (p, c) => p.query != c.query,
            builder: (context, s) => s.query.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.clear_rounded, size: 20),
                    color: scheme.onSurfaceVariant,
                    tooltip: 'Bersihkan',
                    onPressed: () {
                      controller.clear();
                      context.read<SearchCubit>().onQueryChanged('', const []);
                    },
                  ),
          ),
          const SizedBox(width: 8),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.mic_rounded, color: scheme.primary, size: 22),
            tooltip: 'Pencarian suara',
            onPressed: onMic,
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

/// Kondisi awal halaman Cari: petunjuk singkat (tanpa kartu artis/album).
class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHigh,
            ),
            child: Icon(Icons.search_rounded, size: 30, color: scheme.primary),
          ),
          const SizedBox(height: 14),
          Text(
            'Cari lagu favoritmu',
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ketik judul lagu, nama artis, atau album.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

