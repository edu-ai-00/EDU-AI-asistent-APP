import java.util.Base64
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Compile-time --dart-define values. Flutter hands them to Gradle as one
// comma-separated property of base64-encoded "KEY=value" entries.
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.mapNotNull { entry ->
        val decoded = String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
        val separator = decoded.indexOf('=')
        if (separator > 0) decoded.substring(0, separator) to decoded.substring(separator + 1) else null
    }
    ?.toMap()
    ?: emptyMap()

android {
    namespace = "com.eduai.eduaiapp"
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
        applicationId = "com.eduai.eduaiapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The app ships no google-services.json: the FIREBASE_* dart-defines
        // are the whole Firebase config. Expose them as the string resources
        // the google-services plugin would have generated, so Firebase's
        // native init also runs when a push wakes a killed app (no Dart yet).
        // A build without the defines gets no resources and no push.
        dartDefines["FIREBASE_ANDROID_APP_ID"]?.takeIf { it.isNotBlank() }?.let { appId ->
            resValue("string", "google_app_id", appId)
            dartDefines["FIREBASE_API_KEY"]?.let { resValue("string", "google_api_key", it) }
            dartDefines["FIREBASE_PROJECT_ID"]?.let { resValue("string", "project_id", it) }
            dartDefines["FIREBASE_MESSAGING_SENDER_ID"]?.let { resValue("string", "gcm_defaultSenderId", it) }
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
