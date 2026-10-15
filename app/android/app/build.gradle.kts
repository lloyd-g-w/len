import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored), see README "Release".
//   storeFile=/absolute/path/to/len-release.jks   (or relative to android/app)
//   storePassword=…
//   keyAlias=len
//   keyPassword=…
// Without it, release builds fall back to the debug key (fine for testing,
// not for publishing: updates must always be signed with the same key).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "dev.len.len"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.len.len"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode / versionName come from `version: x.y.z+N` in pubspec.yaml
        // (overridable with --build-name / --build-number).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "Len"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    // A side-by-side test install (`-PlenTest=true`): its own app id and
    // label, so it never replaces (or needs uninstalling) a copy signed
    // with another key, and keeps that copy's notes.
    if (project.findProperty("lenTest") == "true") {
        defaultConfig.applicationIdSuffix = ".test"
        defaultConfig.manifestPlaceholders["appLabel"] = "Len (test)"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            // R8 code shrinking + resource shrinking. Plugins ship their own
            // consumer keep rules (e.g. `jni`); app-specific rules go in
            // proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    // Low-latency ink (WetInkOverlay.kt): front-buffered rendering and motion prediction.
    implementation("androidx.graphics:graphics-core:1.0.4")
    implementation("androidx.input:input-motionprediction:1.0.0")
    // Handwriting recognition off the UI thread (HandwritingRecognitionPlugin.kt); the same
    // version as google_mlkit_digital_ink_recognition's, which keeps the model downloads.
    implementation("com.google.mlkit:digital-ink-recognition:19.0.0")
    // WetInkModelTest (plain JVM): ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
}
