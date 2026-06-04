import Cocoa
import FlutterMacOS

// FFI-only plugin: no method channel or platform code needed.
// The plugin exists solely to package the Rust dylib (`libnative_animated_image_codec.dylib`)
// and have it linked into the host app's Frameworks/ directory via CocoaPods.
//
// All actual functionality lives in the main Dart package via dart:ffi.
public class NativeAnimatedImageMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No registration needed - this is an FFI plugin.
  }
}
