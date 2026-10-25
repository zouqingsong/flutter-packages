Pod::Spec.new do |s|
  s.name             = 'adaptive_viewport'
  s.version          = '0.1.0'
  s.summary          = 'Hinge state and interface orientation for Flutter layouts.'
  s.description      = <<-DESC
Reports the UIHinge status and angle (iOS 27.1+) and the interface orientation
(which long edge has the sensor housing in landscape) to Dart.
                       DESC
  s.homepage         = 'https://github.com/zouqingsong/flutter-packages'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Doitech' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'adaptive_viewport/Sources/adaptive_viewport/**/*.{h,m}'
  s.public_header_files = 'adaptive_viewport/Sources/adaptive_viewport/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.resource_bundles = {'adaptive_viewport_privacy' => ['adaptive_viewport/Sources/adaptive_viewport/PrivacyInfo.xcprivacy']}
end
