#!/usr/bin/env bash
# Build APK release khusus ABI armeabi-v7a (arm32) untuk device 32-bit.
#
# Kenapa script dan bukan perintah biasa:
# 1. Flutter --target-platform hanya membatasi libapp/libflutter; native lib plugin
#    (Chaquopy/Python dll) mengikuti ndk.abiFilters. Karena itu property
#    `targetAbis=armeabi-v7a` dipasang sementara di android/gradle.properties
#    (lihat PATCH VENDOR #3 di third_party/yt_flutter_musicapi/android/build.gradle
#    dan patch serupa di android/app/build.gradle.kts).
# 2. `flutter clean` wajib: sisa intermediates Gradle pernah membuat ABI lama ikut
#    terbawa ke APK walau --target-platform sudah diganti.
#
# Pemakaian:  ./tool/build-arm32.sh
# Output:     build/app/outputs/flutter-apk/app-release-arm32.apk
set -euo pipefail
cd "$(dirname "$0")/.."

PROP_FILE="android/gradle.properties"
if grep -q "^targetAbis=" "$PROP_FILE"; then
    echo "ERROR: $PROP_FILE sudah berisi targetAbis; hapus dulu agar tidak bentrok." >&2
    exit 1
fi

restore() {
    # Berjalan baik saat sukses maupun gagal (trap EXIT) supaya property tidak tertinggal.
    sed -i '/^targetAbis=/d' "$PROP_FILE"
}
trap restore EXIT

FLUTTER="${FLUTTER:-$(command -v flutter 2>/dev/null || echo "/home/dika/develop/flutter/bin/flutter")}"
echo "targetAbis=armeabi-v7a" >> "$PROP_FILE"
$FLUTTER clean
$FLUTTER build apk --release --target-platform android-arm

OUT="build/app/outputs/flutter-apk"
mv -f "$OUT/app-release.apk" "$OUT/app-release-arm32.apk"
echo "OK: $OUT/app-release-arm32.apk"
