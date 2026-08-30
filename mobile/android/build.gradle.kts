allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

/**
 * Puts concurrent-futures on camera_android_camerax's own compile classpath.
 *
 * The plugin's Java references `androidx.concurrent.futures.CallbackToFutureAdapter`
 * but does not declare it, so `:camera_android_camerax:compileReleaseJavaWithJavac`
 * fails with "class file ... not found" -- and, because javac cannot complete the
 * symbol, it reports the whole thing as an internal compiler error and asks you to
 * file a bug against the JDK, which sends you looking in the wrong place entirely.
 *
 * It has to be added to that subproject. Declaring it in :app does nothing: the app's
 * classpath is not the plugin's, which is the mistake I made first.
 */
subprojects {
    if (name == "camera_android_camerax") {
        afterEvaluate {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.1.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
