import Flutter
import UIKit

// FFI-only plugin: no method channel or platform code needed.
// The plugin exists solely to package the Rust static lib
// (`libnative_animated_image_codec.a`) and have it linked into the host app
// via CocoaPods.
//
// All actual functionality lives in the main Dart package via dart:ffi.
public class NativeAnimatedImageIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No registration needed - this is an FFI plugin.
  }
}
