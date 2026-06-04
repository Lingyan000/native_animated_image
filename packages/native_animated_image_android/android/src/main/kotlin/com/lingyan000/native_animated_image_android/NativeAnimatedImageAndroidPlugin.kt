package com.lingyan000.native_animated_image_android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * FFI-only plugin: no method channel or platform code needed.
 *
 * The plugin exists solely to package the Rust shared libraries
 * (`libnative_animated_image_codec.so` under `jniLibs/{abi}/`) and have them
 * automatically packaged into the host app APK / AAB by Android Gradle Plugin.
 *
 * All actual functionality lives in the main Dart package via dart:ffi.
 */
class NativeAnimatedImageAndroidPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No registration needed - this is an FFI plugin.
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // No cleanup needed.
    }
}
