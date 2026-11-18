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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Con android.builtInKotlin=false (plantilla de Flutter), estos plugins no
// aplican Kotlin por su cuenta: screen_protector 1.5.3 solo lo hace con
// AGP < 9 y los de google_mlkit_* asumen el Kotlin integrado de
// AGP 9. Sin esto sus clases no se compilan.
val pluginsSinKotlin =
    setOf("screen_protector", "google_mlkit_commons", "google_mlkit_text_recognition")
subprojects {
    if (name in pluginsSinKotlin) {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
            if (name == "screen_protector") {
                extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}
