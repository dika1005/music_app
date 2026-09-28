import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';

/// Modal bottom sheet untuk menambahkan lagu ke playlist buatan pengguna
void showAddToPlaylistSheet(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => AddToPlaylistSheet(track: track),
  );
}

class AddToPlaylistSheet extends StatefulWidget {
  final Track track;
  const AddToPlaylistSheet({super.key, required this.track});

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  bool _isCreating = false;
  final _createCtrl = TextEditingController();

  @override
  void dispose() {
    _createCtrl.dispose();
    super.dispose();
  }

  void _submitCreate() {
    final name = _createCtrl.text.trim();
    if (name.isEmpty) return;

    final libCubit = context.read<LibraryCubit>();
    final newPl = libCubit.createPlaylist(name);
    libCubit.addToPlaylist(newPl.id, widget.track);

    _createCtrl.clear();
    setState(() => _isCreating = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playlist "${newPl.name}" dibuat & lagu ditambahkan!'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, libState) {
          final playlists = libState.playlists;

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Simpan ke Playlist',
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (!_isCreating)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.primary,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Buat Baru'),
                            onPressed: () => setState(() => _isCreating = true),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Inline Create Playlist Input Card
                  if (_isCreating)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: scheme.primary.withAlpha(100)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _createCtrl,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submitCreate(),
                              decoration: InputDecoration(
                                hintText: 'Nama playlist...',
                                hintStyle: TextStyle(color: scheme.outline),
                                isDense: true,
                                prefixIcon: Icon(Icons.queue_music_rounded, color: scheme.primary, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: scheme.surface,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    _createCtrl.clear();
                                    setState(() => _isCreating = false);
                                  },
                                  child: const Text('Batal'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  onPressed: _submitCreate,
                                  child: const Text('Buat & Tambah'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (playlists.isEmpty && !_isCreating)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                      child: Column(
                        children: [
                          Icon(Icons.queue_music_rounded, size: 40, color: scheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            'Belum ada playlist',
                            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Buat Playlist Pertama'),
                            onPressed: () => setState(() => _isCreating = true),
                          ),
                        ],
                      ),
                    )
                  else
                    ...playlists.map((pl) {
                      final alreadyIn = pl.tracks.any((t) => t.id == widget.track.id);
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: alreadyIn ? scheme.outline : scheme.primary,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          pl.name,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: alreadyIn ? scheme.outline : scheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${pl.tracks.length} lagu${alreadyIn ? ' • Sudah ditambahkan' : ''}',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        trailing: alreadyIn
                            ? Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20)
                            : Icon(Icons.add_circle_outline_rounded, color: scheme.outline, size: 20),
                        enabled: !alreadyIn,
                        onTap: alreadyIn
                            ? null
                            : () {
                                context.read<LibraryCubit>().addToPlaylist(pl.id, widget.track);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Ditambahkan ke "${pl.name}"'),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                      );
                    }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
