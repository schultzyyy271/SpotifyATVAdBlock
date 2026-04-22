ARCHS = arm64
TARGET = appletv:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpotifyATVAdBlock
SpotifyATVAdBlock_FILES = Sources/SpotifyATVAdBlock/Tweak.m
SpotifyATVAdBlock_CFLAGS = -fobjc-arc
SpotifyATVAdBlock_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
