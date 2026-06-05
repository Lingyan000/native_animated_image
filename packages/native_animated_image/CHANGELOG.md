# Changelog

## 0.2.0 - 2026-06-05

**Platform-native AVIF decoder** — new top-level addition.

- Added `NativeAvifPlatform` API: routes AVIF bytes through the OS's
  optimized decoder via a method channel (iOS/macOS `CGImageSourceCreateWithData`
  on system ImageIO, Android `ImageDecoder` on API 31+).
- Targets parity with Safari iOS 16.4+ / macOS 13.4+ AVIF decoding, which
  uses the same Apple-internal ImageIO codepath — community-reported 2-5x
  faster than the bundled third-party libavif/dav1d that `flutter_avif`
  ships.
- Static AVIF works on all listed platforms. Animated AVIF works on
  iOS 16.4+ / macOS 13.4+; Android animated AVIF currently throws so
  callers can fall back to their own backend.
- Suggested usage:
  ```dart
  if (await NativeAvifPlatform.canUse()) {
    final decoded = await NativeAvifPlatform.decode(bytes);
    // decoded.frames[0].rgba is RGBA8888 ready for ui.decodeImageFromPixels
  }
  ```

GIF/APNG/WebP path is unchanged from 0.1.x.

## 0.1.2 - 2026-06-05

- **iOS** ship Rust as a dynamic framework (dylib bundled in
  `.framework`), not a static `.a`. Static-lib FFI symbols get
  dead-stripped (no compile-time caller) and Xcode 16 rejects every
  `-force_load` workaround as an unresolved build input. Dylib is
  loaded by dyld at app startup → all `native_animated_image_*`
  symbols are immediately available to `DynamicLibrary.process()`.
- `tool/build_native.dart ios` now builds cdylib for both ios-arm64
  and ios-arm64-simulator, wraps each in a `.framework` bundle with
  correct install_name + Info.plist (bundle ID with dashes only,
  no underscores), and packs them into an xcframework.

## 0.1.1 - 2026-06-05

- **iOS** podspec: ship `native_animated_image_codec.xcframework` (Apple
  recommended) instead of separate device / simulator `.a` files behind
  SDK-conditional `LIBRARY_SEARCH_PATHS`. Old form broke when consumers
  installed via pub.dev (path was monorepo-relative). Linker error
  "Library 'native_animated_image_codec' not found" is fixed.
- No API / behavior changes to main package; bumped to pull the fixed
  iOS impl.

## 0.1.0 - 2026-06-04

Initial release.

- GIF decoder (full disposal & transparency handling)
- APNG decoder (acTL / fcTL / fdAT, all blend & dispose ops)
- Animated WebP decoder (via `image-webp`)
- `NativeAnimatedImageProvider` — drop-in Flutter `ImageProvider`
- Isolate-based decode, Timer-driven frame scheduling, `hasListeners` auto-pause
- Platforms: macOS, iOS, Android, Windows, Linux
