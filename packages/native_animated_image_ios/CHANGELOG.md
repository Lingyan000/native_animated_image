# Changelog

## 0.2.0 - 2026-06-05

- Added Swift bridge to system ImageIO for AVIF decoding (static + animated
  on iOS 16.4+).
  Used by main package's `NativeAvifPlatform`. Matches Safari performance.
- Registered as both `ffiPlugin` (Rust codec) and `pluginClass`
  (AVIF method channel).


## 0.1.2 - 2026-06-05

- Switch the bundled Rust binary from static `.a` to dynamic framework
  (cdylib in a `.framework` bundle, packed into an xcframework with
  ios-arm64 + ios-arm64-simulator slices).
- Why: static-lib FFI symbols get dead-stripped (no compile-time
  caller); `-force_load` workarounds break in Xcode 16's strict
  build-input validation. Dylib is loaded by dyld at app launch and
  every symbol is immediately visible to `DynamicLibrary.process()`.
- Podspec simplified: just `vendored_frameworks` on the xcframework,
  no more SDK-conditional LIBRARY_SEARCH_PATHS / OTHER_LDFLAGS hacks.

## 0.1.1 - 2026-06-05

- Switch from separate `Libs/{device,simulator}/*.a` + SDK-conditional
  `LIBRARY_SEARCH_PATHS` to a single `Libs/native_animated_image_codec.xcframework`.
- Fixes "Library 'native_animated_image_codec' not found" linker error
  when consumed via pub.dev (the old podspec used a monorepo-relative
  path that didn't survive packaging).

## 0.1.0 - 2026-06-04

Initial release. ios platform implementation of `native_animated_image` (ships the Rust-built native binary).
