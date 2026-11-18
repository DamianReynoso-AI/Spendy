import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Llave de firma de release: android/key.properties (no se versiona; ver
// docs/firma_release.md). AUD-02: sin esa llave el release NO se compila,
// porque un APK firmado con la llave de depuración no se puede instalar
// encima del anterior (hay que desinstalar y se pierden los datos) ni
// publicar en Google Play. Solo para pruebas internas se puede firmar con
// la de depuración exportando SPENDY_ALLOW_DEBUG_SIGNING=1.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null
val allowDebugSigning = System.getenv("SPENDY_ALLOW_DEBUG_SIGNING") == "1"

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.name.contains("Release") }
    if (buildsRelease && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            "Falta android/key.properties: el release debe firmarse con la " +
                "llave de Spendy (docs/firma_release.md). Para una prueba " +
                "interna, exporta SPENDY_ALLOW_DEBUG_SIGNING=1.",
        )
    }
}

android {
    namespace = "mx.zenorbak.spendy"
    compileSdk = 37 // permission_handler_android pide 37 o mayor
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mx.zenorbak.spendy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // RNF-34: Android 10 (API 29) o superior.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug",
            )
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
