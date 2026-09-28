// Uji live YtMusicDataSource dengan YtFlutterMusicapi.
// Dinonaktifkan secara default untuk CI tanpa Android emulator.
// Jalankan manual: LIVE=1 flutter test test/live_probe_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/features/player/data/datasources/yt_music_datasource.dart';
import 'package:yt_flutter_musicapi/yt_flutter_musicapi.dart';

final bool _live = Platform.environment['LIVE'] == '1';

void main() {
  test('yt_flutter_musicapi: search/charts/audio', () async {
    final api = YtFlutterMusicapi();
    final ds = YtMusicDataSource(api);

    final s = await ds.search('coldplay', limit: 5);
    // ignore: avoid_print
    print('SEARCH n=${s.length} | ${s.isEmpty ? '-' : s.first.title} | ${s.isEmpty ? '-' : s.first.artworkUrl}');
    expect(s, isNotEmpty);

    final t = await ds.charts(limit: 5);
    // ignore: avoid_print
    print('CHARTS n=${t.length} | ${t.isEmpty ? '-' : t.first.title}');
    expect(t, isNotEmpty);

    final url = await ds.audioUrl('dQw4w9WgXcQ');
    // ignore: avoid_print
    print('AUDIO host=${Uri.parse(url).host}');
    expect(url, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)), skip: _live ? false : 'butuh lingkungan Android (set LIVE=1)');
}
