#!/usr/bin/env bash
# Builds, packages, signs, and notarizes Made distribution archives (.dmg and .zip).
set -euo pipefail

pkg_dir=$(cd "$(dirname "$0")/.." && pwd)

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Builds, packages, signs, and notarizes Made distribution archives (.dmg and .zip).

Options:
  -v, --version <version>       Marketing version string (default: 0.1.0 or \$VERSION)
  -b, --build-number <number>   Build number string (default: 1 or \$BUILD_NUMBER)
  -i, --identity <identity>     Code signing identity (default: - for ad-hoc, or \$SIGNING_IDENTITY)
  -o, --output-dir <directory>  Directory to write distribution artifacts (default: macos/.build/dist)
  -n, --notarize                Submit the disk image for Apple notarization and staple the ticket
  -d, --dry-run                 Perform an ad-hoc packaging run without notarization or release signing
  -h, --help                    Show this help message and exit
EOF
}

version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
identity="${SIGNING_IDENTITY:--}"
output_dir="$pkg_dir/.build/dist"
notarize=false
dry_run=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            version="$2"
            shift 2
            ;;
        -b|--build-number)
            build_number="$2"
            shift 2
            ;;
        -i|--identity)
            identity="$2"
            shift 2
            ;;
        -o|--output-dir)
            output_dir="$2"
            shift 2
            ;;
        -n|--notarize)
            notarize=true
            shift
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "package-release: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$dry_run" = true ]; then
    identity="-"
    notarize=false
fi

if [ "$notarize" = true ] && [ "$identity" = "-" ]; then
    echo "package-release: cannot notarize an ad-hoc signed build. Specify a valid Developer ID signing identity." >&2
    exit 1
fi

bin_dir=$(swift build --package-path "$pkg_dir" --build-system swiftbuild --show-bin-path)
if [ ! -f "$bin_dir/MadeApp" ] || [ ! -f "$bin_dir/MadeKernelService" ]; then
    echo "package-release: binaries missing, building targets..."
    swift build --package-path "$pkg_dir" --build-system swiftbuild
fi

app="$pkg_dir/.build/Made.app"

echo "package-release: assembling app bundle (version $version, build $build_number, identity $identity)..."
VERSION="$version" BUILD_NUMBER="$build_number" SIGNING_IDENTITY="$identity" "$pkg_dir/scripts/bundle-app.sh"

mkdir -p "$output_dir"
dmg_name="Made-$version.dmg"
zip_name="Made-$version.zip"
dmg_path="$output_dir/$dmg_name"
zip_path="$output_dir/$zip_name"

echo "package-release: creating ZIP archive at $zip_path..."
rm -f "$zip_path"
ditto -c -k --keepParent "$app" "$zip_path"

echo "package-release: creating DMG archive at $dmg_path..."
staging=$(mktemp -d "${TMPDIR:-/tmp}/made-dmg-staging.XXXXXX")
cleanup() {
    rm -rf "$staging"
}
trap cleanup EXIT

cp -R "$app" "$staging/Made.app"
ln -s /Applications "$staging/Applications"

rm -f "$dmg_path"
hdiutil create -volname "Made" -srcfolder "$staging" -ov -format UDZO "$dmg_path"

if [ "$identity" != "-" ]; then
    echo "package-release: signing DMG with identity $identity..."
    codesign --force --sign "$identity" --timestamp "$dmg_path"
fi

echo "package-release: verifying DMG integrity..."
hdiutil verify "$dmg_path"

echo "package-release: generating SHA256 checksums..."
(cd "$output_dir" && shasum -a 256 "$dmg_name" "$zip_name" > SHA256SUMS)

if [ "$notarize" = true ]; then
    echo "package-release: submitting $dmg_path for notarization..."
    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    elif [ -n "${APPLE_NOTARY_API_KEY_PATH:-}" ] && [ -n "${APPLE_NOTARY_KEY_ID:-}" ] && [ -n "${APPLE_NOTARY_ISSUER:-}" ]; then
        xcrun notarytool submit "$dmg_path" --key "$APPLE_NOTARY_API_KEY_PATH" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
        xcrun notarytool submit "$dmg_path" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
    else
        echo "package-release: notarization requested but no credentials found." >&2
        echo "Please provide NOTARY_KEYCHAIN_PROFILE, APPLE_NOTARY_API_KEY_PATH/KEY_ID/ISSUER, or APPLE_ID/TEAM_ID/APP_PASSWORD." >&2
        exit 1
    fi

    echo "package-release: stapling notarization ticket to DMG..."
    xcrun stapler staple "$dmg_path"

    echo "package-release: stapling notarization ticket to application..."
    xcrun stapler staple "$app"

    echo "package-release: assessing Gatekeeper acceptance..."
    spctl --assess --type execute --verbose "$app"
fi

echo "package-release: release artifacts created in $output_dir:"
ls -lh "$output_dir"
