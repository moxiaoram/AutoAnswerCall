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
$(info [AwemeVision 2.0.3] target: Relaxin v0.4.8 / iOS 17.3 / RootHide / arm64 dylib / iphoneos-arm64e deb)

# 在GitHub Actions中运行时的特殊配置
ifeq ($(GITHUB_ACTIONS),true)
    export INSTALL = 0
    export FINALPACKAGE = 1
endif

export DEBUG = 0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

# The working 1.7 injection used DYYY.dylib + DYYY.plist. On RELAXIN
# White List environments this filename may matter for compatibility.
# Package identity stays independent (com.local.awemevision.relaxin).
LEGACY_LOADER_NAME ?= 1
ifeq ($(LEGACY_LOADER_NAME),1)
  TWEAK_NAME = DYYY
else ifeq ($(LEGACY_LOADER_NAME),0)
  TWEAK_NAME = AwemeVision
else
  $(error LEGACY_LOADER_NAME must be 0 or 1)
endif

# FULL is required for the original settings to work. COMPAT is a diagnostic
# mode only: it deliberately skips many feature hooks. Never ship COMPAT by default.
AWEMEVISION_STARTUP ?= full
ifneq ($(filter $(AWEMEVISION_STARTUP),compat full),$(AWEMEVISION_STARTUP))
  $(error AWEMEVISION_STARTUP must be compat or full)
endif
ifeq ($(AWEMEVISION_STARTUP),full)
  AWEMEVISION_COMPAT_BOOT = 0
else
  AWEMEVISION_COMPAT_BOOT = 1
endif
$(info [AwemeVision 2.0.3] loader=$(TWEAK_NAME), boot=$(AWEMEVISION_STARTUP), probe=$(PROBE_ONLY))


# Minimal injection self-test: build only a constructor marker, with no complex Logos hooks.
# After testing: make clean && make package SCHEME=roothide (without PROBE_ONLY).
ifeq ($(PROBE_ONLY),1)
  $(TWEAK_NAME)_FILES = DYYYInjectionProbe.m
  $(TWEAK_NAME)_CFLAGS = -fobjc-arc -w -DDYYY_PROBE_ONLY=1 -DAWEMEVISION_COMPAT_BOOT=1
else
  $(TWEAK_NAME)_FILES = DYYYInjectionProbe.m DYYY.xm DYYYFloatClearButton.xm DYYYFloatSpeedButton.m DYYYSettings.xm DYYYABTestHook.xm DYYYLongPressPanel.xm DYYYGridLongPressPanel.m DYYYImmersivePlaybackManager.m DYYYAutoNextManager.m DYYYAlbumThumbnailBar.m DYYYPhotoGalleryController.m DYYYSettingsHelper.m DYYYImagePickerDelegate.m DYYYBackupPickerDelegate.m DYYYSettingViewController.m DYYYSystemSettingsViewController.m DYYYBottomAlertView.m DYYYCustomInputView.m DYYYOptionsSelectionView.m DYYYIconOptionsDialogView.m DYYYAboutDialogView.m DYYYKeywordListView.m DYYYFilterSettingsView.m DYYYConfirmCloseView.m DYYYToast.m DYYYManager.m DYYYUtils.m CityManager.m AWMSafeDispatchTimer.m
  $(TWEAK_NAME)_FILES += DYYY408Compatibility.m
  $(TWEAK_NAME)_CFLAGS = -fobjc-arc -w -DAWEMEVISION_COMPAT_BOOT=$(AWEMEVISION_COMPAT_BOOT)
endif
# RootHide: never produce dynamically looked-up undefined imports.
# Link every public framework explicitly and let the macOS linker fail fast
# for unresolved symbols. Private app classes must be looked up via Objective-C
# runtime API (NSClassFromString / %c), not referenced as link-time classes.
ifeq ($(PROBE_ONLY),1)
  $(TWEAK_NAME)_FRAMEWORKS = Foundation
  $(TWEAK_NAME)_LDFLAGS += -Wl,-undefined,error
else
  $(TWEAK_NAME)_LDFLAGS += -Wl,-undefined,error
  $(TWEAK_NAME)_LDFLAGS += -weak_framework AVFAudio
  $(TWEAK_NAME)_FRAMEWORKS = Foundation UIKit AVFoundation CoreMedia CoreAudio CoreGraphics ImageIO Photos QuartzCore MobileCoreServices
endif
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS=0
export ERROR_ON_WARNINGS=0
export LOGOS_DEFAULT_GENERATOR=internal

include $(THEOS_MAKE_PATH)/tweak.mk

# Install only after verifying the .deb on your device. Never install from CI.
# No hard-coded SSH IP addresses or silent push-to-device hooks.
after-package::
	@echo "[AwemeVision] Package created; run scripts/verify_relaxin_deb.py on the .deb."
