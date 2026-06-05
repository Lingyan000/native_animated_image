#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'native_animated_image_ios'
  s.version          = '0.1.1'
  s.summary          = 'iOS implementation of native_animated_image (Rust-based GIF/APNG/WebP decoder).'
  s.description      = <<-DESC
A native Rust decoder for animated images, bypassing Flutter's built-in Skia
multi-frame codec to avoid upstream bugs.
                       DESC
  s.homepage         = 'https://github.com/Lingyan000/native_animated_image'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Lingyan000' => 'noreply@github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'

  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS[sdk=iphonesimulator*]' => 'arm64 x86_64',
  }
  s.swift_version = '5.0'

  # XCFramework 内含 device(ios-arm64) + simulator(ios-arm64-simulator) 两个 static lib slice。
  # Xcode 根据 build SDK 自动选对应的 slice 链接,无需手动配 LIBRARY_SEARCH_PATHS。
  # 与单一 .a + SDK-conditional path 相比,xcframework 是 Apple 官方推荐做法。
  s.vendored_frameworks = 'Libs/native_animated_image_codec.xcframework'
end
