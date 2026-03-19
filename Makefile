# OS detection
ifndef TARGET_OS
ifeq ($(OS),Windows_NT)
    TARGET_OS := win32
else
    UNAME_S := $(shell uname -s)
    UNAME_M := $(shell uname -m)

    ifeq ($(UNAME_S),Linux)
        ifeq ($(UNAME_M),x86_64)
            TARGET_OS := linux64
        endif
        ifeq ($(UNAME_M),i686)
            TARGET_OS := linux32
        endif
        ifeq ($(UNAME_M),armv6l)
            TARGET_OS := linux-armhf
        endif
    endif

    ifeq ($(UNAME_S),Darwin)
        TARGET_OS := osx
    endif

    ifeq ($(UNAME_S),FreeBSD)
        TARGET_OS := freebsd
    endif
endif
endif # TARGET_OS

# --------------------------------------------------------------------
# Android cross-compile config (set TARGET_OS=android to enable)
# --------------------------------------------------------------------
ifeq ($(TARGET_OS),android)
    # Required: path to Android NDK root
    ANDROID_NDK_HOME ?= $(NDK_HOME)
ifndef ANDROID_NDK_HOME
    $(error ANDROID_NDK_HOME is not set. Example: make TARGET_OS=android ANDROID_NDK_HOME=/path/to/android-ndk-r27)
endif

    # Tunables
    ANDROID_API ?= 24
    ANDROID_ABI ?= arm64-v8a

    # Map ABI -> target triple
    ifeq ($(ANDROID_ABI),arm64-v8a)
        ANDROID_TRIPLE := aarch64-linux-android
    endif
    ifeq ($(ANDROID_ABI),armeabi-v7a)
        ANDROID_TRIPLE := armv7a-linux-androideabi
    endif
    ifeq ($(ANDROID_ABI),x86)
        ANDROID_TRIPLE := i686-linux-android
    endif
    ifeq ($(ANDROID_ABI),x86_64)
        ANDROID_TRIPLE := x86_64-linux-android
    endif

ifndef ANDROID_TRIPLE
    $(error Unsupported ANDROID_ABI '$(ANDROID_ABI)'. Use one of: arm64-v8a, armeabi-v7a, x86, x86_64)
endif

    # Detect host tag for NDK prebuilt toolchain dir
ifndef NDK_HOST_TAG
ifeq ($(OS),Windows_NT)
    NDK_HOST_TAG := windows-x86_64
else
    UNAME_S := $(shell uname -s)
    UNAME_M := $(shell uname -m)
    ifeq ($(UNAME_S),Linux)
        NDK_HOST_TAG := linux-x86_64
    endif
    ifeq ($(UNAME_S),Darwin)
        ifeq ($(UNAME_M),arm64)
            NDK_HOST_TAG := darwin-arm64
        else
            NDK_HOST_TAG := darwin-x86_64
        endif
    endif
endif
endif

    NDK_BIN := $(ANDROID_NDK_HOME)/toolchains/llvm/prebuilt/$(NDK_HOST_TAG)/bin
    TARGET_CC := $(NDK_BIN)/$(ANDROID_TRIPLE)$(ANDROID_API)-clang
    TARGET_CXX := $(NDK_BIN)/$(ANDROID_TRIPLE)$(ANDROID_API)-clang++
    STRIP ?= $(NDK_BIN)/llvm-strip

    ARCHIVE ?= tar
    TARGET := mklittlefs
    TARGET_CFLAGS := -fPIE
    TARGET_CXXFLAGS := -fPIE
    TARGET_LDFLAGS := -pie
endif

# OS-specific settings and build flags
ifeq ($(TARGET_OS),win32)
    ARCHIVE ?= zip
    TARGET := mklittlefs.exe
    TARGET_CFLAGS = -mno-ms-bitfields
    TARGET_LDFLAGS = -Wl,-static -static-libgcc -static-libstdc++ -Wl,-Bstatic -lstdc++ -lpthread -Wl,-Bdynamic
else ifneq ($(TARGET_OS),android)
    ARCHIVE ?= tar
    TARGET := mklittlefs
endif

# Packaging into archive (for 'dist' target)
ifeq ($(ARCHIVE),zip)
    ARCHIVE_CMD := zip -r
    ARCHIVE_EXTENSION := zip
endif
ifeq ($(ARCHIVE),tar)
    ARCHIVE_CMD := tar czf
    ARCHIVE_EXTENSION := tar.gz
endif

STRIP ?= strip

VERSION ?= $(shell git describe --tag)
LITTLEFS_VERSION := $(shell git -C littlefs describe --tags || echo "unknown")
BUILD_CONFIG_NAME ?= -generic

OBJ		:= main.o \
           littlefs/lfs.o \
           littlefs/lfs_util.o

INCLUDES := -Itclap -Iinclude -Ilittlefs -I.

FILES_TO_FORMAT := $(shell find . -not -path './littlefs/*' \( -name '*.c' -o -name '*.cpp' \))
DIFF_FILES := $(addsuffix .diff,$(FILES_TO_FORMAT))

# clang doesn't seem to handle -D "ARG=\"foo bar\"" correctly, so replace spaces with \x20:
BUILD_CONFIG_STR := $(shell echo $(CPPFLAGS) | sed 's- -\\\\x20-g')

# Use Android toolchain compilers when TARGET_OS=android
ifneq ($(TARGET_CC),)
override CC := $(TARGET_CC)
override CXX := $(TARGET_CXX)
endif

override CPPFLAGS := \
    $(INCLUDES) \
    -D VERSION=\"$(VERSION)\" \
    -D LITTLEFS_VERSION=\"$(LITTLEFS_VERSION)\" \
    -D BUILD_CONFIG=\"$(BUILD_CONFIG_STR)\" \
    -D BUILD_CONFIG_NAME=\"$(BUILD_CONFIG_NAME)\" \
    -D __NO_INLINE__ \
    -D LFS_NAME_MAX=255 \
    $(CPPFLAGS)

override CFLAGS := -std=gnu99 -Os -Wall -Wextra -Werror $(TARGET_CFLAGS) $(CFLAGS)
override CXXFLAGS := -std=gnu++11 -Os -Wall -Wextra -Werror $(TARGET_CXXFLAGS) $(CXXFLAGS)
override LDFLAGS := $(TARGET_LDFLAGS) $(LDFLAGS)

DIST_NAME := mklittlefs-$(VERSION)$(BUILD_CONFIG_NAME)-$(TARGET_OS)
DIST_DIR := $(DIST_NAME)
DIST_ARCHIVE := $(DIST_NAME).$(ARCHIVE_EXTENSION)

all: $(TARGET)
dist: $(DIST_ARCHIVE)

$(DIST_ARCHIVE): $(TARGET) $(DIST_DIR)
    cp $(TARGET) $(DIST_DIR)/
    $(ARCHIVE_CMD) $(DIST_ARCHIVE) $(DIST_DIR)

$(TARGET): $(OBJ)
    $(CXX) $^ -o $@ $(LDFLAGS)
    $(STRIP) $(TARGET)

$(DIST_DIR):
    @mkdir -p $@

clean:
    @rm -f $(TARGET) $(OBJ) $(DIFF_FILES)

format-check: $(DIFF_FILES)
    @rm -f $(DIFF_FILES)

test: $(TARGET)
    @./run_tests.sh tests

.PHONY: all clean dist format-check test
