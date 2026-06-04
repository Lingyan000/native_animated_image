#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'native_animated_image_ios'
  s.version          = '0.1.0'
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
    # Static lib 按 SDK 自动选 device / simulator
    'OTHER_LDFLAGS' => '-l"native_animated_image_codec"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]'        => '"${PODS_TARGET_SRCROOT}/Libs/device"',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '"${PODS_TARGET_SRCROOT}/Libs/simulator"',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-l"native_animated_image_codec"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]'        => '"${PODS_TARGET_SRCROOT}/../../../packages/native_animated_image_ios/ios/Libs/device"',
    'LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]' => '"${PODS_TARGET_SRCROOT}/../../../packages/native_animated_image_ios/ios/Libs/simulator"',
  }

  s.preserve_paths   = 'Libs/device/*.a', 'Libs/simulator/*.a'
  s.swift_version = '5.0'
end
