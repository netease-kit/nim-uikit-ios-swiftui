# podspec 配置文件，用于源码依赖时统一配置

module YXConfig
  def self.imuikit_version
    "10.9.30"
  end

  def self.deployment_target
    "16.0"
  end

  def self.swift_version
    "5.0"
  end

  def self.homepage
    "http://netease.im"
  end

  def self.author
    "yunxin engineering department"
  end

  def self.pod_target_xcconfig(s)
    s.pod_target_xcconfig = {
      "BUILD_LIBRARY_FOR_DISTRIBUTION" => "YES",
      "APPLICATION_EXTENSION_API_ONLY" => "NO",
      "DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym",
      "CLANG_ENABLE_EXPLICIT_MODULES" => "NO",
      "DEFINES_MODULE" => "YES",
      "SWIFT_INSTALL_OBJC_HEADER" => "YES",
      "SWIFT_OBJC_INTERFACE_HEADER_NAME" => "$(PRODUCT_MODULE_NAME)-Swift.h"
    }
  end

  def self.license
    { :'type' => "Copyright", :'text' => " Copyright 2022 Netease " }
  end
end
