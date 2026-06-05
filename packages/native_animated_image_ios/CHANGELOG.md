# Changelog

## 0.1.1 - 2026-06-05

- Switch from separate `Libs/{device,simulator}/*.a` + SDK-conditional
  `LIBRARY_SEARCH_PATHS` to a single `Libs/native_animated_image_codec.xcframework`.
- Fixes "Library 'native_animated_image_codec' not found" linker error
  when consumed via pub.dev (the old podspec used a monorepo-relative
  path that didn't survive packaging).

## 0.1.0 - 2026-06-04

Initial release. ios platform implementation of `native_animated_image` (ships the Rust-built native binary).
