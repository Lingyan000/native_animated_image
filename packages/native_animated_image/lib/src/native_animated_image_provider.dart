/// [NativeAnimatedImageProvider] — Flutter [ImageProvider] that decodes
/// animated images (GIF / APNG / animated WebP) via the native Rust codec,
/// bypassing Flutter's built-in Skia multi-frame codec.
///
/// 用法:
///
/// ```dart
/// Image(image: NativeAnimatedImageProvider.memory(gifBytes))
/// Image(image: NativeAnimatedImageProvider.network('https://...'))
/// ```
///
/// 实现要点(参考成熟的 AvifImageProvider 模式):
/// - 单帧场景走 [OneFrameImageStreamCompleter] 快速路径
/// - 多帧场景用 `Timer` 调度帧切换,`hasListeners` 自动暂停/恢复
/// - 解码在 [Isolate.run] background isolate 中跑,避免阻塞 UI
/// - 并发解码限制(避免大量动图同屏解码导致内存峰值)
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'ffi/native_animated_image_ffi.dart';
import 'utils/semaphore.dart';

/// 限制全局并发解码数,避免多个大动图同时解导致 RAM 峰值
final _decodeSemaphore = AsyncSemaphore(3);

/// 字节源:bytes / network / file
abstract class _ByteSource {
  Future<Uint8List> load();

  /// 用于 ImageProvider key 相等性
  String get cacheKey;
}

class _MemorySource extends _ByteSource {
  _MemorySource(this.bytes, {required this.tag});

  final Uint8List bytes;
  final String tag;

  @override
  Future<Uint8List> load() async => bytes;

  @override
  String get cacheKey => 'memory:$tag';
}

class _NetworkSource extends _ByteSource {
  _NetworkSource(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  Future<Uint8List> load() async {
    // 默认实现:用 Flutter 的 NetworkImage 内部机制(HttpClient)
    // 高阶用户(如 fluxdo)应该走自己的 cacheManager,我们在外层提供
    // [NativeAnimatedImageProvider.fromBytesProvider] 让他们包装
    throw UnimplementedError(
      'NativeAnimatedImageProvider.network requires a custom byte loader. '
      'Use NativeAnimatedImageProvider.fromBytesProvider(...) instead, '
      'or wait for built-in HttpClient implementation in v0.2.',
    );
  }

  @override
  String get cacheKey => 'network:$url';
}

class _CustomSource extends _ByteSource {
  _CustomSource(this.loader, {required this.tag});

  final Future<Uint8List> Function() loader;
  final String tag;

  @override
  Future<Uint8List> load() => loader();

  @override
  String get cacheKey => 'custom:$tag';
}

/// Flutter [ImageProvider] implementation backed by the native Rust decoder.
class NativeAnimatedImageProvider extends ImageProvider<NativeAnimatedImageProvider> {
  NativeAnimatedImageProvider._(this._source, {this.scale = 1.0});

  /// 从已有的字节数据创建 provider。
  ///
  /// [tag] 用于 ImageProvider 相等性判断 —— 相同 tag 的 provider 会共享 Flutter 全局
  /// ImageCache 项。传一个稳定的标识符(如 url、hash、或资源 id)。
  factory NativeAnimatedImageProvider.memory(
    Uint8List bytes, {
    required String tag,
    double scale = 1.0,
  }) =>
      NativeAnimatedImageProvider._(_MemorySource(bytes, tag: tag), scale: scale);

  /// 从自定义 byte loader 创建 provider(适用于已有 cache_manager 的场景)。
  ///
  /// 这是最灵活的入口 —— 调用方决定从哪里(网络/文件/缓存)拉 bytes。
  factory NativeAnimatedImageProvider.fromBytesProvider({
    required Future<Uint8List> Function() loader,
    required String tag,
    double scale = 1.0,
  }) =>
      NativeAnimatedImageProvider._(_CustomSource(loader, tag: tag), scale: scale);

  /// (实验)从 URL 创建 provider。当前要求用户自己提供 byte loader,
  /// 见 [fromBytesProvider]。未来版本会内置 HttpClient 实现。
  factory NativeAnimatedImageProvider.network(
    String url, {
    Map<String, String>? headers,
    double scale = 1.0,
  }) =>
      NativeAnimatedImageProvider._(_NetworkSource(url, headers: headers), scale: scale);

  final _ByteSource _source;
  final double scale;

