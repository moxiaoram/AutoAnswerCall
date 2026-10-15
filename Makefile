TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide
PACKAGE_VERSION := 1.1.0
INSTALL_TARGET_PROCESSES := MobilePhone

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AutoAnswerCall
AutoAnswerCall_FILES := Tweak.x
AutoAnswerCall_CFLAGS := -fobjc-arc
AutoAnswerCall_FRAMEWORKS := Foundation UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
