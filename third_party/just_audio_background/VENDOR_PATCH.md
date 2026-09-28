# Vendor patch: just_audio_background

Paket ini adalah salinan `just_audio_background 0.0.1-beta.17` dari pub.dev yang
di-vendor ke repo (`dependency_overrides` di `pubspec.yaml`) **hanya** untuk
melengkapi tombol navigasi di notifikasi background playback: next, previous,
dan shuffle. Versi pub.dev menyorot next/prev (`hasNext`/`hasPrevious`) dan
tidak menyediakan tombol acak sama sekali.

Berkas yang diubah dibanding pub.dev: hanya
`lib/just_audio_background.dart` (kelas `_PlayerAudioHandler`, konstruktor
`_JustAudioPlayer`, dan kelas `_ModeEvent` baru).
Semua patch ditandai komentar `Vendor patch`.

## Perubahan dibanding pub.dev 0.0.1-beta.17

### Patch #1 — tombol next/prev selalu tampil + status acak/ulang dilaporkan

Lokasi: `_PlayerAudioHandler._broadcastState()`, `setShuffleMode()`, dan
`customAction()` (baru).

Upstream:

```dart
final controls = [
  if (hasPrevious) MediaControl.skipToPrevious,
  if (_playing) MediaControl.pause else MediaControl.play,
  if (hasNext) MediaControl.skipToNext,
];
```

Vendor (sekarang):

```dart
final controls = [
  MediaControl.skipToPrevious, // selalu ada, walau di ujung antrean (patch #2 wrap-around)
  if (_playing) MediaControl.pause else MediaControl.play,
  MediaControl.skipToNext,
];
```

dengan state tambahan:

```dart
systemActions: {
  MediaAction.seek,          // memunculkan seek bar di notifikasi Android 13+
  MediaAction.seekForward,
  MediaAction.seekBackward,
  MediaAction.setShuffleMode,
  MediaAction.setRepeatMode, // bit aksi untuk tombol bawaan sistem Android 13+
  MediaAction.skipToNext,    // WAJIB: AUTO_ENABLED_ACTIONS sengaja tidak menyalakannya
  MediaAction.skipToPrevious,
},
androidCompactActionIndices: const [0, 1, 2], // tampilan ringkas: prev/play/next
shuffleMode: _shuffleMode,  // dilaporkan supaya chip acak bawaan sistem sinkron
repeatMode: _repeatMode,
```

#### Revisi 2 — tombol acak kustom DIHAPUS

Versi sebelumnya menambahkan:

```dart
MediaControl.custom(
  androidIcon: 'drawable/ic_shuffle',
  label: isShuffle ? 'Acak Aktif' : 'Acak Lagu',
  name: 'shuffle',
),
```

Ternyata tombol itu **tidak pernah muncul** di notifikasi:

- `AudioServicePlugin.setState()` memanggil `createCustomAction(control)`; kontrol
  dengan `customAction != null` dimasukkan ke `PlaybackStateCompat` **custom
  actions**, bukan ke `nativeActions`.
- `AudioService.buildNotification()` hanya menambahkan `nativeActions` ke
  notifikasi. Jadi custom action tidak pernah jadi tombol notifikasi (Android
  < 13 tidak merendernya sama sekali; Android 13+/SystemUI juga tidak konsisten).
- Karena `MediaControl.custom` tidak punya keycode media-button,
  `buildMediaButtonPendingIntent()` mengembalikan `PendingIntent` null, sehingga
  sebagai control biasa pun tidak bisa diklik (`toKeyCode` → `KEYCODE_UNKNOWN`).

Karena itu kontrol kustom dibuang dan mode acak/ulang sekarang mengandalkan
**kontrol media bawaan Android 13+**:

- `audio_service` selalu menyalakan `ACTION_SET_SHUFFLE_MODE` dan
  `ACTION_SET_REPEAT_MODE` (`AUTO_ENABLED_ACTIONS` di `AudioService.java`), dan
