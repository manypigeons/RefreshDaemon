#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# build-altsign.sh — step 1 of the Theos build (see THEOS-BUILD.md).
#
# Compiles the AltSign-Static product for the iOS device slice and stages
# the artifacts (static libs + AltSign.swiftmodule + OpenSSL) into the
# folder the Makefile's ALTSIGN_DIR / ALTSIGN_MODULE point at.
#
# Usage:  ./build-altsign.sh [--clean]
# Then:   make package
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# Resolve paths relative to this script so it runs from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALTSIGN_SRC="$SCRIPT_DIR/../Dependencies/AltSign"
ARTIFACTS="$ALTSIGN_SRC/.build/artifacts"       # == Makefile ALTSIGN_DIR
MODULES="$ARTIFACTS/Modules"                     # == Makefile ALTSIGN_MODULE
DERIVED="$ALTSIGN_SRC/.build/theos"
OPENSSL="$ALTSIGN_SRC/Dependencies/OpenSSL/iphoneos/lib"

SCHEME="AltSign-Static"
CONFIG="Release"

log() { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ "${1:-}" = "--clean" ] && { log "Cleaning $ARTIFACTS and $DERIVED"; rm -rf "$ARTIFACTS" "$DERIVED"; }

command -v xcodebuild >/dev/null || die "xcodebuild not found (need the Xcode command-line tools / iOS SDK)."
[ -d "$ALTSIGN_SRC" ] || die "AltSign source not found at $ALTSIGN_SRC"

# Canonicalize paths — xcodebuild must run from the package dir, so DERIVED
# has to be absolute (no ".." relative to a directory we're about to leave).
ALTSIGN_SRC="$(cd "$ALTSIGN_SRC" && pwd)"
ARTIFACTS="$ALTSIGN_SRC/.build/artifacts"
MODULES="$ARTIFACTS/Modules"
DERIVED="$ALTSIGN_SRC/.build/theos"
OPENSSL="$ALTSIGN_SRC/Dependencies/OpenSSL/iphoneos/lib"

# ── 0. Fix OpenSSL header path ───────────────────────────────────────
# AltSign's Package.swift header-search-paths point at OpenSSL/ios/include,
# but this checkout ships the iOS headers under OpenSSL/iphoneos/. Without
# this symlink, the ldid target fails to find <openssl/*.h>.
OSSL_ROOT="$ALTSIGN_SRC/Dependencies/OpenSSL"
if [ -d "$OSSL_ROOT/iphoneos" ] && [ ! -e "$OSSL_ROOT/ios" ]; then
  log "Linking OpenSSL/ios -> iphoneos (Package.swift expects ios/)"
  ln -sfn iphoneos "$OSSL_ROOT/ios"
fi

# ── 1. Compile AltSign-Static for a generic iOS device ───────────────
# Run from the package directory so xcodebuild finds Package.swift.
log "Building $SCHEME for generic/platform=iOS (this is the slow part)…"
( cd "$ALTSIGN_SRC" && xcodebuild build \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
) | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

PRODUCTS="$DERIVED/Build/Products/${CONFIG}-iphoneos"
[ -d "$PRODUCTS" ] || die "Build products not found at $PRODUCTS — check the xcodebuild log above."

# ── 2. Stage the artifacts the Makefile expects ──────────────────────
log "Staging artifacts into $ARTIFACTS"
mkdir -p "$ARTIFACTS" "$MODULES"

# The AltSign-Static SwiftPM product emits one relocatable .o per target
# (AltSign, CAltSign, CoreCrypto, CCoreCrypto, ldid, ldid-core) rather than a
# static archive, so -lAltSign has nothing to find. Bundle those objects (plus
# any stray .a) into a single libAltSign.a. `ar rcs` writes the symbol index,
# so the linker resolves the cross-target references in any order.
OBJS=$(find "$PRODUCTS" -maxdepth 1 -name '*.o' | sort)
[ -n "$OBJS" ] || die "No .o files in $PRODUCTS — the AltSign build produced nothing to link."
rm -f "$ARTIFACTS/libAltSign.a"
ar rcs "$ARTIFACTS/libAltSign.a" $OBJS
log "Archived $(printf '%s\n' "$OBJS" | wc -l | tr -d ' ') objects into libAltSign.a"
find "$PRODUCTS" -name '*.a' -exec cp -f {} "$ARTIFACTS/" \; 2>/dev/null || true

# Swift module interface.
if MOD=$(find "$PRODUCTS" -maxdepth 2 -name 'AltSign.swiftmodule' -print -quit); [ -n "$MOD" ]; then
  cp -Rf "$MOD" "$MODULES/"
else
  die "AltSign.swiftmodule not found under $PRODUCTS"
fi

# OpenSSL device static libs (linker often needs these).
if [ -d "$OPENSSL" ]; then
  cp -f "$OPENSSL"/lib*.a "$ARTIFACTS/" 2>/dev/null || true
  log "Copied OpenSSL libs from $OPENSSL"
else
  log "warning: OpenSSL device libs not found at $OPENSSL — add -L/-l manually if the link fails."
fi

# ── 3. Report ────────────────────────────────────────────────────────
log "Staged files:"
ls -1 "$ARTIFACTS"/*.a 2>/dev/null | sed 's/^/    /' || echo "    (no .a files — check the build log)"
echo "    Modules/$(ls "$MODULES" 2>/dev/null | tr '\n' ' ')"

log "Done. Now run:  make package"
