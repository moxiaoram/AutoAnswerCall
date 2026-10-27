TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
PACKAGE_VERSION := 2.1.4
INSTALL_TARGET_PROCESSES := SpringBoard InCallService

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AutoAnswerCall AutoAnswerTRBridge
AutoAnswerCall_FILES := Tweak.x
AutoAnswerCall_CFLAGS := -fobjc-arc
AutoAnswerCall_FRAMEWORKS := Foundation UIKit AVFoundation
# RootHide 运行时：系统进程（如 InCallService）注入时必须链接 libroothide，
# 否则 dylib 在 .jbroot 沙盒外无法重定位（表现为"装了但不注入"）。
# 注意：不加 -l 前缀解析失败时，直接写 .tbd 全路径。
# 按 CallAssist 的方式链接 RootHide 运行时：
# install-name 使用 @loader_path/.jbroot/... 相对路径，
# 这样注入到系统进程（InCallService）时能正确重定向回 /var/jb。
AutoAnswerCall_LDFLAGS := $(THEOS_PROJECT_DIR)/vendor/libroothide.tbd $(THEOS_PROJECT_DIR)/vendor/libsubstrate.tbd
AutoAnswerCall_PLIST := AutoAnswerCall.plist

AutoAnswerTRBridge_FILES := Tweak.x
AutoAnswerTRBridge_CFLAGS := -fobjc-arc
AutoAnswerTRBridge_FRAMEWORKS := Foundation UIKit AVFoundation
AutoAnswerTRBridge_PLIST := AutoAnswerTRBridge.plist

BUNDLE_NAME := AutoAnswerCallPrefs
AutoAnswerCallPrefs_FILES := Preferences/AARootListController.m
AutoAnswerCallPrefs_INFO_PLIST := Preferences/Resources/Info.plist
AutoAnswerCallPrefs_RESOURCE_FILES := Preferences/Resources/Root.plist Preferences/Resources/icon.png Preferences/Resources/icon@2x.png Preferences/Resources/icon@3x.png
AutoAnswerCallPrefs_FRAMEWORKS := UIKit Foundation AVFoundation
AutoAnswerCallPrefs_PRIVATE_FRAMEWORKS := Preferences
AutoAnswerCallPrefs_LDFLAGS := -F$(THEOS_PROJECT_DIR)/vendor
AutoAnswerCallPrefs_INSTALL_PATH := /Library/PreferenceBundles
AutoAnswerCallPrefs_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

include $(THEOS_MAKE_PATH)/bundle.mk


# RootHide 需要为每个 tweak 生成 .roothidepatch 符号链接，
# 否则 dylib 装载后无法正确重定位（表现为"装了但完全不生效"）。
after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries
	@for t in $(TWEAK_NAME); do \
	  ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib \
	    $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$$t.dylib.roothidepatch; \
	  echo "  patched $$t.dylib.roothidepatch"; \
	done
