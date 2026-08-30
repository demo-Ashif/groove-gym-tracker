plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Reverse-DNS of the aether.lab domain (ADR §1.2). The namespace never
    // carries a flavor suffix — only the application ID does, or R-class
    // resolution breaks.
    namespace = "lab.aether.groove"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent once published — Android will never allow a change.
        applicationId = "lab.aether.groove"
        // Android 8.0 (ADR: iOS 15+ / Android 8+, API 26).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // No product flavors. dev/prod differ only in Dart-side config, compiled in
    // from lib/core/config/app_env.dart and selected by entrypoint
    // (lib/main_dev.dart | lib/main_prod.dart). One application ID, one
    // installable app. Revisit if side-by-side installs are ever needed.
    //
    // iOS has Dev/Prod Xcode schemes backed by per-environment build
    // configurations, so `--flavor` works there and not here. Keep CLI runs
    // flavorless (`flutter run -t lib/main_dev.dart`) so they work on both.

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
