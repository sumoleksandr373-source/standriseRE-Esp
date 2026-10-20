TARGET := iphone:clang:16.5:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

DYLIB_NAME = StandRiseESP

StandRiseESP_FILES = Tweak.mm Overlay.mm
StandRiseESP_CFLAGS = -fobjc-arc -std=c++17
StandRiseESP_CCFLAGS = -std=c++17
StandRiseESP_FRAMEWORKS = UIKit CoreGraphics Foundation
StandRiseESP_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/dylib.mk
