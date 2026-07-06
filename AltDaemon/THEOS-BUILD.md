# Building AltDaemon with Theos

This folder contains a Theos scaffold (`Makefile`, `control`, `layout/`) that
builds `AltDaemon` into a rootless `.deb` without opening Xcode. The daemon
target itself is trivial for Theos — the real work is producing a for-device
build of **AltSign** and linking it. Read this before running `make`.

## 0. Prerequisites

- [Theos](https://theos.dev) installed, `$THEOS` exported.
- A macOS toolchain with the iOS SDK (Theos uses it under the hood).
- `ldid` on PATH (Theos ships one) for entitlement signing.
- Set `THEOS_DEVICE_IP` if you want `make do` to install over SSH.

## 1. Build AltSign for-device (the hard part)

> **One-command path:** run `./build-altsign.sh` — it does everything in this
> section (xcodebuild + staging into `ALTSIGN_DIR`/`ALTSIGN_MODULE`). Use
> `--clean` to rebuild from scratch. The rest of this section explains what it
> does so you can debug link errors.

Every Swift file in the daemon does `import AltSign`. AltSign is a Swift + ObjC
library with a native stack (OpenSSL, ldid, minizip, libplist,
libimobiledevice, libusbmuxd, libcurl, fragmentzip). Theos will **not** compile
all of that for you. Build it once, then link the artifacts.

The package already declares a static product in
`../Dependencies/AltSign/Package.swift`:

```
.library(name: "AltSign-Static",
         targets: ["AltSign", "CAltSign", "CoreCrypto", "CCoreCrypto", "ldid", "ldid-core"])
```

Build that product for the iOS device slice. SwiftPM won't cleanly
cross-compile it, so drive it through `xcodebuild`:

```sh
cd ../Dependencies/AltSign

xcodebuild build \
  -scheme AltSign-Static \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/theos \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
```

Collect three things from `.build/theos/Build/Products/Release-iphoneos/`:

1. `libAltSign.a` (and any sibling `.a` for CAltSign / CoreCrypto / ldid).
2. `AltSign.swiftmodule/` — the compiled Swift interface.
3. `OpenSSL.xcframework`'s `ios-arm64` static lib (from
   `Dependencies/OpenSSL/Frameworks/OpenSSL.xcframework`).

Stage them into one folder, e.g. `../Dependencies/AltSign/.build/artifacts/`,
with the `.swiftmodule` under a `Modules/` subfolder. The `Makefile` points
`ALTSIGN_DIR` / `ALTSIGN_MODULE` at exactly those two paths — edit them if you
stage elsewhere.

> Tip: if the linker later complains about missing OpenSSL / plist / curl
> symbols, add them to `AltDaemon_LDFLAGS` in the Makefile, e.g.
> `-lssl -lcrypto -lplist-2.0`, and add `-L` for wherever those `.a`s live.

## 2. Build the daemon

```sh
cd AltDaemon
./prep-sources.sh   # symlink the Shared sources the target needs (run once)
make package        # rootless .deb lands in ./packages
```

`prep-sources.sh` mirrors the exact source membership of the Xcode AltDaemon
target (17 files) into a flat, space-free `src-shared/` symlink dir. This is
required because several sources live in `../Shared` — including two under a
folder literally named `Server Protocol` (with a space), which a Make `FILES`
list cannot represent. Re-run it if the target's file list ever changes.

What the Makefile does:

- Compiles the 5 daemon `*.swift` files here plus the `src-shared/` Swift and
  ObjC sources (`ConnectionManager`, `Connection`, `XPCConnection`,
  `ServerProtocol`, `CodableError`, the extensions, `ALTConstants`, and the
  `NSError`/`CFNotificationName` categories). Note: `ALTWrappedError.m` is
  intentionally excluded — it is not a member of the Xcode target.
- Feeds `AltDaemon-Bridging-Header.h` to Swift via `-import-objc-header`, with
  `-I` paths so its `#import`s (`ALTConnection.h`, `ALTConstants.h`, …) resolve.
- Links `AltSign`, `Foundation`, `Security`, and the private `AuthKit`
  framework (for `AKDevice` / `AKAppleIDSession`). `LSApplicationWorkspace` and
  the Security `SecStaticCode*` SPI are resolved from your bridging-header
  declarations at runtime — no extra link flag needed.
- Signs the binary with `AltDaemon.entitlements`
  (`platform-application`, `com.apple.authkit.client.private`, the
  `mobileinstall` SPI allow-list) via `ldid -S`.

## 3. Install

```sh
make do             # build + install to THEOS_DEVICE_IP
# or copy packages/*.deb to the device and: dpkg -i <file>.deb
```

`layout/` carries the launchd plist to `/Library/LaunchDaemons` and the
maintainer scripts (`preinst`/`postinst`/`prerm`) `launchctl (un)load` it. Both
the plist's `ProgramArguments` path and the scripts are written for the
rootless `/var/jb` prefix; drop `THEOS_PACKAGE_SCHEME = rootless` from the
Makefile and revert those paths for a rootful jailbreak.

## Known sharp edges

- **`get-task-allow` + `platform-application`** in the entitlements require the
  jailbreak's `ldid`/`jailbreakd` to actually honor them; ad-hoc signing alone
  won't grant the private AuthKit/mobileinstall entitlements. This is a
  jailbreak-trust concern, not a Theos one.
- **`arm64e`**: only ships if your jailbreak supports arm64e binaries. Drop it
  from `ARCHS` if `dpkg` rejects the arch or the daemon won't launch.
- **AltSign is the whole game.** If `make` fails, it will almost certainly be an
  undefined-symbol error from AltSign or its C deps — iterate on step 1 and the
  `LDFLAGS`, not the daemon.
