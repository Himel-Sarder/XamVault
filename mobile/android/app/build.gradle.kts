plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.uniexam.uniexam"
    // flutter_secure_storage compiles against SDK 37; matching it here silences the
    // plugin-mismatch warning. Requires AGP 8.13+ (see android/settings.gradle.kts).
    compileSdk = 37
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
        applicationId = "com.uniexam.uniexam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

/**
 * Removes dev-only plugins from the generated registrant before a release compile.
 *
 * `flutter pub get` writes GeneratedPluginRegistrant.java with every plugin it can see,
 * dev dependencies included, and `flutter build` does not rewrite it afterwards. A
 * release build leaves the dev plugins' Gradle modules out on purpose, so javac then
 * meets `dev.flutter.plugins.integration_test` with nothing on the classpath to satisfy
 * it and the build dies with "package does not exist".
 *
 * The effect is that any release build following any `pub get` fails, which is a trap
 * with no signposting: the registrant is generated and gitignored, so the diff shows
 * nothing and the error names a file nobody wrote.
 *
 * Which plugins to strip is read from `.flutter-plugins-dependencies` rather than named
 * here, so a dev dependency added later is handled without anyone remembering this.
 *
 * Only release compiles are hooked, so a debug build still registers everything. A
 * release build does leave the file stripped on disk afterwards, but any `flutter`
 * command that needs it -- `flutter test integration_test` included -- runs `pub get`
 * first and puts it straight back.
 */
val stripDevPluginRegistrations = tasks.register("stripDevPluginRegistrations") {
    val manifest = rootProject.projectDir.parentFile.resolve(".flutter-plugins-dependencies")
    val registrant = project.projectDir.resolve(
        "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
    )
    // Read at execution time: pub get may rewrite both during the build.
    doLast {
        if (!manifest.exists() || !registrant.exists()) return@doLast

        @Suppress("UNCHECKED_CAST")
        val parsed = groovy.json.JsonSlurper().parse(manifest) as Map<String, Any?>
        val android = (parsed["plugins"] as? Map<String, Any?>)?.get("android") as? List<Map<String, Any?>>
            ?: return@doLast
        val devOnly = android
            .filter { it["dev_dependency"] == true }
            .mapNotNull { it["name"] as? String }
        if (devOnly.isEmpty()) return@doLast

        val lines = registrant.readLines()
        val drop = sortedSetOf<Int>()
        lines.forEachIndexed { index, line ->
            // The catch line names the plugin: Log.e(TAG, "Error registering plugin <name>, ...
            val named = devOnly.any { line.contains("Error registering plugin $it,") }
            if (named) {
                // A registration is a fixed five-line block: try / add / catch / log / }.
                val start = (index - 2).coerceAtLeast(0)
                for (i in start..(index + 1).coerceAtMost(lines.lastIndex)) drop.add(i)
            }
        }
        if (drop.isEmpty()) return@doLast

        val kept = lines.filterIndexed { index, _ -> index !in drop }
        registrant.writeText(kept.joinToString(System.lineSeparator()) + System.lineSeparator())
        logger.lifecycle(
            "Stripped dev-only plugin registrations from GeneratedPluginRegistrant: " +
                devOnly.joinToString(", ")
        )
    }
}

tasks.matching { it.name.matches(Regex("compile.*ReleaseJavaWithJavac")) }.configureEach {
    dependsOn(stripDevPluginRegistrations)
}
