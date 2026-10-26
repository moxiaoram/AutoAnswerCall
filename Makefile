TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
PACKAGE_VERSION := 1.7.0
INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AutoAnswerCall
AutoAnswerCall_FILES := Tweak.x
AutoAnswerCall_CFLAGS := -fobjc-arc
AutoAnswerCall_FRAMEWORKS := Foundation UIKit AVFoundation

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
