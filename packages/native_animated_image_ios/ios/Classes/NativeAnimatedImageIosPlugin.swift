import Flutter
import UIKit

/// iOS plugin entry point.
///
/// Two responsibilities:
///
/// 1. **FFI**: package the Rust dylib (via the bundled xcframework) so
///    `DynamicLibrary.process()` on the Dart side can resolve symbols from
///    `native_animated_image_codec` for GIF/APNG/WebP decoding.
/// 2. **AVIF method channel**: expose Apple's system ImageIO (iOS 16.4+)
///    to Dart so AVIF (including animated sequences) goes through Apple's
///    optimized codec — measurably faster than the third-party libavif
///    that flutter_avif ships. See `NativeAvifPlatformDecoder.swift`.
public class NativeAnimatedImageIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.lingyan000.native_animated_image/avif_platform",
      binaryMessenger: registrar.messenger())
    let instance = NativeAnimatedImageIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canDecodeAvif":
      result(NativeAvifPlatformDecoder.canDecodeAvif)

    case "decodeAvif":
      guard let args = call.arguments as? [String: Any],
            let typed = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid_args",
                            message: "expected { bytes: Uint8List }",
                            details: nil))
        return
      }
      // Decode on a background QoS so we don't block the platform thread.
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let decoded = try NativeAvifPlatformDecoder.decode(bytes: typed.data)
          DispatchQueue.main.async { result(decoded) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "decode_error",
                                message: error.localizedDescription,
                                details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
