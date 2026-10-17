TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
INSTALL_TARGET_PROCESSES := SpringBoard MobilePhone InCallService

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AutoAnswerCall
AutoAnswerCall_FILES := Tweak.x
AutoAnswerCall_CFLAGS := -fobjc-arc
PACKAGE_VERSION := 1.17.7
AutoAnswerCall_FRAMEWORKS := Foundation UIKit AVFoundation CallKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
