plugins {
    id("com.android.application")
}

android {
    namespace = "io.github.avtsye.wsabtbridge"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.avtsye.wsabtbridge"
        minSdk = 30
        targetSdk = 35
        versionCode = 2
        versionName = "0.2.0"
    }

    signingConfigs {
        create("ciDebug") {
            val ciKey = rootProject.file("ci-debug.keystore")
            if (ciKey.exists()) {
                storeFile = ciKey
                storePassword = "android"
                keyAlias = "wsabtdebug"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (rootProject.file("ci-debug.keystore").exists()) {
                signingConfig = signingConfigs.getByName("ciDebug")
            }
        }
    }
}

dependencies {
}
