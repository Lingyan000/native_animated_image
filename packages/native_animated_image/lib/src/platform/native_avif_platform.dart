/// Bridge to Apple ImageIO (iOS / macOS) / Android ImageDecoder for AVIF.
///
/// Why this exists: Apple Safari (iOS 16.4+ / macOS 13.4+) and Chrome use
/// system-optimized AVIF decoders that are measurably faster than the
/// third-party `flutter_avif` package. By routing through the platform's
/// own ImageIO / ImageDecoder, we get parity with what the browser does.
///
/// Usage: callers should first check [canUse] (cached, fast). If true, call
/// [decode]. If false, the caller must fall back to its own AVIF backend
/// (typically `flutter_avif` for old systems or non-Apple/Android desktop).
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../ffi/native_animated_image_ffi.dart'
    show DecodedAnimatedImage, AnimatedFrame, NativeAnimatedImageFfi;

const _channel = MethodChannel('com.lingyan000.native_animated_image/avif_platform');

class NativeAvifPlatform {
  NativeAvifPlatform._();

  static bool? _cachedCanUse;
  static Future<bool>? _canUseInflight;

  /// Returns true iff the running OS exposes a system AVIF decoder we can use
  /// (currently iOS 16.4+ / macOS 13.4+ via ImageIO; Android API 31+ via
  /// ImageDecoder when that plugin's Kotlin bridge lands).
  ///
  /// Result is cached for the process lifetime — the OS version doesn't change.
  /// Always returns false on platforms without a plugin implementation
  /// (Windows / Linux / Web) so callers cleanly fall back.
  static Future<bool> canUse() {
    final cached = _cachedCanUse;
    if (cached != null) return Future.value(cached);
    final inflight = _canUseInflight;
    if (inflight != null) return inflight;

    if (!Platform.isIOS && !Platform.isMacOS && !Platform.isAndroid) {
      _cachedCanUse = false;
      return Future.value(false);
    }

    final fut = _channel
        .invokeMethod<bool>('canDecodeAvif')
        .then<bool>((v) => v ?? false)
        .catchError((_) => false)
        .whenComplete(() => _canUseInflight = null);
    _canUseInflight = fut;
    return fut.then((v) {
      _cachedCanUse = v;
      return v;
    });
  }

  /// Decode AVIF bytes — tries the platform's system decoder first
  /// (iOS/macOS ImageIO, Android ImageDecoder), then transparently falls back
  /// to the pure-Rust `zenavif` decoder (via FFI) if the platform side
  /// declines or fails.
  ///
  /// Fallback covers e.g.:
  /// - Android animated AVIF (system ImageDecoder doesn't expose per-frame access)
  /// - iOS < 16.4 / macOS < 13.4 (no system AVIF decoder)
  /// - Windows / Linux (no native bridge implemented)
  /// - Edge cases where ImageIO refuses unusual AVIF profiles
  ///
  /// Frame RGBA buffers are tightly packed RGBA8888 (premultiplied alpha on
  /// platform path; straight alpha on Rust fallback path) — both formats
  /// `ui.decodeImageFromPixels` consumes directly.
  static Future<DecodedAnimatedImage> decode(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw NativeAvifPlatformException(
          'empty', 'decode called with empty bytes');
    }

    // Try platform native if the OS supports it
    if (await canUse()) {
      try {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'decodeAvif',
          {'bytes': bytes},
        );
        if (raw != null) {
          return _toDecodedAnimatedImage(raw);
        }
      } on PlatformException {
        // Known fallback cases:
        // - Android `decode_error` for animated AVIF (`UnsupportedOperationException`)
        // - iOS `decode_error` for malformed/unusual AVIF profiles
        // Fall through to Rust path.
        // (Hard errors like 'invalid_args' / 'unsupported_os' also fall through;
        // Rust handles malformed input the same way.)
      }
    }

    // Fallback: pure-Rust `zenavif` via FFI
    return NativeAnimatedImageFfi.instance.decode(bytes);
  }

  static DecodedAnimatedImage _toDecodedAnimatedImage(
      Map<Object?, Object?> raw) {
    final width = (raw['width'] as num).toInt();
    final height = (raw['height'] as num).toInt();
    final loopCount = (raw['loopCount'] as num?)?.toInt() ?? 0;
    final framesList = raw['frames'] as List<Object?>? ?? const [];

    final frames = framesList.map((rawFrame) {
      final m = (rawFrame as Map<Object?, Object?>);
      final rgba = m['rgba'] as Uint8List;
      final delayMs = (m['delayMs'] as num).toInt();
      return AnimatedFrame(
        rgba: rgba,
        delay: Duration(milliseconds: delayMs <= 0 ? 100 : delayMs),
      );
    }).toList(growable: false);

    return DecodedAnimatedImage(
      width: width,
      height: height,
      loopCount: loopCount,
      frames: frames,
    );
  }

  /// Convenience: decode + decode first frame to [ui.Image]. For thumbnail /
  /// single-frame fast paths where you don't need the full frame list.
  static Future<ui.Image> decodeFirstFrameToUiImage(Uint8List bytes) async {
    final decoded = await decode(bytes);
    if (decoded.frames.isEmpty) {
      throw NativeAvifPlatformException('no_frames', 'decoded image has 0 frames');
    }
    final first = decoded.frames.first;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      first.rgba,
      decoded.width,
      decoded.height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    return completer.future;
  }
}

class NativeAvifPlatformException implements Exception {
  NativeAvifPlatformException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'NativeAvifPlatformException($code: $message)';
}
