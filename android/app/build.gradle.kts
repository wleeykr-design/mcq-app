plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.medquiz.mcqstudio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.medquiz.mcqstudio"
        minSdk = 21
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (file("medquiz.keystore").exists()) {
            create("release") {
                storeFile = file("medquiz.keystore")
                storePassword = System.getenv("KEYSTORE_PASS") ?: "medquiz27"
                keyAlias = System.getenv("KEY_ALIAS") ?: "medquiz"
                keyPassword = System.getenv("KEY_PASS") ?: "medquiz27"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (file("medquiz.keystore").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
