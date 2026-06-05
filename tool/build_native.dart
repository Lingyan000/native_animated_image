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
  const dstPath =
      'packages/native_animated_image_macos/macos/Libs/libnative_animated_image_codec.dylib';
  final copyRc = _copyFile(
    '$_crateDir/target/release/libnative_animated_image_codec.dylib',
    dstPath,
  );
  if (copyRc != 0) return copyRc;
  // cargo build 写的 install_name 是 absolute path,在别人机器 / CI runner 上
  // dyld 找不到。改成 @rpath/<name> 后,CocoaPods 把 dylib 放进
  // Frameworks/,app 启动时 dyld 走 @rpath search。必须做这一步。
  final renameRc = await Process.run('install_name_tool', [
    '-id',
    '@rpath/libnative_animated_image_codec.dylib',
    dstPath,
  ]);
  stdout.write(renameRc.stdout);
  stderr.write(renameRc.stderr);
  return renameRc.exitCode;
}

Future<int> _buildIos() async {
  if (!Platform.isMacOS) {
    stderr.writeln('ios build must run on macOS host');
    return 1;
  }
  // 1. Build dylib (cdylib) for device + simulator
  var rc = await _runCargo(['build', '--release', '--target', 'aarch64-apple-ios']);
  if (rc != 0) return rc;
  rc = await _runCargo(['build', '--release', '--target', 'aarch64-apple-ios-sim']);
  if (rc != 0) return rc;

  // 2. Wrap each dylib into a proper .framework bundle
  //    (dyld loads the whole library at app startup → DCE bypass).
  final stagingDir = Directory('${Directory.systemTemp.path}/nai_ios_fw_${DateTime.now().millisecondsSinceEpoch}');
  stagingDir.createSync(recursive: true);

  for (final pair in [
    {'rust_target': 'aarch64-apple-ios', 'slice': 'device'},
    {'rust_target': 'aarch64-apple-ios-sim', 'slice': 'simulator'},
  ]) {
    final fwDir = Directory(
        '${stagingDir.path}/${pair['slice']}/native_animated_image_codec.framework');
    fwDir.createSync(recursive: true);

    // Copy dylib as `<framework>/native_animated_image_codec` (no extension)
    final dylibSrc = File(
        '$_crateDir/target/${pair['rust_target']}/release/libnative_animated_image_codec.dylib');
    final binDst = File('${fwDir.path}/native_animated_image_codec');
    dylibSrc.copySync(binDst.path);

    // install_name → @rpath/native_animated_image_codec.framework/native_animated_image_codec
    final installNameRc = await Process.run('install_name_tool', [
      '-id',
      '@rpath/native_animated_image_codec.framework/native_animated_image_codec',
      binDst.path,
    ]);
    if (installNameRc.exitCode != 0) {
      stderr.write(installNameRc.stderr);
      return installNameRc.exitCode;
    }

    // Write minimal Info.plist
    File('${fwDir.path}/Info.plist').writeAsStringSync(_iosFrameworkInfoPlist);
  }

  // 3. Bundle device + simulator frameworks into a single xcframework
  final xcframeworkPath =
      'packages/native_animated_image_ios/ios/Libs/native_animated_image_codec.xcframework';
  final xcframeworkDir = Directory(xcframeworkPath);
  if (xcframeworkDir.existsSync()) {
    xcframeworkDir.deleteSync(recursive: true);
  }
  Directory(xcframeworkPath).parent.createSync(recursive: true);

  final xcResult = await Process.run('xcodebuild', [
    '-create-xcframework',
    '-framework',
    '${stagingDir.path}/device/native_animated_image_codec.framework',
    '-framework',
    '${stagingDir.path}/simulator/native_animated_image_codec.framework',
    '-output',
    xcframeworkPath,
  ], runInShell: true);
  stdout.write(xcResult.stdout);
  stderr.write(xcResult.stderr);

  // Cleanup staging
  stagingDir.deleteSync(recursive: true);

  if (xcResult.exitCode != 0) return xcResult.exitCode;
  stdout.writeln('xcframework (dylib slices): $xcframeworkPath');
  return 0;
}

const String _iosFrameworkInfoPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>native_animated_image_codec</string>
  <key>CFBundleIdentifier</key><string>com.lingyan000.native-animated-image-codec</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>native_animated_image_codec</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>12.0</string>
</dict>
</plist>
''';

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
