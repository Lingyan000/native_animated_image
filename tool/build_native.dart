// Build native binaries for native_animated_image_codec Rust crate and stage
// them into the appropriate per-platform plugin packages.
//
// Usage:
//   dart tool/build_native.dart <platform>
//
// Where <platform> is one of: macos, ios, android, windows, linux, all
//
// - `macos` / `windows` / `linux`: cargo build for host triple (must run on the
//   target OS — cross-compile is too painful)
// - `ios`: cargo build for aarch64-apple-ios + aarch64-apple-ios-sim (macOS host)
// - `android`: cargo-ndk build for arm64-v8a / armeabi-v7a / x86_64 / x86
// - `all`: do everything possible on this host (other platforms emit a warning)

import 'dart:io';

const String _crateDir = 'crates/native_animated_image_codec';

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/build_native.dart <platform>');
    stderr.writeln('  platform: macos | ios | android | windows | linux | all');
    return 64;
  }

  switch (args[0]) {
    case 'macos':
      return _buildMacos();
    case 'ios':
      return _buildIos();
    case 'android':
      return _buildAndroid();
    case 'windows':
      return _buildWindows();
    case 'linux':
      return _buildLinux();
    case 'all':
      return _buildAll();
    default:
      stderr.writeln('Unknown platform: ${args[0]}');
      return 64;
  }
}

Future<int> _buildMacos() async {
  if (!Platform.isMacOS) {
    stderr.writeln('macos build must run on macOS host');
    return 1;
  }
  final rc = await _runCargo(['build', '--release']);
  if (rc != 0) return rc;
  return _copyFile(
    '$_crateDir/target/release/libnative_animated_image_codec.dylib',
    'packages/native_animated_image_macos/macos/Libs/libnative_animated_image_codec.dylib',
  );
}

Future<int> _buildIos() async {
  if (!Platform.isMacOS) {
    stderr.writeln('ios build must run on macOS host');
    return 1;
  }
  // Device (arm64)
  var rc = await _runCargo(['build', '--release', '--target', 'aarch64-apple-ios']);
  if (rc != 0) return rc;
  rc = _copyFile(
    '$_crateDir/target/aarch64-apple-ios/release/libnative_animated_image_codec.a',
    'packages/native_animated_image_ios/ios/Libs/device/libnative_animated_image_codec.a',
  );
  if (rc != 0) return rc;

  // Simulator (arm64 — Apple Silicon)
  rc = await _runCargo(['build', '--release', '--target', 'aarch64-apple-ios-sim']);
  if (rc != 0) return rc;
  return _copyFile(
    '$_crateDir/target/aarch64-apple-ios-sim/release/libnative_animated_image_codec.a',
    'packages/native_animated_image_ios/ios/Libs/simulator/libnative_animated_image_codec.a',
  );
}

Future<int> _buildAndroid() async {
  final ndk = Platform.environment['ANDROID_NDK_HOME'] ??
      '/opt/homebrew/share/android-commandlinetools/ndk/28.2.13676358';
  if (!Directory(ndk).existsSync()) {
    stderr.writeln('ANDROID_NDK_HOME not set or invalid: $ndk');
    stderr.writeln('Install NDK via `brew install android-commandlinetools` '
        'or `sdkmanager "ndk;28.2.13676358"`.');
    return 1;
  }
  final result = await Process.run(
    'cargo',
    [
      'ndk',
      '-t', 'arm64-v8a',
      '-t', 'armeabi-v7a',
      '-t', 'x86_64',
      '-t', 'x86',
      '--platform', '21',
      '-o', '../../packages/native_animated_image_android/android/src/main/jniLibs',
      'build', '--release',
    ],
    workingDirectory: _crateDir,
    environment: {'ANDROID_NDK_HOME': ndk},
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}

Future<int> _buildWindows() async {
  if (!Platform.isWindows) {
    stderr.writeln('windows build must run on Windows host');
    return 1;
  }
  final rc = await _runCargo(['build', '--release']);
  if (rc != 0) return rc;
  return _copyFile(
    '$_crateDir/target/release/native_animated_image_codec.dll',
    'packages/native_animated_image_windows/windows/native_animated_image_codec.dll',
  );
}

Future<int> _buildLinux() async {
  if (!Platform.isLinux) {
    stderr.writeln('linux build must run on Linux host');
    return 1;
  }
  final rc = await _runCargo(['build', '--release']);
  if (rc != 0) return rc;
  return _copyFile(
    '$_crateDir/target/release/libnative_animated_image_codec.so',
    'packages/native_animated_image_linux/linux/libnative_animated_image_codec.so',
  );
}

Future<int> _buildAll() async {
  // Build whatever is possible on this host (don't fail if a target isn't reachable)
  final rcs = <String, int>{};
  if (Platform.isMacOS) {
    rcs['macos'] = await _buildMacos();
    rcs['ios'] = await _buildIos();
    rcs['android'] = await _buildAndroid();
  } else if (Platform.isWindows) {
    rcs['windows'] = await _buildWindows();
  } else if (Platform.isLinux) {
    rcs['linux'] = await _buildLinux();
    rcs['android'] = await _buildAndroid();
  }
  for (final entry in rcs.entries) {
    stdout.writeln('${entry.key}: ${entry.value == 0 ? "OK" : "FAILED (${entry.value})"}');
  }
  return rcs.values.any((rc) => rc != 0) ? 1 : 0;
}

Future<int> _runCargo(List<String> args) async {
  final result = await Process.run('cargo', args,
      workingDirectory: _crateDir, runInShell: true);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}

int _copyFile(String src, String dst) {
  final srcFile = File(src);
  if (!srcFile.existsSync()) {
    stderr.writeln('Source not found: $src');
    return 1;
  }
  final dstFile = File(dst);
  dstFile.parent.createSync(recursive: true);
  srcFile.copySync(dst);
  stdout.writeln('Copied: $src → $dst');
  return 0;
}
