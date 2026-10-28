#
#  DYYY
#
#  Copyright (c) 2024 huami. All rights reserved.
#  Channel: @huamidev
#  Created on: 2024/10/04
#
# 本地配置文件（可选）
-include Makefile.local

# 2.0.0: The target device is iPhone15,3 / iOS 17.3 / Relaxin v0.4.8.
# Relaxin uses the RootHide packaging/injection scheme, *not* generic rootless.
SCHEME ?= roothide
ifneq ($(strip $(SCHEME)),roothide)
  $(error This device-targeted release requires SCHEME=roothide; got '$(SCHEME)')
endif
ifneq ($(strip $(THEOS_PACKAGE_SCHEME)),)
  ifneq ($(strip $(THEOS_PACKAGE_SCHEME)),roothide)
    $(error RootHide build required: THEOS_PACKAGE_SCHEME must equal roothide)
  endif
endif
override THEOS_PACKAGE_SCHEME := roothide
export THEOS_PACKAGE_SCHEME

# Third-party App Store app executable is arm64; Debian package arch is
# iphoneos-arm64e for RootHide. Do not confuse the two architecture fields.
ARCHS = arm64
DEB_ARCH = iphoneos-arm64e
TARGET = iphone:clang:latest:17.3
$(info [AwemeVision 2.0.0] target: Relaxin v0.4.8 / iOS 17.3 / RootHide / arm64 dylib / iphoneos-arm64e deb)

# 在GitHub Actions中运行时的特殊配置
ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeVision

# Minimal injection self-test: build only a constructor marker, with no complex Logos hooks.
# After testing: make clean && make package SCHEME=roothide (without PROBE_ONLY).
ifeq ($(PROBE_ONLY),1)
  AwemeVision_FILES = DYYYInjectionProbe.m
  AwemeVision_CFLAGS = -fobjc-arc -w -DDYYY_PROBE_ONLY=1
else
  AwemeVision_FILES = DYYYInjectionProbe.m DYYY.xm DYYYFloatClearButton.xm DYYYFloatSpeedButton.m DYYYSettings.xm DYYYABTestHook.xm DYYYLongPressPanel.xm DYYYGridLongPressPanel.m DYYYImmersivePlaybackManager.m DYYYAutoNextManager.m DYYYAlbumThumbnailBar.m DYYYPhotoGalleryController.m DYYYSettingsHelper.m DYYYImagePickerDelegate.m DYYYBackupPickerDelegate.m DYYYSettingViewController.m DYYYSystemSettingsViewController.m DYYYBottomAlertView.m DYYYCustomInputView.m DYYYOptionsSelectionView.m DYYYIconOptionsDialogView.m DYYYAboutDialogView.m DYYYKeywordListView.m DYYYFilterSettingsView.m DYYYConfirmCloseView.m DYYYToast.m DYYYManager.m DYYYUtils.m CityManager.m AWMSafeDispatchTimer.m
  AwemeVision_FILES += DYYY408Compatibility.m
  AwemeVision_CFLAGS = -fobjc-arc -w
endif
AwemeVision_LDFLAGS = -weak_framework AVFAudio
AwemeVision_FRAMEWORKS = CoreAudio ImageIO
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11
AwemeVision_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS=0
export ERROR_ON_WARNINGS=0
export LOGOS_DEFAULT_GENERATOR=internal

include $(THEOS_MAKE_PATH)/tweak.mk

# Install only after verifying the .deb on your device. Never install from CI.
# No hard-coded SSH IP addresses or silent push-to-device hooks.
after-package::
	@echo "[AwemeVision] Package created; run scripts/verify_relaxin_deb.py on the .deb."
