plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.thescaleon.paasel.delivery_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.thescaleon.paasel.delivery_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The Maps SDK reads its key from the manifest, so --dart-define cannot
        // reach it. Supply one with either
        //   flutter build apk --android-project-arg=mapsApiKey=AIza...
        // or GOOGLE_MAPS_API_KEY in the environment.
        //
        // Empty is a valid build: the key entry exists, the SDK reports an
        // authorization failure, and the dashboard's position card stays a grey
        // tile. The coordinates printed beneath it come from geolocator and are
        // unaffected.
        manifestPlaceholders["mapsApiKey"] =
            (project.findProperty("mapsApiKey") as String?)
                ?: System.getenv("GOOGLE_MAPS_API_KEY")
                ?: ""
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
