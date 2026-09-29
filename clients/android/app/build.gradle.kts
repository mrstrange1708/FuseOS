import com.google.protobuf.gradle.proto

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.protobuf)
}

android {
    namespace = "com.fuseos.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.fuseos.app"
        minSdk = 26
        targetSdk = 34
        // The release workflow passes the tag and run number; local builds stay 0.1 (1).
        versionCode = (project.findProperty("versionCode") as String?)?.toInt() ?: 1
        versionName = (project.findProperty("versionName") as String?) ?: "0.1"

        // Where the app looks for the control plane. `./dev.sh` passes this Mac's
        // current LAN IP; the default is the emulator's alias for the host.
        val serverUrl = (project.findProperty("serverUrl") as String?) ?: "http://10.0.2.2:3000"
        buildConfigField("String", "SERVER_URL", "\"$serverUrl\"")
    }

    // Release signing comes from the environment (the release workflow decodes the keystore
    // from a secret). Without it, assembleRelease still builds — unsigned, uninstallable —
    // which is what a local release build should be: the key never lives in the repo.
    val keystore = System.getenv("FUSE_KEYSTORE")?.let(::file)?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storePassword = System.getenv("FUSE_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("FUSE_KEY_ALIAS") ?: "fuseos"
                keyPassword = System.getenv("FUSE_KEY_PASSWORD") ?: System.getenv("FUSE_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    // The device-to-device wire contract lives at the repo root and is shared verbatim
    // with the macOS client. Never hand-edit the generated bindings.
    sourceSets {
        named("main") {
            proto { srcDir("../../../proto") }
        }
    }
}

protobuf {
    protoc { artifact = "com.google.protobuf:protoc:${libs.versions.protobuf.get()}" }
    generateProtoTasks {
        all().forEach { task ->
            task.builtins {
                create("java") { option("lite") }
            }
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.graphics.path)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)

    // Scanning the link QR: CameraX for the preview, ML Kit for the decode.
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.mlkit.barcode.scanning)

    implementation(libs.androidx.datastore.preferences)
    // Sign in with Google: the system account picker hands back an ID token (docs/api.md).
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services)
    implementation(libs.googleid)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.client.websockets)
    implementation(libs.ktor.serialization.kotlinx.json)

    implementation(libs.protobuf.javalite)

    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
}
