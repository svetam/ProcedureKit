Pod::Spec.new do |s|
  s.name              = "ProcedureKit"
  s.version           = "4.0.0-h1"
  s.summary           = "Powerful Operation subclasses in Swift."
  s.description       = <<-DESC
  
A Swift framework inspired by Apple's WWDC 2015
session Advanced NSOperations: https://developer.apple.com/videos/wwdc/2015/?id=226.

                       DESC
  s.homepage          = "https://github.com/svetam/ProcedureKit"
  s.license           = 'MIT'
  s.authors           = { "ProcedureKit Core Contributors" => "hello@procedure.kit.run" }
  s.source            = { :git => "https://github.com/ProcedureKit/ProcedureKit.git", :tag => s.version.to_s }
  s.module_name       = 'ProcedureKit'
  s.social_media_url  = 'https://twitter.com/danthorpe'
  s.requires_arc      = true
  s.ios.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'
  s.tvos.deployment_target = '9.0'
  s.osx.deployment_target = '10.10'
  
  # Ensure the correct version of Swift is used
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '3.0' }

  # Defaul spec is 'Standard'
  s.default_subspec   = 'Standard'

  # Creates a framework suitable for an iOS, watchOS, tvOS or macOS application
  s.subspec 'Standard' do |ss|
    ss.source_files = [
      'Sources', 
    ]
  end

  # Creates a framework suitable to use for testing code which uses ProcedureKit
  s.subspec 'Testing' do |ss|
    ss.source_files = [
      'Sources/Testing',
    ]
  end
end


