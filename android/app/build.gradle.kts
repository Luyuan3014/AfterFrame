plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.after_frame"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.after_frame"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Android 15+ 16KB 页面对齐：兼容未对齐的原生库，避免 .so 加载时崩溃
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        // 多 AAR 同名 .so 冲突处理：取第一个可用的，避免重复类定义
        pickFirsts += listOf(
            "**/libc++_shared.so",
            "**/libavcodec.so",
            "**/libavfilter.so",
            "**/libavformat.so",
            "**/libavutil.so",
            "**/libswresample.so",
            "**/libswscale.so",
        )
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false   // 避免 R8 误删 JNI 桥接
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FFmpeg Kit Android build with 16 KB page support and every ABI used by
    // Flutter's default --split-per-abi command.
    implementation("com.antonkarpenko:ffmpeg-kit-full:2.2.1")
    implementation("com.arthenica:smart-exception-java:0.2.1")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
