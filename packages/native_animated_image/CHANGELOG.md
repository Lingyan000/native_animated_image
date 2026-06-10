# Changelog

## 0.3.1 - 2026-06-10

**修复:不透明(无 alpha 通道)动画 WebP 解码必定 crash 整个 app。**

`webp_decoder` 此前固定按 `宽×高×4` 分配每帧 buffer(默认所有 WebP 都带 alpha),
但 `image-webp` 对无 alpha 通道的图期望的是 `宽×高×3`(紧密 RGB)。`read_frame`
(image-webp `decoder.rs:754`)开头即 `assert_eq!(Some(buf.len()), output_buffer_size())`,
两者不等直接 panic;叠加 Cargo profile `panic = "abort"` + FFI 入口无 `catch_unwind`,
panic 逃逸 `extern "C"` 边界 → **SIGABRT,整个 app 崩溃**:

```
assertion `left == right` failed
  left: Some(409600)   // 宽×高×4 (我们给的 buffer)
 right: Some(307200)   // 宽×高×3 (image-webp 期望)
```

任何不透明 RGB 动画 WebP(很常见)都会触发,并非偶发畸形图片。

修复(四层):

- **根治**:`webp_decoder` 改用 `decoder.output_buffer_size()` 分配 buffer,无 alpha
  时把紧密 RGB 展开成 RGBA8888(alpha=255),尺寸永远匹配,从源头消除 assert。
- **防线 1**:FFI 入口 `native_animated_image_decode` 增加 `catch_unwind`,把任何
  解码器 panic(GIF/PNG/WebP 通吃)收敛成新错误码 `kErrPanic`(-6),绝不再 abort 进程。
- **防线 2**:`webp_decoder` 逐帧 `catch_unwind`,畸形帧时截断保留已解出的帧。
- **配套**:Cargo profile `panic = "abort"` → `"unwind"`(catch_unwind 生效的前提)。

## 0.3.0 - 2026-06-08

**BREAKING: AVIF support removed.**

v0.2.x 引入的 `NativeAvifPlatform`(iOS/macOS ImageIO + Android ImageDecoder
+ Rust zenavif 兜底)有 **致命问题**:zenavif 内部 `rav1d-safe 0.5.7` 在 ARM
SIMD 路径(`mc_arm.rs:5905`)有 `usize` underflow,触发即 panic;Cargo profile
`panic = "abort"` 直接 crash 整个 app。线上多次出现:

```
thread 'rav1d-worker-N' panicked at .../rav1d-safe/src/safe_simd/mc_arm.rs:5905:46:
range start index 18446744073709550077 out of range for slice of length 262144
Lost connection to device.
```

zenavif 还要求 armv7 用 nightly Rust toolchain(`stdarch_arm_feature_detection`
unstable),作为生产依赖不合适。

**v0.3.0 把 AVIF 彻底从包里剥离**。如果你需要 AVIF,用
[`flutter_avif`](https://pub.dev/packages/flutter_avif)(libavif + dav1d
C 库,工业标准,稳)。本包保持只做"绕 Skia multi_frame_codec #85831 bug 的
GIF / APNG / animated WebP 解码器"这个清晰职责。

### Removed
- `NativeAvifPlatform`, `NativeAvifPlatformException`(已从 export 移除)
- iOS / macOS Swift `NativeAvifPlatformDecoder` + ImageIO bridge
- Android Kotlin `ImageDecoder` AVIF method handler
- Rust crate `avif_decoder.rs` 模块 + `zenavif` / `zenpixels-convert` /
  `rgb` / `bytemuck` 依赖
- `DecodeError::Avif` variant

### Changed
- AVIF magic bytes(ISO BMFF ftyp / avif / avis / mif1 / msf1)进 Rust
  decode_bytes 现在返 `UnsupportedFormat`,触发 [NativeAnimatedImageProvider]
  内的 Flutter codec fallback(Skia 在 iOS 16.4+ / Android 14+ 支持 AVIF
  静态解码)。如果上层需要完整 AVIF 动画,应该自己 router 到 `flutter_avif`。
- Cargo profile / build 流程精简:armv7 不再需要 nightly toolchain,
  全部 4 ABI 一次 `cargo-ndk build` 完成。
- Binary 大幅瘦身:macOS dylib 从 1.7MB → 474KB(-72%),Android / Linux /
  Windows 类似比例缩减。

### Migration from 0.2.x
```dart
// before
import 'package:native_animated_image/native_animated_image.dart'
    show NativeAvifPlatform;
final decoded = await NativeAvifPlatform.decode(bytes);

// after — 用 flutter_avif
import 'package:flutter_avif/flutter_avif.dart';
final frames = await decodeAvif(bytes);
```

## 0.2.2 - 2026-06-05

**Bug fix: `NativeAnimatedImageProvider` now falls back to Flutter's built-in codec for static images.**

Before 0.2.2, calling `NativeAnimatedImageProvider` with a **static** WebP / PNG /
JPEG image would fail with `kErrUnsupported` (the Rust pipeline only handles
GIF / APNG / animated WebP / AVIF). Callers had to pre-filter URLs to route
static images elsewhere — easy to get wrong (e.g. routing all `.webp` URLs to
this provider would break for static webp, which is the majority case).

Now the provider transparently falls back to
`ui.instantiateImageCodecFromBuffer` when Rust returns `kErrUnsupported`,
so the contract is: **any image the platform can display, this provider
can display.** Static formats avoid the #85831 Skia disposal bug by
construction (the bug only fires on multi-frame disposal paths).

## 0.2.1 - 2026-06-05

**Pure-Rust AVIF decoder added as fallback for the platform-native path.**

- New `crates/native_animated_image_codec/src/avif_decoder.rs` powered by
  [`zenavif`](https://crates.io/crates/zenavif) (rav1d + zenavif-parse) —
  pure Rust, no C dependencies, supports static + animated + alpha.
- `NativeAvifPlatform.decode` now transparently falls back to the Rust
  decoder when the platform's system decoder fails or isn't available.
  Notably covers:
  - **Android animated AVIF** (system `ImageDecoder` can decode animated
    AVIF but won't let us pull individual frames out of an
    `AnimatedImageDrawable` — we go through Rust instead).
  - **iOS < 16.4 / macOS < 13.4** (no system AVIF decoder).
  - **Windows / Linux** (no native bridge).
- Performance: Rust path is ~5% slower than libavif/dav1d C path, so
  Apple/Google's optimized ImageIO/ImageDecoder is still preferred when
  available. Rust catches the rest.


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
