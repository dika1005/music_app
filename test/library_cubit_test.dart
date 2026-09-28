// Personalisasi: play count, top artis, hasil pencarian, album koleksi.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/library/presentation/bloc/library_cubit.dart';
import 'package:music_app/features/player/domain/entities/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _t(String id, String artist, {String? album, String streamUrl = ''}) =>
    Track(id: id, title: 'Lagu $id', artist: artist, album: album, streamUrl: streamUrl);

void main() {
  test('pushRecent menaikkan playCounts dan mostPlayed urut terbanyak', () {
    final cubit = LibraryCubit();
    cubit.pushRecent(_t('1', 'A'));
    cubit.pushRecent(_t('2', 'B'));
    cubit.pushRecent(_t('2', 'B'));

    expect(cubit.state.playCounts['2'], 2);
    expect(cubit.mostPlayed.first.id, '2');
    expect(cubit.state.recents.length, 2, reason: 'tidak ada duplikat di riwayat');
    cubit.close();
  });

  test('topArtists menghitung riwayat lebih berat dari hasil pencarian', () {
    final cubit = LibraryCubit();
    cubit.pushRecent(_t('1', 'Coldplay'));
    cubit.pushSearchResults('pop', [_t('2', 'SZA'), _t('3', 'SZA')]);

    expect(cubit.state.topArtists.first, 'Coldplay');
    expect(cubit.state.topArtists, contains('SZA'));
    cubit.close();
  });

  test('pushSearchResults mengisi tastePool tanpa duplikat', () {
    final cubit = LibraryCubit();
    cubit.pushRecent(_t('1', 'A', album: 'X'));
    cubit.pushSearchResults('mix', [_t('1', 'A', album: 'X'), _t('2', 'B')]);

    expect(cubit.state.lastQuery, 'mix');
    expect(cubit.tasteTracks.map((t) => t.id).toList(), ['1', '2']);
    cubit.close();
  });

  test('pushQuery menyimpan riwayat unik dan terbaru di depan', () {
    final cubit = LibraryCubit();
    cubit.pushQuery('lofi');
    cubit.pushQuery('jazz');
    cubit.pushQuery('LOFI');

    expect(cubit.state.queries, ['LOFI', 'jazz']);
    cubit.close();
  });

  test('restore memuat favorit + riwayat + histogram dari storage', () async {
    SharedPreferences.setMockInitialValues({
      'lib.queries': ['lofi', 'jazz'],
      'lib.playCounts': jsonEncode({'v1': 3}),
      'lib.favorites': jsonEncode([
        {'id': 'v1', 'title': 'Lagu', 'artist': 'Artis', 'album': 'Album', 'duration': 120},
      ]),
      'lib.recents': jsonEncode([
        {'id': 'v2', 'title': 'Lagu 2', 'artist': 'Artis 2', 'artworkUrl': 'http://x/y.jpg'},
      ]),
    });

    final cubit = LibraryCubit();
    await cubit.restore();

    expect(cubit.state.queries, ['lofi', 'jazz']);
    expect(cubit.state.favorites.single.title, 'Lagu');
    expect(cubit.state.favorites.single.album, 'Album');
    expect(cubit.state.recents.single.artworkUrl, 'http://x/y.jpg');
    expect(cubit.state.playCounts['v1'], 3);
    expect(cubit.state.recents.single.duration, Duration.zero);
    cubit.close();
  });

  test('mutasi tersimpan ke storage (tanpa streamUrl)', () async {
    SharedPreferences.setMockInitialValues({});
    final cubit = LibraryCubit();
    await cubit.restore();

    cubit.pushRecent(_t('v9', 'Artis', streamUrl: 'http://audio/expired'));
    cubit.toggleFavorite(_t('v9', 'Artis'));
    cubit.pushQuery('lofi');
    await cubit.saved;

    final prefs = await SharedPreferences.getInstance();
    final recents = jsonDecode(prefs.getString('lib.recents')!) as List;
    expect(recents.first['id'], 'v9');
    expect(recents.first.containsKey('streamUrl'), isFalse);
    expect(prefs.getString('lib.favorites'), contains('v9'));
    expect(prefs.getStringList('lib.queries'), ['lofi']);
    expect(jsonDecode(prefs.getString('lib.playCounts')!)['v9'], 1);
    cubit.close();
  });

  test('custom playlist: buat, tambah lagu, hapus lagu, dan hapus playlist', () async {
    SharedPreferences.setMockInitialValues({});
    final cubit = LibraryCubit();
    await cubit.restore();

    // 1. Buat playlist
    cubit.createPlaylist('Favorit Santai');
    expect(cubit.state.playlists.length, 1);
    expect(cubit.state.playlists.first.name, 'Favorit Santai');
    final plId = cubit.state.playlists.first.id;

    // 2. Tambah lagu ke playlist
    cubit.addToPlaylist(plId, _t('s1', 'Artis 1'));
    cubit.addToPlaylist(plId, _t('s2', 'Artis 2'));
    // Duplikat tidak boleh masuk
    cubit.addToPlaylist(plId, _t('s1', 'Artis 1'));
    expect(cubit.state.playlists.first.tracks.length, 2);

    // 3. Hapus lagu dari playlist
    cubit.removeFromPlaylist(plId, 's1');
    expect(cubit.state.playlists.first.tracks.length, 1);
    expect(cubit.state.playlists.first.tracks.first.id, 's2');

    // 4. Rename playlist
    cubit.renamePlaylist(plId, 'Santai Sore');
    expect(cubit.state.playlists.first.name, 'Santai Sore');

    // 5. Hapus playlist
    cubit.deletePlaylist(plId);
    expect(cubit.state.playlists, isEmpty);
    cubit.close();
  });
}