- patch ini melaporkan `shuffleMode`/`repeatMode` pada `PlaybackStateCompat`.

Hasilnya chip acak/ulang di panel media Android 13+ benar-benar bisa diklik, dan
perubahannya kembali ke aplikasi lewat patch #4 (`setShuffleMode()` →
`_ModeEvent` → `shuffleModeEnabledStream` → `PlayerCubit.onShuffleChanged`).

Handler `customAction('shuffle')` dipertahankan hanya untuk kompatibilitas (kalau
aplikasi kelak memasang kontrol kustom bernama `shuffle` lagi).
`android/app/src/main/res/drawable/ic_shuffle.xml` kini tidak dipakai lagi, tapi
sengaja ditinggal agar tidak mengubah resource apa pun saat build.

Catatan batasan: di Android < 13 notifikasi hanya bisa memuat aksi ber-keycode
(play/pause/next/prev/stop/ff/rewind) sehingga **tidak ada** tombol acak di
notifikasi pada versi OS tersebut; status acak tetap dilaporkan lewat
`shuffleMode` sehingga Android Auto/Wear ikut sinkron.

Catatan batasan: di Android < 13 custom action tidak dirender sebagai tombol
notifikasi (hanya aksi ber-keycode: play/pause/next/prev/stop/ff/rewind).
Status acak/ulang tetap dilaporkan lewat `shuffleMode`/`repeatMode` sehingga
Android Auto/Wear ikut sinkron.

### Patch #2 — `skipToNext`/`skipToPrevious` tidak pernah mati

Lokasi: `_PlayerAudioHandler.skipToNext()`, `skipToPrevious()`.

Upstream berhenti diam saat antrean habis (dan `skipToPrevious` hanya restart
lagu). Vendor:

- next di ujung antrean → lompat ke lagu pertama (wrap-around);
- prev di awal antrean → lompat ke lagu terakhir;
- prev saat posisi > 3 detik → restart lagu (seperti pemutar standar);
- antrean berisi 1 lagu → restart lagu.

```dart
Future<void> skipToNext() async {
  if (hasNext) {
    await skipToQueueItem(nextIndex!);
  } else if (effectiveIndices.length > 1) {
    await skipToQueueItem(effectiveIndices.first);
  } else {
    await (await _player).seek(SeekRequest(position: Duration.zero));
  }
}
```

(`skipToPrevious()` analog, plus aturan restart > 3 detik.)

Aplikasi mengikuti semua perpindahan ini lewat
`AppAudioHandler.onIndexChanged` ← `currentIndexStream`, termasuk yang berasal
dari notifikasi. Penyisipan lagu rekomendasi `upNext` tetap hanya berlaku untuk
tombol di dalam aplikasi (`PlayerCubit.next()`), bukan untuk tombol notifikasi.

### Patch #3 — `setShuffleMode` eksplisit (bukan toggle)

Lokasi: `_PlayerAudioHandler.setShuffleMode()`.

Versi sebelumnya sempat di-patch menjadi toggle yang mengabaikan argumen
`shuffleMode`. Itu salah ketika pemanggil sudah tahu mode targetnya (misalnya
chip acak bawaan sistem Android 13 yang mengirim mode eksplisit, atau pemanggilan
berulang dengan nilai yang sama). Sekarang mode yang diminta dipakai apa adanya,
dan operasi toggle hanya dilakukan di satu tempat: `customAction('shuffle')`
dan tombol di UI aplikasi (`PlayerCubit.toggleShuffle` →
`AppAudioHandler.setShuffle`).

## Sinkronisasi dua arah dengan aplikasi

- Aplikasi → notifikasi: `PlayerCubit.toggleShuffle()` /
  `cycleRepeat()` memanggil `AppAudioHandler` → just_audio → service, dan
  `_broadcastState()` menerbitkan ulang tombol + `shuffleMode`/`repeatMode`.
