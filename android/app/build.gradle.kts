plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = System.getenv("RCN_RELEASE_STORE_FILE")
val releaseStorePassword = System.getenv("RCN_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("RCN_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("RCN_RELEASE_KEY_PASSWORD")
val releaseSigningValues =
    listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    )
val releaseSigningConfigured = releaseSigningValues.all { !it.isNullOrBlank() }
val releaseSigningPartiallyConfigured =
    releaseSigningValues.any { !it.isNullOrBlank() } && !releaseSigningConfigured
val releaseBuildRequested =
    gradle.startParameter.taskNames.any { requestedTask ->
        val taskName = requestedTask.substringAfterLast(':')
        taskName.contains("release", ignoreCase = true) ||
            taskName.equals("build", ignoreCase = true) ||
            taskName.equals("assemble", ignoreCase = true) ||
            taskName.equals("bundle", ignoreCase = true)
    }

if (releaseSigningPartiallyConfigured) {
    throw GradleException(
        "Release signing is only partially configured. " +
            "Use tool/build-release.ps1 so no signing value is omitted.",
    )
}

if (releaseBuildRequested && !releaseSigningConfigured) {
    throw GradleException(
        "Release signing is not configured. " +
            "Use tool/build-release.ps1 with a dedicated keystore.",
    )
}

android {
    namespace = "com.kapioka.recipe_cooking_navigator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kapioka.recipe_cooking_navigator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
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
