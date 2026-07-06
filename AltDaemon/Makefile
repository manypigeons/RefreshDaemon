# ── AltDaemon (Theos) ──────────────────────────────────────────────
# Builds the AltStore daemon as a rootless .deb without Xcode.
#
# Prereqs:
#   1. THEOS installed and $THEOS exported.
#   2. AltSign built for-device as a static lib + swiftmodule.
#      See THEOS-BUILD.md. Point ALTSIGN_DIR at the folder that
#      contains libAltSign.a and the .swiftmodule search path.
#
# Build:  make package        (rootless .deb in ./packages)
# Install: make do            (build + copy to device via THEOS_DEVICE_IP)
# ───────────────────────────────────────────────────────────────────

# Rootless daemon. arm64-only: AltSign is currently staged for arm64 only, and
# an arm64 daemon runs fine on arm64e devices. To add arm64e, rebuild AltSign
# with arm64e too (xcodebuild ARCHS="arm64 arm64e"), make libAltSign.a a fat
# archive, and add arm64e back here.
export ARCHS = arm64
export TARGET = iphone:clang:latest:14.0

# Rootless prefix — comment out for a rootful (/usr/bin) build.
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = AltDaemon

# --- AltSign linkage (edit these two lines) -------------------------
# Folder containing libAltSign.a (+ CAltSign/CoreCrypto/ldid/OpenSSL).
ALTSIGN_DIR   = $(THEOS_PROJECT_DIR)/../Dependencies/AltSign/.build/artifacts
# Folder containing AltSign.swiftmodule for the iOS arm64 slice.
ALTSIGN_MODULE = $(ALTSIGN_DIR)/Modules
# --------------------------------------------------------------------

SHARED = $(THEOS_PROJECT_DIR)/../Shared

# AltSign source root — needed so Swift can resolve the CAltSign / CAltSign.Private
# Clang modules that `import AltSign` re-exports (its module map + headers).
ALTSIGN_ROOT = $(THEOS_PROJECT_DIR)/../Dependencies/AltSign
ALTSIGN_MODULEMAP = $(ALTSIGN_ROOT)/AltSign/include/module.modulemap

# Sources: the 5 daemon .swift files here, plus the exact Shared sources
# the Xcode AltDaemon target compiles — symlinked space-free into
# src-shared/ by ./prep-sources.sh (RUN THAT FIRST). Mirrors the target's
# 17-file membership; do not add ALTWrappedError.m (not in the target).
AltDaemon_FILES  = $(wildcard *.swift)
AltDaemon_FILES += $(wildcard src-shared/*.swift)
AltDaemon_FILES += $(wildcard src-shared/*.m)

# Header search paths for the bridging header's #imports.
# -DALTDAEMON selects the AltDaemon-Swift.h branch in NSError+ALTServerError.m;
# -I$(THEOS_OBJ_DIR)/$(THEOS_CURRENT_ARCH)/generated makes that Theos-generated
# Swift interop header findable from the ObjC compile.
AltDaemon_CFLAGS = -I$(SHARED) \
                   -I$(SHARED)/Categories \
                   -I$(SHARED)/Connections \
                   -I$(SHARED)/Errors \
                   -I$(SHARED)/XPC \
                   -I$(THEOS_OBJ_DIR)/$(THEOS_CURRENT_ARCH)/generated \
                   -I$(ALTSIGN_ROOT)/AltSign/include \
                   -DALTDAEMON=1 \
                   -Wno-nullability-completeness \
                   -fobjc-arc

# Swift: bridging header + AltSign module search path.
AltDaemon_SWIFTFLAGS = -import-objc-header $(THEOS_PROJECT_DIR)/AltDaemon-Bridging-Header.h \
                       -I$(SHARED) -I$(SHARED)/Connections \
                       -I$(ALTSIGN_MODULE)
# Make the CAltSign Clang module (re-exported by AltSign) resolvable: point
# Swift's embedded clang at CAltSign's module map + the header search paths
# CAltSign itself uses (mirrors AltSign Package.swift cSettings). The
# OpenSSL/ios path relies on the ios->iphoneos symlink build-altsign.sh makes.
AltDaemon_SWIFTFLAGS += -Xcc -fmodule-map-file=$(ALTSIGN_MODULEMAP) \
                        -Xcc -I$(ALTSIGN_ROOT)/AltSign/include \
                        -Xcc -I$(ALTSIGN_ROOT)/AltSign/include/AltSign \
                        -Xcc -I$(ALTSIGN_ROOT)/Dependencies/minizip \
                        -Xcc -I$(ALTSIGN_ROOT)/Dependencies/OpenSSL/ios/include \
                        -Xcc -I$(ALTSIGN_ROOT)/Dependencies/ldid/libplist/include \
                        -Xcc -I$(ALTSIGN_ROOT)/Dependencies/ldid \
                        -Xcc -Dunix=1

# Link AltSign + its native deps and the frameworks the daemon needs.
# libAltSign.a bundles the AltSign/CAltSign/CoreCrypto/ldid objects; crypto/ssl
# (staged into ALTSIGN_DIR by build-altsign.sh) and z satisfy their references.
# NOTE: AuthKit is intentionally NOT linked. AKDevice/AKAppleIDSession (and
# LSApplicationWorkspace) are obtained at runtime via NSClassFromString, and
# AnisetteDataManager dlopen()s AuthKit itself — so there is no build-time
# framework dependency to resolve.
AltDaemon_LDFLAGS  = -L$(ALTSIGN_DIR)
AltDaemon_LIBRARIES = AltSign crypto ssl z
AltDaemon_FRAMEWORKS = Foundation Security

# Sign the finished binary with the daemon's entitlements.
AltDaemon_CODESIGN_FLAGS = -SAltDaemon.entitlements

# Install to /usr/bin (rootless prefix is added automatically).
AltDaemon_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
