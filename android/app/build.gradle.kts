import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// AND-02：release 簽名讀 android/key.properties（CI 由 GitHub secrets 產生，
// 本機不存在時 debug 組建與測試照常）。release 缺件時 fail closed，
// 絕不回退 debug 簽名。
val keystoreProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        FileInputStream(propertiesFile).use { load(it) }
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingSigningKeys =
    releaseSigningKeys.filter { keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.vibesync.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // DEC-03 凍結：applicationId 固定 com.vibesync.app，不得改。
        applicationId = "com.vibesync.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (missingSigningKeys.isEmpty()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// release 組建的 fail-closed 守門：缺簽名欄位或 keystore 檔不存在就直接擋，
// 錯誤訊息不含任何密碼內容。
tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        doFirst {
            check(missingSigningKeys.isEmpty()) {
                "android/key.properties 缺少 release 簽名欄位 $missingSigningKeys；" +
                    "release 禁用 debug 簽名（fail closed）"
            }
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            check(file(storeFilePath).exists()) {
                "release keystore 不存在：$storeFilePath（fail closed）"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
