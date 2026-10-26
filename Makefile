TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
PACKAGE_VERSION := 1.8.1
INSTALL_TARGET_PROCESSES := SpringBoard TRCallMonitor

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AutoAnswerCall AutoAnswerTRBridge
AutoAnswerCall_FILES := Tweak.x
AutoAnswerCall_CFLAGS := -fobjc-arc
AutoAnswerCall_FRAMEWORKS := Foundation UIKit AVFoundation
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
