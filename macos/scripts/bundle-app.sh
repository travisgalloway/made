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

for product in MadeApp MadeKernelService "$resources"; do
    if [ ! -e "$bin_dir/$product" ]; then
        echo "bundle-app: $bin_dir/$product is missing; run 'make build' first" >&2
        exit 1
    fi
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$service/Contents/MacOS"

cp "$pkg_dir/Support/MadeApp-Info.plist" "$app/Contents/Info.plist"
cp "$bin_dir/MadeApp" "$app/Contents/MacOS/MadeApp"
cp -R "$bin_dir/$resources" "$app/Contents/Resources/$resources"
cp "$pkg_dir/Support/MadeKernelService-Info.plist" "$service/Contents/Info.plist"
cp "$bin_dir/MadeKernelService" "$service/Contents/MacOS/MadeKernelService"

# Ad-hoc signatures, inside out: the service, then the app that seals it.
codesign --force --sign - "$service"
codesign --force --sign - "$app"
echo "bundle-app: built $app"
