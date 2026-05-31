ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = AntiDarkSword

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AntiDarkSword

AntiDarkSword_FILES = main.m ADSAppDelegate.m ADSRootViewController.m ADSDarkEngine.m \
                      dark/offsets.m dark/krw.m dark/kutils.m dark/kexploit_opa334.m \
                      dark/sandbox_escape.m dark/vnode.m

AntiDarkSword_RESOURCE_DIRS = Bundle
AntiDarkSword_FRAMEWORKS = UIKit QuartzCore
AntiDarkSword_CFLAGS = -fobjc-arc -I. -Idark \
	-Wno-error -Wno-deprecated -Wno-implicit-function-declaration \
	-Wno-incompatible-pointer-types-discards-qualifiers -Wno-unused-variable \
	-DADS_HAS_DARK_OFFSETS_H=1 \
	-DADS_HAS_DARK_OFFSETS_M=1 \
	-DADS_HAS_DARK_KRW_H=1 \
	-DADS_HAS_DARK_KRW_M=1 \
	-DADS_HAS_DARK_KUTILS_H=1 \
	-DADS_HAS_DARK_KUTILS_M=1 \
	-DADS_HAS_DARK_KEXPLOIT_H=1 \
	-DADS_HAS_DARK_KEXPLOIT_M=1 \
	-DADS_HAS_DARK_SANDBOX_H=1 \
	-DADS_HAS_DARK_SANDBOX_M=1

AntiDarkSword_CODESIGN_FLAGS = -Sentitlements.plist
AntiDarkSword_PLIST_FILE = Info.plist

include $(THEOS_MAKE_PATH)/application.mk
