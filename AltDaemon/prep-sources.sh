#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# prep-sources.sh — mirror the exact source membership of the Xcode
# AltDaemon target into a flat, space-free symlink dir (src-shared/) so
# Theos/Make can compile it. Run once (and re-run if the target's file
# list changes). Idempotent.
#
# Why: the daemon pulls several Swift/ObjC files out of ../Shared, and
# one of those lives under a folder named "Server Protocol" (with a
# space) which a Make FILES list cannot represent. Symlinking the
# individual files into src-shared/ removes the space entirely.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DEST=src-shared
rm -rf "$DEST"; mkdir -p "$DEST"

# Exact non-local sources compiled by the Xcode AltDaemon target.
# (The 5 *.swift files in this dir are globbed directly by the Makefile.)
SHARED_FILES=(
  "Extensions/NSXPCConnection+MachServices.swift"
  "Extensions/Result+Conveniences.swift"
  "Extensions/ALTServerError+Conveniences.swift"
  "Extensions/Bundle+AltStore.swift"
  "Connections/XPCConnection.swift"
  "Connections/ConnectionManager.swift"
  "Connections/Connection.swift"
  "Server Protocol/CodableError.swift"
  "Server Protocol/ServerProtocol.swift"
  # Not in the (stale) Xcode target list, but the current shared code needs
  # them: CodableError.sanitizedForSerialization() etc. live here, and their
  # dependency closure (ALTLocalizedError -> UserInfoValue) comes with them.
  "Extensions/NSError+AltStore.swift"
  "Errors/ALTLocalizedError.swift"
  "Errors/UserInfoValue.swift"
  "ALTConstants.m"
  "Categories/CFNotificationName+AltStore.m"
  "Categories/NSError+ALTServerError.m"
  # Needed by NSError+AltStore.swift (ALTWrappedError(error:userInfo:)).
  # Exposed to Swift via the bridging header.
  "Errors/ALTWrappedError.m"
)

for rel in "${SHARED_FILES[@]}"; do
  src="../Shared/$rel"
  [ -f "$src" ] || { echo "✗ missing source: $src" >&2; exit 1; }
  # Flat symlink named after the basename (all basenames are unique).
  ln -sf "../$src" "$DEST/$(basename "$rel")"
done

echo "✓ linked ${#SHARED_FILES[@]} shared sources into $DEST/"
ls -1 "$DEST"
