#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "MythosLog.xcodeproj")
APP_NAME = "MythosLog"
WIDGET_NAME = "MythosLogWidgets"
TEAM_ID = "5865Y52YG7"
IOS_DEPLOYMENT_TARGET = "17.0"

def ensure_group(parent, path)
  parent.find_subpath(path, true)
end

def add_source_files(project, target, paths)
  paths.each do |path|
    group = ensure_group(project.main_group, File.dirname(path))
    ref = group.files.find { |file| file.path == path } || group.new_file(path)
    target.add_file_references([ref], "-fobjc-arc")
  end
end

def add_resources(project, target, paths)
  paths.each do |path|
    group = ensure_group(project.main_group, File.dirname(path))
    ref = group.files.find { |file| file.path == path } || group.new_file(path)
    target.resources_build_phase.add_file_reference(ref)
  end
end

def configure_project(project)
  project.root_object.attributes["LastSwiftUpdateCheck"] = "1700"
  project.root_object.attributes["LastUpgradeCheck"] = "1700"

  project.build_configurations.each do |config|
    config.build_settings["DEVELOPMENT_TEAM"] = TEAM_ID
    config.build_settings["SWIFT_VERSION"] = "5.0"
    config.build_settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
    config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = IOS_DEPLOYMENT_TARGET
    config.build_settings["TARGETED_DEVICE_FAMILY"] = "1,2"
    config.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
    config.build_settings["SWIFT_APPROACHABLE_CONCURRENCY"] = "YES"
    config.build_settings["SWIFT_DEFAULT_ACTOR_ISOLATION"] = "MainActor"
  end
end

def configure_app_target(target)
  target.project.root_object.attributes["TargetAttributes"] ||= {}
  target.project.root_object.attributes["TargetAttributes"][target.uuid] ||= {}
  target.project.root_object.attributes["TargetAttributes"][target.uuid]["SystemCapabilities"] = {
    "com.apple.BackgroundModes" => { "enabled" => 1 },
    "com.apple.HealthKit" => { "enabled" => 1 },
    "com.apple.Push" => { "enabled" => 1 },
    "com.apple.iCloud" => { "enabled" => 1 }
  }

  target.build_configurations.each do |config|
    settings = config.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "studio.curateddesign.MythosLog"
    settings["INFOPLIST_FILE"] = "MythosLog/Info.plist"
    settings["CODE_SIGN_ENTITLEMENTS"] = "MythosLog/MythosLog.entitlements"
    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["CURRENT_PROJECT_VERSION"] = "1"
    settings["MARKETING_VERSION"] = "1.0"
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks"]
    settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  end
end

def configure_widget_target(target)
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "studio.curateddesign.MythosLog.widgets"
    settings["INFOPLIST_FILE"] = "MythosLogWidgets/Info.plist"
    settings["CODE_SIGN_ENTITLEMENTS"] = "MythosLogWidgets/MythosLogWidgets.entitlements"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["CURRENT_PROJECT_VERSION"] = "1"
    settings["MARKETING_VERSION"] = "1.0"
    settings["GENERATE_INFOPLIST_FILE"] = "NO"
    settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
    settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
    settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
    settings["SKIP_INSTALL"] = "YES"
  end
end

def configure_test_target(target)
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "studio.curateddesign.MythosLogTests"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["CURRENT_PROJECT_VERSION"] = "1"
    settings["MARKETING_VERSION"] = "1.0"
    settings["GENERATE_INFOPLIST_FILE"] = "YES"
    settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
    settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/#{APP_NAME}.app/#{APP_NAME}"
    settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  end
end

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
configure_project(project)

app_target = project.new_target(:application, APP_NAME, :ios, IOS_DEPLOYMENT_TARGET)
widget_target = project.new_target(:app_extension, WIDGET_NAME, :ios, IOS_DEPLOYMENT_TARGET)
test_target = project.new_target(:unit_test_bundle, "MythosLogTests", :ios, IOS_DEPLOYMENT_TARGET)

configure_app_target(app_target)
configure_widget_target(widget_target)
configure_test_target(test_target)

app_sources = Dir.glob(File.join(ROOT, "MythosLog/**/*.swift"))
                .map { |path| path.delete_prefix("#{ROOT}/") }
                .sort
app_resources = ["MythosLog/Assets.xcassets"]

widget_sources = (
  Dir.glob(File.join(ROOT, "MythosLogWidgets/**/*.swift")).map { |path| path.delete_prefix("#{ROOT}/") } +
  [
    "MythosLog/App/AppIdentity.swift",
    "MythosLog/Support/Formatting.swift",
    "MythosLog/Support/TrainingRoute.swift",
    "MythosLog/Support/WidgetSnapshot.swift",
    "MythosLog/Support/QuickLogQueue.swift"
  ]
).uniq.sort

test_sources = Dir.glob(File.join(ROOT, "MythosLogTests/**/*.swift"))
                .map { |path| path.delete_prefix("#{ROOT}/") }
                .sort

add_source_files(project, app_target, app_sources)
add_resources(project, app_target, app_resources)

add_source_files(project, widget_target, widget_sources)

add_source_files(project, test_target, test_sources)
test_target.add_dependency(app_target)
app_target.add_dependency(widget_target)

embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == "Embed App Extensions" } ||
  app_target.new_copy_files_build_phase("Embed App Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_phase.add_file_reference(widget_target.product_reference, true)
build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, APP_NAME, true)

project.save
puts "Generated #{PROJECT_PATH}"
