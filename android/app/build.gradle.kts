plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.music_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.music_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Chaquopy (yt_flutter_musicapi) butuh minSdk 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // FIX crash release "Invalid notification (no valid small icon)":
            // ikon notifikasi `drawable/ic_stat_music` sempat hilang dari APK
            // (aapt tidak menemukan resource drawable/ic_stat_music sama sekali)
            // karena penyusutan resource menghapus vector yang hanya dirujuk
            // lewat string dari Dart ("drawable/ic_stat_music"). Matikan
            // penyusutan + pasang keep.xml supaya ikon selalu ikut terkemas.
            isShrinkResources = false
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// PATCH (music_app): pembatas ABI per varian, hanya aktif jika property `targetAbis`
// ada (contoh: `targetAbis=armeabi-v7a` di android/gradle.properties — dipakai oleh
// tool/build-arm32.sh). Tanpa property, blok ini tidak mengubah apa pun sehingga
// build default/universal tetap identik.
// Tujuannya jadi "choke point" di app agar native lib dari input mana pun (Chaquopy
// via library, AndroidX, dsb.) ikut terfilter sesuai ABI varian.
val targetAbisProp = (project.findProperty("targetAbis") as? String).orEmpty()
val targetAbis = targetAbisProp.split(",").map { it.trim() }.filter { it.isNotEmpty() }
if (targetAbis.isNotEmpty()) {
    android {
        defaultConfig {
            ndk.abiFilters.clear()
            targetAbis.forEach { ndk.abiFilters.add(it) }
        }
    }
    // Flutter Gradle plugin bisa mengonfigurasi ABI setelah blok dievaluasi;
    // pasang ulang di afterEvaluate agar pembatas tetap menang.
    afterEvaluate {
        android.defaultConfig.ndk.abiFilters.clear()
        targetAbis.forEach { android.defaultConfig.ndk.abiFilters.add(it) }
    }
}

