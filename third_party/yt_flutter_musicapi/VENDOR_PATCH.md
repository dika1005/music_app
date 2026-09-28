# Vendor patch: yt_flutter_musicapi

Paket ini adalah salinan `yt_flutter_musicapi 3.4.4` dari pub.dev yang di-vendor ke repo
(`dependency_overrides` di `pubspec.yaml`) **hanya** karena satu bug build di Android:
`android/build.gradle` upstream menulis build Python secara hardcode ke path Windows.

## Perubahan dibanding pub.dev 3.4.4

### Patch #1 — `buildPython` (hardcode path Windows)

Lokasi: `android/build.gradle`, blok `chaquopy { defaultConfig { ... } }`.

Upstream:

```groovy
chaquopy {
    defaultConfig {
        version = "3.11"
        buildPython("C:/Python311/python.exe")
```

Vendor (sekarang):

```groovy
chaquopy {
    defaultConfig {
        version = "3.11"
        buildPython(resolveBuildPython())   // env CHAQUOPY_BUILD_PYTHON -> python3.11 di Linux/macOS
```

`resolveBuildPython()` didefinisikan tepat di atas blok `chaquopy`. Resolusi:
`CHAQUOPY_BUILD_PYTHON` (env) → Windows: `C:/Python311/python.exe` → lainnya: `python3.11`.

Gejala kalau baris ini tidak dipatch (build gagal setelah ~1-13 menit):

```
Execution failed for task ':yt_flutter_musicapi:installDebugPythonRequirements'.
> [C:/Python311/python.exe] is not a valid Python 3.11 command:
  '.../yt_flutter_musicapi-3.4.4/android/C:/Python311/python.exe' does not exist.
```

### Patch #2 — `flutter.jar` dari cache engine lokal (path usang)

Lokasi: `android/build.gradle`, blok `dependencies`.

Upstream:

```groovy
compileOnly files("$flutterRoot/bin/cache/artifacts/engine/android-arm/flutter.jar")
```

Vendor (sekarang):

```groovy
def legacyFlutterJar = file("$flutterRoot/bin/cache/artifacts/engine/android-arm/flutter.jar")
if (legacyFlutterJar.exists()) {
    compileOnly files(legacyFlutterJar)
}
```

Alasan: Flutter modern tidak lagi menaruh `flutter.jar` debug di
`bin/cache/artifacts/engine/android-arm/` (yang ada hanya varian `-profile`/`-release`).
Embedding sekarang datang via Maven `io.flutter:flutter_embedding_<mode>` yang ditambahkan
otomatis oleh Flutter Gradle plugin ke semua project plugin
(`flutter_tools/gradle/.../plugins/PluginHandler.kt`). Dengan baris upstream, build gagal:

```
Execution failed for task ':yt_flutter_musicapi:compileDebugKotlin'.
> Could not resolve all files for configuration ':yt_flutter_musicapi:debugCompileClasspath'.
  > Failed to transform flutter.jar ...
    > File/directory does not exist: .../engine/android-arm/flutter.jar
```

### Patch #3 — `ndk.abiFilters` (hardcode 4 ABI)

Lokasi: `android/build.gradle`, blok `defaultConfig { ndk { ... } }`.

Upstream:

```groovy
ndk {
    abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'
}
```

Vendor (sekarang):

```groovy
ndk {
    abiFilters.clear()
    resolveTargetAbis().each { abiFilters.add(it) }   // default = 4 ABI spt upstream
}
```

Alasan: Flutter `--target-platform` hanya membatasi `libapp.so`/`libflutter.so`, sedangkan
Chaquopy mengikuti `abiFilters` ini. Dengan hardcode 4 ABI, build `--target-platform android-arm`
tetap mengemas libpython & kawan-kawan untuk arm64/x86_64 tanpa `libapp.so`/`libflutter.so` —
APK "arm32" itu lengket berisi 3 ABI dan **crash di device arm64** (Android memilih folder
ABI terbaik yang tidak lengkap itu). `resolveTargetAbis()` membaca property gradle root
`targetAbis` (mis. `targetAbis=armeabi-v7a` di `android/gradle.properties`); tanpa property,
empat ABI seperti upstream. Pembatas serupa juga ditambahkan di `android/app/build.gradle.kts`
milik app (choke point untuk native lib dari input lain). Lihat `tool/build-arm32.sh`.

## Prasyarat host

Chaquopy menjalankan `pip install yt-dlp ytmusicapi` di komputer yang build, jadi host harus
punya **Python 3.11** (harus sama dengan `version = "3.11"`) dan akses internet ke PyPI +
`https://chaquo.com/maven`.

```bash
python3.11 --version              # butuh 3.11.x
python3.11 -m pip --version       # pip harus ada
# kalau python3.11 tidak ada di PATH, mis. dari pyenv:
export CHAQUOPY_BUILD_PYTHON=$HOME/.pyenv/versions/3.11.9/bin/python3.11
```

## Cara update / kembali ke pub.dev

1. Unduh `yt_flutter_musicapi-<versi>.tar.gz` dari pub.dev, ekstrak.
2. Salin `lib/`, `android/`, `pubspec.yaml`, `LICENSE`, `README.md` ke folder ini.
3. Ulangi patch `buildPython` dan patch #3 (`abiFilters`) di `android/build.gradle`.
4. `flutter pub get`.

Kalau upstream sudah menghapus hardcode path Windows, hapus
`dependency_overrides` di `pubspec.yaml` dan pakai versi pub.dev langsung.
