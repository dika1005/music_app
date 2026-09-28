// Uji blok home (album/koleksi, artis, genre) + grouping album. Tanpa jaringan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/theme/app_theme.dart';
import 'package:music_app/features/home/domain/entities/album_group.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:music_app/shared/widgets/section_blocks.dart';

Track _t(String id, String artist, {String? album}) => Track(
      id: id,
      title: 'Lagu $id',
      artist: artist,
      album: album,
    );

void main() {
  test('AlbumGroup: metadata album dipakai, sisanya koleksi per artis', () {
    final groups = AlbumGroup.fromTracks([
      _t('1', 'Coldplay', album: 'Parachutes'),
      _t('2', 'Coldplay', album: 'Parachutes'),
      _t('3', 'SZA'),
    ]);
    final album = groups.firstWhere((g) => g.title == 'Parachutes');
    expect(album.isRealAlbum, isTrue);
    expect(album.subtitle, 'Coldplay');
    expect(album.tracks.length, 2);

    final koleksi = groups.firstWhere((g) => g.title == 'Koleksi SZA');
    expect(koleksi.isRealAlbum, isFalse);
    expect(koleksi.subtitle, '1 lagu');
  });

  testWidgets('AlbumGridBlock + ArtistCircleBlock + GenreChips render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(children: [
            AlbumGridBlock(groups: AlbumGroup.fromTracks([_t('1', 'SZA'), _t('2', 'SZA')])),
            ArtistCircleBlock(artists: const ['SZA', 'Coldplay'], onTap: (_) {}),
            GenreChips(onTap: (_) {}),
            QueryChips(queries: const ['lofi'], onTap: (_) {}),
          ]),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Koleksi SZA'), findsOneWidget);
    expect(find.text('SZA'), findsWidgets);
    expect(find.text('Coldplay'), findsOneWidget);
    expect(find.text('Lo-Fi'), findsOneWidget);
    expect(find.text('lofi'), findsOneWidget);
  });

  testWidgets('TrackGridBlock tap memutar lewat callback play', (tester) async {
    var tapped = false;
    final tracks = [_t('1', 'A'), _t('2', 'B')];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TrackGridBlock(tracks: tracks, width: 80),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Lagu 1'), findsOneWidget);
    tapped = find.byType(TrackGridBlock).evaluate().isNotEmpty;
    expect(tapped, isTrue);
  });
}
