import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La llave de firma vive FUERA del repositorio (D-51), al lado de codigo/:
// ../llaves-android/key.properties y el .jks que nombra. Sin ella, el APK de release se firma
// con la llave de depuracion, que sirve para probar pero no para publicar: un telefono no
// acepta instalar encima de una version firmada con otra llave.
val carpetaDeLlaves = rootProject.file("../../../llaves-android")
val llave = Properties().apply {
    val archivo = carpetaDeLlaves.resolve("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}
val hayLlave = llave.getProperty("storeFile") != null

android {
    namespace = "tech.maxpizzapp.cocina"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // El APK es solo para cocina (D-48): recepcion sigue en la web.
        applicationId = "tech.maxpizzapp.cocina"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Por donde vuelve Keycloak despues del acceso (D-49): tech.maxpizzapp.cocina:/callback.
        // Tiene que coincidir con AutorizadorAndroid.retorno y estar en el cliente de Keycloak.
        manifestPlaceholders += mapOf("appAuthRedirectScheme" to "tech.maxpizzapp.cocina")
    }

    signingConfigs {
        if (hayLlave) {
            create("release") {
                storeFile = carpetaDeLlaves.resolve(llave.getProperty("storeFile"))
                storePassword = llave.getProperty("storePassword")
                keyAlias = llave.getProperty("keyAlias")
                keyPassword = llave.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hayLlave) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "AVISO: no esta la llave en ${carpetaDeLlaves.path}. El APK se firma con la " +
                        "llave de depuracion: sirve para probar, NO para publicar.",
                )
                signingConfigs.getByName("debug")
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
