import org.gradle.kotlin.dsl.support.serviceOf
import org.gradle.process.ExecOperations

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

// The cargokit that `irondash_engine_context` bundles still calls
// `project.exec { ... }`, which Gradle 9 removed. This gives that plugin's
// project the same call, run through `ExecOperations`. Remove it when the
// plugin ships a cargokit that uses `ExecOperations`.
project(":irondash_engine_context") {
    val execOperations = serviceOf<ExecOperations>()
    extensions.extraProperties["exec"] =
        object : groovy.lang.Closure<Any?>(this) {
            @Suppress("unused")
            fun doCall(spec: groovy.lang.Closure<*>): Any? =
                execOperations.exec {
                    spec.delegate = this
                    spec.resolveStrategy = groovy.lang.Closure.DELEGATE_FIRST
                    spec.call(this)
                }
        }
}

// The same plugin compiles against API 31, which the AndroidX libraries it
// pulls in no longer accept.
project(":irondash_engine_context") {
    val raise = {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
    if (state.executed) raise() else afterEvaluate { raise() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
