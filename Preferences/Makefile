include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := AutoAnswerCallPrefs
AutoAnswerCallPrefs_FILES := AACRootListController.m
AutoAnswerCallPrefs_FRAMEWORKS := UIKit Foundation AVFoundation UniformTypeIdentifiers
AutoAnswerCallPrefs_PRIVATE_FRAMEWORKS := Preferences
AutoAnswerCallPrefs_LDFLAGS := -F$(THEOS_PROJECT_DIR)/vendor
AutoAnswerCallPrefs_INSTALL_PATH := /Library/PreferenceBundles
AutoAnswerCallPrefs_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AutoAnswerCallPrefs.bundle
	cp Resources/Root.plist Resources/Info.plist Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png $(THEOS_STAGING_DIR)/Library/PreferenceBundles/AutoAnswerCallPrefs.bundle/
	mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	cp Resources/autoanswer.call.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/autoanswer.call.plist
