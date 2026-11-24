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
// AGP 9 enforces checkReleaseAarMetadata on library subprojects; ensure legacy
// Flutter plugins (e.g. opus_flutter_android compiled against API 33) compile
// against at least API 36 to satisfy Flutter 3.50+ AndroidX dependencies.
subprojects {
    if (name != "app") {
        afterEvaluate {
            val androidExt = extensions.findByName("android") ?: return@afterEvaluate
            val getCompileSdk = androidExt.javaClass.methods.firstOrNull {
                it.name == "getCompileSdk" && it.parameterCount == 0
            }
            val currentSdk = (getCompileSdk?.invoke(androidExt) as? Int) ?: 0
            if (currentSdk in 1..35) {
                val setCompileSdk = androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterCount == 1 &&
                        (it.parameterTypes[0] == Int::class.javaPrimitiveType ||
                            it.parameterTypes[0] == Integer::class.java)
                }
                setCompileSdk?.invoke(androidExt, 36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
