// Example app for `native_animated_image`.
//
// Demonstrates loading animated GIF / APNG / WebP via the native Rust
// decoder, bypassing Flutter's built-in Skia multi_frame_codec.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:native_animated_image/native_animated_image.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'native_animated_image example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ExampleHome(),
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  // 三个真实动图样本(都是公开 CDN URL,演示 GIF / APNG / WebP 三种格式)
  static const _samples = <_Sample>[
    _Sample(
      label: 'GIF (disposal=2 bug repro)',
      description:
          'frame 10 has disposal=2 (Restore to Background), which crashes '
          "Flutter's built-in Skia multi_frame_codec (#85831). "
          'Native Rust pipeline handles it correctly.',
      url:
          'https://cdn3.ldstatic.com/original/4X/1/c/c/1cc4d3406a7d2531c7a97e2813d9b700059764bc.gif',
    ),
    _Sample(
      label: 'Animated WebP',
      description: 'Lossy + lossless animation supported.',
      url: 'https://www.gstatic.com/webp/gallery/dancing_banana2.lossless.webp',
    ),
    _Sample(
      label: 'APNG',
      description: 'Full blend/dispose op handling.',
      url:
          'https://upload.wikimedia.org/wikipedia/commons/1/14/Animated_PNG_example_bouncing_beach_ball.png',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('native_animated_image'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _samples.length,
        separatorBuilder: (_, __) => const SizedBox(height: 24),
        itemBuilder: (context, i) => _SampleCard(sample: _samples[i]),
      ),
    );
  }
}

class _Sample {
  const _Sample({
    required this.label,
    required this.description,
    required this.url,
  });
  final String label;
  final String description;
  final String url;
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.sample});
  final _Sample sample;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sample.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(sample.description,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 288,
                height: 288,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: NativeAnimatedImageProvider.fromBytesProvider(
                      loader: () => _httpGetBytes(sample.url),
                      tag: sample.url,
                    ),
                    fit: BoxFit.contain,
                    frameBuilder: (context, child, frame, wasSync) {
                      if (wasSync || frame != null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stack) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('decode failed: $error',
                              style: const TextStyle(color: Colors.red)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(sample.url,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Minimal HTTP byte loader. In real apps you'd plug in your own cache layer.
Future<Uint8List> _httpGetBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode} for $url');
  }
  return response.bodyBytes;
}
