TARGET := iphone:clang:latest:17.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AACAudioProbe
AACAudioProbe_FILES := AudioProbe.xm
AACAudioProbe_CFLAGS := -fobjc-arc
AACAudioProbe_FRAMEWORKS := Foundation AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
