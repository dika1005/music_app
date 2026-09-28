#!/usr/bin/env bash
# Build APK release untuk arm32 (armeabi-v7a) dan arm64 (arm64-v8a).
# Menghapus build lama dan menyimpan kedua file APK secara rapi.
set -euo pipefail
cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-$(command -v flutter 2>/dev/null || echo "/home/dika/develop/flutter/bin/flutter")}"
PROP_FILE="android/gradle.properties"
OUT_DIR="build/app/outputs/flutter-apk"
DIST_DIR="release_apks"

restore() {
    sed -i '/^targetAbis=/d' "$PROP_FILE"
}
trap restore EXIT

echo "=== 1. Menghapus build lama ==="
restore
rm -rf build/ "$DIST_DIR"
mkdir -p "$DIST_DIR"
$FLUTTER clean

echo "=== 2. Membangun APK ARM32 (armeabi-v7a) ==="
restore
echo "targetAbis=armeabi-v7a" >> "$PROP_FILE"
$FLUTTER build apk --release --target-platform android-arm

cp -f "$OUT_DIR/app-release.apk" "$DIST_DIR/app-release-arm32.apk"
echo "Berhasil disimpan ke: $DIST_DIR/app-release-arm32.apk"

echo "=== 3. Membersihkan intermediate cache ==="
restore
$FLUTTER clean

echo "=== 4. Membangun APK ARM64 (arm64-v8a) ==="
restore
echo "targetAbis=arm64-v8a" >> "$PROP_FILE"
$FLUTTER build apk --release --target-platform android-arm64

cp -f "$OUT_DIR/app-release.apk" "$DIST_DIR/app-release-arm64.apk"
echo "Berhasil disimpan ke: $DIST_DIR/app-release-arm64.apk"

# Sinkronkan kembali kedua APK ke direktori output standar flutter
mkdir -p "$OUT_DIR"
cp -f "$DIST_DIR/app-release-arm32.apk" "$OUT_DIR/app-release-arm32.apk"
cp -f "$DIST_DIR/app-release-arm64.apk" "$OUT_DIR/app-release-arm64.apk"
rm -f "$OUT_DIR/app-release.apk" "$OUT_DIR/app-release.apk.sha1"

restore
echo "=== HASIL BUILD LENGKAP ==="
ls -lh "$OUT_DIR"/*.apk
ls -lh "$DIST_DIR"/*.apk