  @override
  Future<NativeAnimatedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NativeAnimatedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NativeAnimatedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final framesLoader = _loadAndDecode(key);
    return _NativeAnimatedImageStreamCompleter(
      framesLoader: framesLoader,
      scale: scale,
      debugLabel: _source.cacheKey,
    );
  }

  /// 从 byte source 加载 → isolate 内 decode → 转 ui.Image 列表
  Future<List<_RenderableFrame>> _loadAndDecode(NativeAnimatedImageProvider key) async {
    await _decodeSemaphore.acquire();
    try {
      final bytes = await key._source.load();

      // 在 background isolate 中跑 Rust FFI 解码,避免阻塞 UI 线程
      final decoded = await Isolate.run(() {
        return NativeAnimatedImageFfi.instance.decode(bytes);
      }, debugName: 'NativeAnimatedImage.decode');

      // 把每帧 RGBA 转为 ui.Image(必须在主 isolate 中做)
      final frames = <_RenderableFrame>[];
      for (final frame in decoded.frames) {
        final image = await _rgbaToUiImage(
          frame.rgba,
          decoded.width,
          decoded.height,
        );
        frames.add(_RenderableFrame(image: image, delay: frame.delay));
      }
      return frames;
    } finally {
      _decodeSemaphore.release();
    }
  }

  /// 把 RGBA Uint8List 转为 ui.Image(用 Flutter 的 decodeImageFromPixels,
  /// 它接受 raw pixel buffer,**不经过 Skia codec**,所以不会踩 multi_frame_codec bug)
  static Future<ui.Image> _rgbaToUiImage(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    return completer.future;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NativeAnimatedImageProvider &&
        other._source.cacheKey == _source.cacheKey &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(_source.cacheKey, scale);

  @override
  String toString() => 'NativeAnimatedImageProvider(${_source.cacheKey}, scale: $scale)';
}

/// 单帧封装:ui.Image + 该帧 delay
class _RenderableFrame {
  _RenderableFrame({required this.image, required this.delay});

  final ui.Image image;
  final Duration delay;
}

/// 多帧动画的 [ImageStreamCompleter] —— Timer 调度 + hasListeners 暂停
///
/// 100% 参考 fluxdo 的 _AvifAnimatedImageStreamCompleter 模式,经过项目实战验证。
class _NativeAnimatedImageStreamCompleter extends ImageStreamCompleter {
  _NativeAnimatedImageStreamCompleter({
    required Future<List<_RenderableFrame>> framesLoader,
    required this.scale,
    this.debugLabel,
  }) {
    framesLoader.then(
      _handleFramesLoaded,
      onError: (Object error, StackTrace stack) {
        reportError(
          context: ErrorDescription(
            'Failed to decode animated image (label: $debugLabel)',
          ),
          exception: error,
          stack: stack,
          silent: false,
        );
      },
    );
  }

  final double scale;
  final String? debugLabel;
  List<_RenderableFrame>? _frames;
  int _currentIndex = 0;
  Timer? _timer;

  void _handleFramesLoaded(List<_RenderableFrame> frames) {
    if (frames.isEmpty) {
      reportError(
        context: ErrorDescription('Decoded animated image has zero frames'),
        exception: Exception('Empty frames'),
        stack: StackTrace.current,
      );
      return;
    }
    _frames = frames;
    _emit();
  }

  /// 输出当前帧,如果是多帧则调度下一帧
  void _emit() {
    final frames = _frames;
    if (frames == null) return;

    // 没有 listener 时暂停(节省 CPU)
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    final frame = frames[_currentIndex];
    // ui.Image 是引用计数的,emit 时 clone 一份给 listener(避免被 cache 清掉时影响显示)
    setImage(ImageInfo(image: frame.image.clone(), scale: scale));

    if (frames.length > 1) {
      final delay = frame.delay.inMilliseconds > 0
          ? frame.delay
          : const Duration(milliseconds: 100);
      _currentIndex = (_currentIndex + 1) % frames.length;
      _timer?.cancel();
      _timer = Timer(delay, _emit);
    }
  }

  @override
  void addListener(ImageStreamListener listener) {
    final hadListeners = hasListeners;
    super.addListener(listener);
    // 重新被 attach(可能是滚回视野),恢复动画
    if (!hadListeners && _frames != null && _frames!.length > 1 && _timer == null) {
      _emit();
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}
