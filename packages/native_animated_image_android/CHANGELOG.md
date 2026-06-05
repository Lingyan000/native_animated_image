# Changelog

## 0.2.1 - 2026-06-05

- Native binary now includes pure-Rust AVIF decoder (`zenavif` =
  rav1d + zenavif-parse). Animated AVIF on Android, which Android's
  system `ImageDecoder` can decode but doesn't expose per-frame access
  for, now works via the Rust path.
- `tool/build_native.dart android` splits build: stable Rust for
  arm64-v8a / x86_64 / x86, nightly Rust for armeabi-v7a (rav1d needs
  nightly on arm32 due to unstable `stdarch_arm_feature_detection`).


## 0.2.0 - 2026-06-05

- Added Kotlin bridge to system `ImageDecoder` for **static AVIF** on
  Android API 31+. Used by main package's `NativeAvifPlatform`.
- Animated AVIF currently throws `UnsupportedOperationException` —
  callers should fall back to their own backend (e.g. flutter_avif).
- Registered as both `ffiPlugin` (Rust codec) and `pluginClass`
  (AVIF method channel).


## 0.1.0 - 2026-06-04

Initial release. android platform implementation of `native_animated_image` (ships the Rust-built native binary).
