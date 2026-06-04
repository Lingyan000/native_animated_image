# native_animated_image

> Native animated image (GIF / APNG / animated WebP) decoder & renderer for Flutter, powered by Rust.

[![pub.dev](https://img.shields.io/badge/pub.dev-coming%20soon-blue)](https://pub.dev/packages/native_animated_image)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Why

Flutter's built-in `multi_frame_codec` (Skia) has long-standing bugs decoding certain animated images:

- [flutter/flutter#85831 — `Could not getPixels for frame N`](https://github.com/flutter/flutter/issues/85831) (open 4+ years)
- [flutter/flutter#94205 — Some frames of gif are decoded incorrectly](https://github.com/flutter/flutter/issues/94205) (open 4+ years)

These bugs cause `broken_image` fallback or rendering glitches for valid GIF/APNG/WebP files that work fine in browsers and native OS image viewers.

`native_animated_image` bypasses Flutter's internal codec by using a **Rust-based decoder** ([`image-rs/gif`](https://github.com/image-rs/image-gif), [`image-rs/png`](https://github.com/image-rs/image-png), [`image-rs/image-webp`](https://github.com/image-rs/image-webp)) and feeding raw RGBA frames directly to Flutter's `RawImage` widget.

## Features

- **GIF**: full animation support, all disposal methods, transparency
- **APNG**: animated PNG with all blend modes & dispose ops
- **animated WebP**: smooth lossy/lossless animation
- **Static fallback**: single-frame images decoded as `ui.Image` for zero overhead
- **Drop-in `ImageProvider`**: works with `Image()`, `DecorationImage`, `Hero`, etc.
- **Auto-pause when off-screen**: respects `TickerMode` semantics via `hasListeners`
- **Memory-safe**: bounded concurrent decode, optional thumbnail PNG cache
- **Cross-platform**: macOS / iOS / Android / Windows / Linux (Web TBD)

## Usage

```dart
import 'package:native_animated_image/native_animated_image.dart';

// As an ImageProvider
Image(image: NativeAnimatedImageProvider.network('https://example.com/foo.gif'))

// From bytes
Image(image: NativeAnimatedImageProvider.memory(bytes))

// As a widget with controller
NativeAnimatedImage.network(
  'https://example.com/foo.webp',
  width: 200,
  height: 200,
  fit: BoxFit.cover,
)
```

## Installation

```yaml
dependencies:
  native_animated_image: ^0.1.0
```

For local development:

```yaml
dependencies:
  native_animated_image:
    git:
      url: https://github.com/Lingyan000/native_animated_image.git
      path: packages/native_animated_image
```

## Architecture

```
flutter app
    │
    ▼  Image(image: NativeAnimatedImageProvider(...))
NativeAnimatedImageProvider (dart, in `native_animated_image`)
    │
    ▼  dart:ffi
native_animated_image_codec (Rust cdylib, in `crates/`)
    ├── gif crate          (GIF)
    ├── png crate          (APNG)
    └── image-webp crate   (animated WebP)
```

Each platform package (`*_macos`, `*_ios`, `*_android`, `*_windows`, `*_linux`) ships a pre-built Rust binary for that platform. The main `native_animated_image` package provides the dart-side API and FFI bindings.

## Status

**Pre-release.** Built primarily to unblock GIF decoding in [fluxdo](https://github.com/Lingyan000/fluxdo). Open issues / PRs welcome.

## License

MIT
