# MelodyFlow — Music Streaming App (Flutter)

Aplikasi music streaming berbasis Flutter (Material 3, font Plus Jakarta Sans) dengan
sumber katalog YouTube Music, background playback + kontrol notifikasi/lockscreen,
lirik tersinkronisasi (LRC), antrean lagu, pencarian suara, dan cache offline.

> Status: dalam pengembangan aktif menuju rilis pertama (`version: 1.0.0+1`).
> `flutter analyze` bersih, seluruh unit test hijau (`flutter test`).

## Fitur

- **Pemutaran audio** — play/pause/next/prev, seek, repeat (off/all/one), shuffle,
  background playback via `just_audio` + `audio_service` (`lib/shared/audio_service/`).
- **Notifikasi & lockscreen** — tombol next/prev selalu tampil (termasuk wrap-around
  di ujung antrean); status acak/ulang sinkron dua arah dengan aplikasi lewat chip
  bawaan Android 13+ (lihat [catatan vendor](#dependensi-yang-di-vendor-third_party)).
- **Lirik sinkron (LRC)** — auto-scroll mengikuti posisi lagu dengan kompensasi
  latensi output (±150 ms), tap baris untuk seek, auto re-center setelah user scroll
  manual, parser multi-timestamp + `[offset:]` + validasi durasi ±5 dtk terhadap LRCLIB.
- **Antrean lagu** — auto-lanjut rekomendasi terkait tanpa memutus audio
  (append + skip, bukan rebuild playlist), riwayat trailing max 20 + cap total 100,
  tap lagu tanpa jeda, reorder/drag, hapus, kosongkan antrean.
- **Beranda / Pencarian / Library** — blok konten YouTube Music, pencarian teks +
  pencarian suara (`speech_to_text`), playlist & unduhan lokal (`shared_preferences`).
- **Cache & offline** — unduhan audio, pre-resolve lagu sekitar posisi aktif,
  monitor konektivitas dengan banner.

## Arsitektur

Clean Architecture per fitur (`data / domain / presentation`), state memakai
`flutter_bloc` (Cubit), DI memakai `get_it` (`lib/injection.dart`), routing memakai
`go_router` (`lib/shared/routing/app_router.dart`).

```
lib/
├── core/            # theme, konstanta, error, utils (format, network, izin notif)
├── features/
│   ├── auth/        # layanan profil
│   ├── home/        # cubit + halaman beranda
│   ├── library/     # cubit + halaman library/playlist lokal
│   ├── player/      # domain Track, datasource YT Music, PlayerCubit (inti app)
│   └── search/      # cubit + halaman pencarian
├── shared/
│   ├── audio_service/  # AppAudioHandler, local stream server
│   ├── routing/        # go_router
│   └── widgets/        # full player, tab lirik/antrean, tile, sheet, dsb.
├── injection.dart
└── main.dart
```

Alur audio: `PlayerCubit` (`lib/features/player/presentation/bloc/player_cubit.dart`)
mengatur antrean/state → `AppAudioHandler` (`lib/shared/audio_service/audio_handler.dart`)
meneruskan ke `just_audio` + sesi media untuk notifikasi/lockscreen. Sumber lagu:
`yt_music_datasource.dart` (YouTube Music API + LRCLIB untuk lirik).

## Dependensi yang di-vendor (`third_party/`)

Dua plugin di-vendor karena versi pub.dev belum memenuhi kebutuhan — **jangan hapus
override `dependency_overrides` di `pubspec.yaml`** sebelum upstream diperbaiki:

| Plugin | Alasan | Detail |
|---|---|---|
| `yt_flutter_musicapi` | `build.gradle` upstream hardcode path Python Windows + path `flutter.jar` lama → build gagal di Linux/macOS | [`third_party/yt_flutter_musicapi/VENDOR_PATCH.md`](third_party/yt_flutter_musicapi/VENDOR_PATCH.md) |
| `just_audio_background` | Notifikasi butuh next/prev permanen (termasuk wrap-around) + sinkron acak/ulang dua arah. Catatan: kontrol media kustom (`MediaControl.custom`) **tidak bisa dirender** `audio_service` — tombol acak/ulang memakai chip bawaan Android 13+ | [`third_party/just_audio_background/VENDOR_PATCH.md`](third_party/just_audio_background/VENDOR_PATCH.md) |

## Prasyarat

- Flutter SDK (stable) + Dart `^3.12.2`
- Android SDK + `ANDROID_HOME`, JDK 21 (dipakai Gradle 9.1), lisensi SDK di-accept
- **Python 3.11 di host** — wajib, karena Chaquopy (`yt_flutter_musicapi`) menjalankan
  `pip install yt-dlp ytmusicapi` saat build. Cek: `python3.11 --version`.
  Kalau tidak ada di PATH: `export CHAQUOPY_BUILD_PYTHON=/path/ke/python3.11`.
- Koneksi internet ke Maven/PyPI/`chaquo.com/maven` (build pertama mengunduh ~2 GB)
- Sisa disk **minimal ~4 GB** (Chaquopy mengemas Python untuk 3 ABI sekaligus)

## Cara jalan (dev)

```bash
flutter pub get
flutter analyze        # harus: No issues found
flutter test           # harus: semua passed (1 skip lama)
flutter run -d <device-id>   # lihat device: flutter devices
```

## Build Android (APK)

Prasyarat di komputer yang dipakai build:

- Android SDK + `ANDROID_HOME`, JDK 21 (dipakai Gradle 9.1), lisensi SDK sudah di-accept
  (`/opt/android-sdk/licenses` di mesin dev ini sudah ada).
- **Python 3.11 di host** — wajib, karena Chaquopy (`yt_flutter_musicapi`) menjalankan
  `pip install yt-dlp ytmusicapi` saat build. Cek: `python3.11 --version`.
  Kalau `python3.11` tidak ada di PATH: `export CHAQUOPY_BUILD_PYTHON=/path/ke/python3.11`.
- Koneksi internet ke Maven/PyPI/`chaquo.com/maven` (build pertama mengunduh ~2 GB).
- Sisa disk **minimal ~4 GB** (Chaquopy mengemas Python untuk 3 ABI sekaligus).

```bash
flutter pub get
flutter build apk --debug --target-platform android-arm64     # lebih cepat & kecil
flutter build apk --release --target-platform android-arm64
```

Hasil: `build/app/outputs/flutter-apk/app-debug.apk` (143 MB) dan `app-release.apk` (71 MB).
Tanpa `--target-platform`, APK tetap berisi 3 ABI (arm64-v8a, armeabi-v7a, x86_64) dan
prosesnya jauh lebih lama.

Pasang ke HP (USB debugging aktif) lalu jalankan/amati log:

```bash
flutter devices
flutter run -d <device-id>
# atau: adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Catatan: `app-release.apk` ditandatangani dengan debug key (lihat `android/app/build.gradle.kts`),
jadi cukup untuk uji coba/sideload, bukan untuk Play Store.

### Varian arm32 (armeabi-v7a) khusus

APK universal di atas sudah mencakup armeabi-v7a, jadi HP 32-bit biasa tetap bisa
memakainya. Untuk APK khusus arm32 (~71 MB, mis. device 32-bit lama):

```bash
./tool/build-arm32.sh
```

Hasil: `build/app/outputs/flutter-apk/app-release-arm32.apk`. Script itu men-toggle
property `targetAbis=armeabi-v7a` sementara di `android/gradle.properties` (dipakai oleh
ndk.abiFilters di app sekaligus plugin Chaquopy), menjalankan `flutter clean` (wajib —
sisa intermediates pernah membuat ABI lama ikut terbawa), lalu mengembalikan property
otomatis. Tanpa property itu, build biasa tetap universal. Property yang sama juga bisa
dipakai untuk varian lain, mis. `targetAbis=arm64-v8a` + `--target-platform android-arm64`
— selama folder ABI terbaik APK selalu lengkap (punya `libapp.so`/`libflutter.so`),
kalau tidak APK bisa crash di device yang memilih ABI tak lengkap.

`yt_flutter_musicapi` di-vendor ke `third_party/` karena `build.gradle` versi pub.dev
hardcode path Python Windows dan path `flutter.jar` lama sehingga build gagal di
Linux/macOS. Detail + cara update ada di
[`third_party/yt_flutter_musicapi/VENDOR_PATCH.md`](third_party/yt_flutter_musicapi/VENDOR_PATCH.md).

`just_audio_background` di-vendor ke `third_party/` supaya notifikasi background
playback punya navigasi lengkap: tombol next/prev selalu tampil (termasuk
wrap-around di ujung antrean) dan status acak/ulang tersinkron dua arah dengan
aplikasi. Tombol acak/ulang di notifikasi memakai kontrol media bawaan Android 13+
(chip sistem), bukan tombol kustom — detail alasannya ada di
[`third_party/just_audio_background/VENDOR_PATCH.md`](third_party/just_audio_background/VENDOR_PATCH.md).

## Test

```bash
flutter test
```

Test penting: `test/player_queue_test.dart` (antrean: auto-lanjut, reorder,
pemangkasan riwayat), `test/lyrics_sync_test.dart` (parser + regresi drift
auto-scroll), `test/player_notification_test.dart` (media item notifikasi),
`test/optimization_test.dart`, `test/home_blocks_test.dart`,
`test/search_cubit_test.dart`, `test/library_cubit_test.dart`.
`test/live_probe_test.dart` butuh jaringan (probe API sungguhan).

## Keterbatasan yang diketahui

- **Android < 13**: notifikasi hanya bisa memuat aksi ber-keycode → tidak ada tombol
  acak di notifikasi (batasan OS). Next/prev tetap ada.
- **Shuffle aktif**: urutan acak dijalankan engine audio, sedangkan daftar
  "BERIKUTNYA DALAM ANTREAN" menampilkan urutan posisi — bisa menyesatkan, dan
  edit/hapus antrean saat shuffle aktif berisiko desync. Workaround: matikan
  shuffle dulu sebelum mengubah antrean.
- **Reorder jarak jauh**: drag lagu lebih dari ~1 layar sulit karena list antrean
  bersarang (tidak auto-scroll saat drag). Geser 1–2 posisi masih normal.

## Dokumen perancangan

Spesifikasi awal ada di `requirement/` (PRD, feature spec, struktur folder,
provider API & catatan legal, coding guidelines) — sebagian sudah tidak sinkron
dengan implementasi, jadikan referensi sejarah, bukan acuan utama.
