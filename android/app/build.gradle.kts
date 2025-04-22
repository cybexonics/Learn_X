import java.util.Properties
import com.android.build.gradle.internal.dsl.BaseAppModuleExtension

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode")?.toInt() ?: 1
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"
val flutterCompileSdkVersion = localProperties.getProperty("flutter.compileSdkVersion")?.toInt() ?: 34
val flutterTargetSdkVersion = localProperties.getProperty("flutter.targetSdkVersion")?.toInt() ?: 34

configure<BaseAppModuleExtension> {
    namespace = "com.example.my_app"
    compileSdkVersion(flutterCompileSdkVersion)
    ndkVersion = localProperties.getProperty("flutter.ndkVersion") ?: "25.2.9519653"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true // Enable desugaring
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.example.my_app"
        minSdk = 24 // Updated from 23 to 24 to match Jitsi requirements
        targetSdk = flutterTargetSdkVersion
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        multiDexEnabled = true // Add this for Jitsi
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:${project.properties["kotlin_version"]}")
    implementation("androidx.multidex:multidex:2.0.1") // Add this for Jitsi
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3") // Add desugaring dependency
}

// Apply the Google Services plugin
apply(plugin = "com.google.gms.google-services")