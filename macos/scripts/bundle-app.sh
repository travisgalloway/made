#!/usr/bin/env bash
# Assembles macos/.build/Made.app from the Swift Build products, with the kernel XPC service inside it.
# XPC services launch only from an app bundle's Contents/XPCServices, so `swift run` cannot start one.
set -euo pipefail

pkg_dir=$(cd "$(dirname "$0")/.." && pwd)
bin_dir=$(swift build --package-path "$pkg_dir" --build-system swiftbuild --show-bin-path)
app="$pkg_dir/.build/Made.app"
service="$app/Contents/XPCServices/MadeKernelService.xpc"
# Bundle.module looks in Bundle.main.resourceURL first, so the resource bundle goes in Contents/Resources.
resources="MadeNative_MadeCore.bundle"
# The Icon Composer source; actool compiles it to Assets.car (macOS 26 glass icon) and made.icns (earlier systems).
icon="$pkg_dir/../img/made.icon"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

for product in MadeApp MadeKernelService "$resources"; do
    if [ ! -e "$bin_dir/$product" ]; then
        echo "bundle-app: $bin_dir/$product is missing; run 'make build' first" >&2
        exit 1
    fi
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$service/Contents/MacOS" "$app/Contents/Helpers"

cp "$pkg_dir/Support/MadeApp-Info.plist" "$app/Contents/Info.plist"
cp "$bin_dir/MadeApp" "$app/Contents/MacOS/MadeApp"
cp -R "$bin_dir/$resources" "$app/Contents/Resources/$resources"
cp "$pkg_dir/Sources/MadeCore/Scripting/ScriptingResources/made.d.ts" "$app/Contents/Resources/made.d.ts"

if [ -d "$pkg_dir/Support/Helpers" ]; then
    for helper in "$pkg_dir/Support/Helpers"/*; do
        if [ -f "$helper" ]; then
            cp "$helper" "$app/Contents/Helpers/"
            chmod +x "$app/Contents/Helpers/$(basename "$helper")"
        fi
    done
fi

if [ -f "$pkg_dir/Support/THIRD_PARTY_NOTICES.md" ]; then
    cp "$pkg_dir/Support/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
fi

# actool can exit 0 without writing anything, so success is both outputs existing.
actool_log=$(xcrun actool "$icon" --compile "$app/Contents/Resources" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon made --output-partial-info-plist /dev/null \
    --output-format human-readable-text 2>&1) || true
if [ ! -f "$app/Contents/Resources/Assets.car" ] || [ ! -f "$app/Contents/Resources/made.icns" ]; then
    echo "bundle-app: actool could not compile $icon (it needs Xcode 26 or later and an existing .icon file):" >&2
    echo "$actool_log" >&2
    exit 1
fi
cp "$pkg_dir/Support/MadeKernelService-Info.plist" "$service/Contents/Info.plist"
cp "$bin_dir/MadeKernelService" "$service/Contents/MacOS/MadeKernelService"

# Stamp version and build number into Info.plist files
plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$service/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$service/Contents/Info.plist"

# Sign inside-out: helper binaries first, then the embedded XPC service, then the enclosing app bundle
sign_args=(--force --sign "$SIGNING_IDENTITY" --options runtime)
if [ "$SIGNING_IDENTITY" != "-" ]; then
    sign_args+=(--timestamp)
fi

if [ -d "$app/Contents/Helpers" ]; then
    for helper in "$app/Contents/Helpers"/*; do
        if [ -f "$helper" ]; then
            codesign "${sign_args[@]}" "$helper"
            codesign --verify --strict "$helper"
        fi
    done
fi

codesign "${sign_args[@]}" --entitlements "$pkg_dir/Support/MadeKernelService.entitlements" "$service"
codesign --verify --strict "$service"

codesign "${sign_args[@]}" --entitlements "$pkg_dir/Support/MadeApp.entitlements" "$app"
codesign --verify --deep --strict "$app"

echo "bundle-app: built and signed $app (version $VERSION, build $BUILD_NUMBER, identity $SIGNING_IDENTITY)"

