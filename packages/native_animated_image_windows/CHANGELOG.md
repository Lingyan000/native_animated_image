# Changelog

## 0.3.0 - 2026-06-08

**BREAKING:** AVIF support removed from `native_animated_image`. See main package
CHANGELOG. Binary rebuilt without zenavif (rav1d), much smaller and no longer
requires nightly Rust on armv7.

## 0.2.2 - 2026-06-05

Native binary rebuilt — no code change in this platform package. Bumped
to stay in sync with `native_animated_image` 0.2.2 which adds Flutter
built-in codec fallback for static webp/png in NativeAnimatedImageProvider.

## 0.2.1 - 2026-06-05

- Version bump alongside main package 0.2.1. Native binary now includes
  pure-Rust AVIF decoder (`zenavif`) — covers AVIF fallback when this
  platform's system decoder isn't available (older OS versions, etc.).


## 0.2.0 - 2026-06-05

- Version bump alongside main package 0.2.0. No platform-side changes —
  no system AVIF decoder available on windows, callers go through Rust path
  for GIF/APNG/WebP and fall back to their own AVIF backend.


## 0.1.0 - 2026-06-04

Initial release. windows platform implementation of `native_animated_image` (ships the Rust-built native binary).
