allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Force a consistent Kotlin version across all subprojects (including plugins like
    // audioplayers_android that declare older Kotlin in their own buildscript classpath).
    // This resolves the Kotlin 1.7.10 instrumentation failure in Gradle 8.14+ transforms.
    configurations.all {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-stdlib:2.2.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.2.20")
            force("org.jetbrains.kotlin:kotlin-stdlib-common:2.2.20")
            force("org.jetbrains.kotlin:kotlin-reflect:2.2.20")
        }
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