- Notifikasi/sistem → aplikasi (patch #4): perubahan acak/ulang diterima
  service di `setShuffleMode()`/`setRepeatMode()` (dari `customAction('shuffle')`
  untuk tombol acak, atau dari aksi `setShuffleMode`/`setRepeatMode` bawaan
  sistem seperti chip Android 13+ / Android Auto). Selain meneruskan perintah
  ke audio engine, service juga menerbitkan `_ModeEvent` lewat `customEvent`
  dan `_JustAudioPlayer` mengubahnya menjadi `PlayerDataMessage(loopMode,
  shuffleMode)` untuk client just_audio. Di aplikasi,
  `AppAudioHandler.init()` mendengarkan `shuffleModeEnabledStream`/
  `loopModeStream` dan meneruskannya lewat callback baru
  `onShuffleChanged`/`onRepeatChanged`, lalu `PlayerCubit` meng-update
  `state.shuffle`/`state.repeat` supaya ikon di pemutar ikut berubah.
  Uji: `test/player_notification_test.dart`.

  Tanpa patch #4, sinkronisasi balik tidak terjadi: `setShuffleMode()`/
  `setRepeatMode()` versi pub.dev hanya meneruskan perintah ke audio engine di
  sisi service tanpa memancarkan `PlayerDataMessage`, sehingga
  `shuffleModeEnabledStream`/`loopModeStream` di aplikasi tidak pernah
  memancarkan nilai baru saat pengguna mengetuk tombol di notifikasi/sistem.

### Patch #4 — `_ModeEvent`: teruskan perubahan acak/ulang ke client

Lokasi: konstruktor `_JustAudioPlayer` (listener `customEvent` baru),
`_PlayerAudioHandler.setShuffleMode()`, `setRepeatMode()`, dan kelas baru
`_ModeEvent` di akhir berkas.

```dart
// di setShuffleMode()/setRepeatMode(), setelah _broadcastStateIfActive():
customEvent.add(_ModeEvent(shuffle: _shuffleMode, repeat: _repeatMode));

// di _JustAudioPlayer(...): ubah menjadi PlayerDataMessage untuk client
_audioHandler.customEvent
    .whereType<_ModeEvent>()
    .map((event) => (
          loopMode: LoopModeMessage.values[...event.repeat.index],
          shuffleMode: event.shuffle == AudioServiceShuffleMode.all
              ? ShuffleModeMessage.all
              : ShuffleModeMessage.none,
        ))
    .distinct() // cegah echo: perubahan dari aplikasi sendiri tidak memantul balik
    .listen((modes) {
  playerDataController.add(PlayerDataMessage(
    loopMode: modes.loopMode,
    shuffleMode: modes.shuffleMode,
  ));
});
```

Catatan echo: saat perubahan berasal dari aplikasi
(`AppAudioHandler.setShuffle/setRepeat` → platform-side `setShuffleMode/`-
`setLoopMode`), service tetap memancarkan `_ModeEvent` yang sama — tapi
`.distinct()` menahannya karena nilainya tidak berubah. `init()` aplikasi juga
memakai `.distinct()` pada stream-nya sebelum memanggil callback, lalu
`PlayerCubit` mengabaikan nilai yang sama dengan state saat ini. Jadi tidak
ada loop emit → set → emit.

## Cara update / kembali ke pub.dev

1. Unduh `just_audio_background-<versi>.tar.gz` dari pub.dev, ekstrak.
2. Salin `lib/` (plus `pubspec.yaml`, `LICENSE`, `README.md`) ke folder ini.
3. Ulangi patch #1–#4 di atas di `lib/just_audio_background.dart`.
4. `flutter pub get`, `flutter analyze`, `flutter test`.

Kalau upstream sudah mendukung next/prev permanen + tombol acak, hapus
`dependency_overrides` `just_audio_background` di `pubspec.yaml` dan pakai
versi pub.dev langsung.
