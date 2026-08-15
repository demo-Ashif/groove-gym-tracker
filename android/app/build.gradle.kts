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

    // Three flavors installable side by side (ADR §16), so a real logging
    // history can live on prod while dev is being broken.
    flavorDimensions += "env"

    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Groove Dev")
        }
        create("stg") {
            dimension = "env"
            applicationIdSuffix = ".stg"
            resValue("string", "app_name", "Groove Stg")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Groove")
        }
    }

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
