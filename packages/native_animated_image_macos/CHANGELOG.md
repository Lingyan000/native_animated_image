# Changelog

## 0.2.1 - 2026-06-05

- Version bump alongside main package 0.2.1. Native binary now includes
  pure-Rust AVIF decoder (`zenavif`) — covers AVIF fallback when this
  platform's system decoder isn't available (older OS versions, etc.).


## 0.2.0 - 2026-06-05

- Added Swift bridge to system ImageIO for AVIF decoding (static + animated
  on macOS 13.4+).
  Used by main package's `NativeAvifPlatform`. Matches Safari performance.
- Registered as both `ffiPlugin` (Rust codec) and `pluginClass`
  (AVIF method channel).


## 0.1.0 - 2026-06-04

Initial release. macos platform implementation of `native_animated_image` (ships the Rust-built native binary).
