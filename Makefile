TARGET := iphone:clang:latest:15.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := ClashAssist
ClashAssist_FILES := CALabUI.m CAObserve.m CABattleRuntime.m CAEventLog.m CAInterfaceRegistry.m
ClashAssist_LIBRARIES := substrate
ClashAssist_CFLAGS := -fobjc-arc -Wall -Wextra
ClashAssist_FRAMEWORKS := Foundation UIKit
PACKAGE_VERSION := 0.4.6

include $(THEOS_MAKE_PATH)/tweak.mk
