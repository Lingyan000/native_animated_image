import Cocoa
import FlutterMacOS

/// macOS plugin entry point.
///
/// Mirrors the iOS plugin (same method channel name + same payload format):
///
/// 1. **FFI** for GIF/APNG/WebP via `libnative_animated_image_codec.dylib`
/// 2. **AVIF method channel** routing to system ImageIO (macOS 13.4+),
///    which uses Apple's optimized AVIF codec — same one Safari uses.
///    See `NativeAvifPlatformDecoder.swift` (this file is the macOS twin
///    of the iOS plugin's same-named class).
public class NativeAnimatedImageMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.lingyan000.native_animated_image/avif_platform",
      binaryMessenger: registrar.messenger)
    let instance = NativeAnimatedImageMacosPlugin()
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
