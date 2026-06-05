# Changelog

## 0.2.0 - 2026-06-05

- Added Kotlin bridge to system `ImageDecoder` for **static AVIF** on
  Android API 31+. Used by main package's `NativeAvifPlatform`.
- Animated AVIF currently throws `UnsupportedOperationException` —
  callers should fall back to their own backend (e.g. flutter_avif).
- Registered as both `ffiPlugin` (Rust codec) and `pluginClass`
  (AVIF method channel).


## 0.1.0 - 2026-06-04

Initial release. android platform implementation of `native_animated_image` (ships the Rust-built native binary).
