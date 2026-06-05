import Flutter
import UIKit

// FFI-only plugin: no method channel or platform code needed.
//
// The plugin exists solely to package the Rust static lib (via xcframework)
// and have it linked into the host app via CocoaPods.
//
// IMPORTANT: Because dart:ffi looks up symbols at runtime, Xcode's linker
// has no compile-time evidence that anyone calls the Rust functions and will
// dead-strip them. We force the linker to keep them via `-u <symbol>` flags
// in the podspec's OTHER_LDFLAGS (see native_animated_image_ios.podspec).
//
// All actual functionality lives in the main Dart package via dart:ffi.
public class NativeAnimatedImageIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No registration needed - this is an FFI plugin.
  }
}
