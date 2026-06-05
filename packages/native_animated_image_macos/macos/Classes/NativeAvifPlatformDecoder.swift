// Native AVIF decoder via Apple's system ImageIO.
//
// Why this matters: Safari iOS 16.4+ / macOS 13.4+ use the same ImageIO path
// to decode AVIF (including animated AVIF sequences). Apple's implementation
// includes SIMD + hardware-accelerated codepaths that are measurably faster
// (community-reported 2-5x) than the third-party libavif/dav1d that the
// flutter_avif package ships.
//
// This file is **shared between the iOS and macOS plugins** (the macOS plugin's
// Classes directory contains a symlink to this file). Both use the same
// ImageIO API — `import ImageIO` works identically on UIKit and AppKit.

import Foundation
import ImageIO
import CoreGraphics
#if os(iOS)
import MobileCoreServices
#endif

@objc public class NativeAvifPlatformDecoder: NSObject {

  /// Whether the running OS version supports AVIF decoding via system ImageIO.
  /// iOS 16.4+ / macOS 13.4+ added animated AVIF; older versions only handled
  /// static AVIF and we want the full feature set so we gate on the same line.
  @objc public static var canDecodeAvif: Bool {
    if #available(iOS 16.4, macOS 13.4, *) {
      return true
    }
    return false
  }

  /// Decode an AVIF byte buffer into RGBA frames.
  /// Returns a dictionary suitable for `FlutterResult`:
  /// ```
  /// {
  ///   "width": Int, "height": Int, "loopCount": Int,
  ///   "frames": [{ "rgba": FlutterStandardTypedData, "delayMs": Int }, ...]
  /// }
  /// ```
  /// Throws if AVIF decoding fails or the OS doesn't support it.
  @objc public static func decode(bytes: Data) throws -> [String: Any] {
    guard canDecodeAvif else {
      throw NSError(domain: "NativeAvifPlatformDecoder", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                                 "OS version too old (need iOS 16.4+ / macOS 13.4+)"])
    }

    let cfData = bytes as CFData
    guard let source = CGImageSourceCreateWithData(cfData, nil) else {
      throw NSError(domain: "NativeAvifPlatformDecoder", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "CGImageSourceCreateWithData failed"])
    }

    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
      throw NSError(domain: "NativeAvifPlatformDecoder", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "AVIF has 0 frames"])
    }

    // Loop count: AVIF animation can specify how many times to loop.
    // 0 = infinite (matches GIF NETSCAPE2.0 convention used elsewhere in the package).
    var loopCount = 0
    if let containerProps = CGImageSourceCopyProperties(source, nil) as? [String: Any] {
      if let heicsProps = containerProps["{HEICS}"] as? [String: Any],
         let lc = heicsProps["LoopCount"] as? Int {
        loopCount = lc
      } else if let avifProps = containerProps["{AVIS}"] as? [String: Any],
                let lc = avifProps["LoopCount"] as? Int {
        loopCount = lc
      }
    }

    var width = 0
    var height = 0
    var frames: [[String: Any]] = []
    frames.reserveCapacity(count)

    for i in 0..<count {
      guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else {
        throw NSError(domain: "NativeAvifPlatformDecoder", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "frame \(i) decode failed"])
      }
      if i == 0 {
        width = cgImage.width
        height = cgImage.height
      }

      let rgba = try cgImageToRGBA(cgImage)
      let delayMs = extractFrameDelayMs(source: source, index: i)

      // FlutterStandardTypedData wraps the byte buffer for binary transfer over
      // the method channel (no string encoding).
      frames.append([
        "rgba": rgba,
        "delayMs": delayMs,
      ])
    }

    return [
      "width": width,
      "height": height,
      "loopCount": loopCount,
      "frames": frames,
    ]
  }

  // MARK: - Helpers

  /// Convert a `CGImage` to a tightly packed RGBA8888 byte buffer (premultiplied).
  /// Uses `CGContext` to redraw into a known pixel format — handles any source
  /// color space / bit depth and gives us bytes that Flutter's
  /// `ui.decodeImageFromPixels(format: rgba8888)` can consume directly.
  private static func cgImageToRGBA(_ cgImage: CGImage) throws -> Data {
    let w = cgImage.width
    let h = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = w * bytesPerPixel
    let bitsPerComponent = 8

    var pixelData = Data(count: w * h * bytesPerPixel)

    let ok: Bool = pixelData.withUnsafeMutableBytes { rawBuf -> Bool in
      guard let base = rawBuf.baseAddress else { return false }
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      // RGBA, premultiplied alpha, big-endian pixel layout
      let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.premultipliedLast.rawValue |
        CGBitmapInfo.byteOrder32Big.rawValue
      ).rawValue

      guard let ctx = CGContext(
        data: base,
        width: w,
        height: h,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      ) else {
        return false
      }
      ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
      return true
    }

    if !ok {
      throw NSError(domain: "NativeAvifPlatformDecoder", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "CGContext draw failed"])
    }
    return pixelData
  }

  /// Extract the per-frame delay from container properties.
  /// AVIF/HEICS share property dictionaries similar to GIF/PNG — try common
  /// dictionary keys + fall back to a sensible default.
  private static func extractFrameDelayMs(source: CGImageSource, index: Int) -> Int {
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
      return 100
    }

    // AVIF / HEICS animated containers expose frame delay under their own dictionary.
    // The exact dictionary key string isn't part of Apple's public headers (no
    // documented constant), so we try the empirically observed names.
    for dictKey in ["{HEICS}", "{AVIS}", "{AVIF}"] {
      if let dict = props[dictKey] as? [String: Any] {
        // Prefer unclamped (raw spec value), fall back to clamped delay.
        if let d = (dict["UnclampedDelayTime"] as? Double)
                    ?? (dict["DelayTime"] as? Double) {
          let ms = Int(d * 1000.0)
          return ms > 0 ? ms : 100
        }
      }
    }

    // Generic top-level delay (rare but spec'd)
    if let d = (props["UnclampedDelayTime"] as? Double)
                ?? (props["DelayTime"] as? Double) {
      let ms = Int(d * 1000.0)
      return ms > 0 ? ms : 100
    }

    return 100
  }
}
