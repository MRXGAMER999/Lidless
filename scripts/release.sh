#!/usr/bin/env bash
# Builds, ad-hoc signs and packages a Lidless release into dist/.
#
#   scripts/release.sh [VERSION] [--publish] [--notes FILE]
#
# VERSION (e.g. 0.1.0 or v0.1.0) must match CFBundleShortVersionString of the
# built app (MARKETING_VERSION); without it the app's own version is used.
# Produces dist/Lidless-VERSION.zip, dist/Lidless-VERSION.dmg and
# dist/SHA256SUMS. --publish then runs `gh release create vVERSION` for a tag
# that must already exist on GitHub. Release notes come from --notes FILE, else
# .github/release-notes/vVERSION.md, else GitHub's generated notes.
#
# Environment: LIDLESS_DIST_DIR (default dist/), LIDLESS_DERIVED_DATA (default
# dist/DerivedData), VERBOSE=1 for full xcodebuild output.
#
# Signing is ad hoc ("Sign to Run Locally"): no Developer ID, no hardened
# runtime, no notarization. Xcode signs the nested framework; never `--deep`.

set -euo pipefail

readonly bundle_id="io.github.mrxgamer999.Lidless"

repo_root=$(cd "$(dirname "$0")/.." && pwd)
project="$repo_root/Lidless/Lidless.xcodeproj"
dist="${LIDLESS_DIST_DIR:-$repo_root/dist}"
derived="${LIDLESS_DERIVED_DATA:-$dist/DerivedData}"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

version=""
publish=0
notes=""
while [ $# -gt 0 ]; do
    case "$1" in
        --publish) publish=1 ;;
        --notes)
            [ $# -ge 2 ] || die "--notes needs a file"
            notes="$2"
            shift
            ;;
        -h | --help) usage; exit 0 ;;
        -*) die "unknown option: $1 (see --help)" ;;
        *)
            [ -z "$version" ] || die "only one version, got '$version' and '$1'"
            version="${1#v}"
            ;;
    esac
    shift
done

for tool in xcodebuild ditto hdiutil shasum codesign lipo /usr/libexec/PlistBuddy; do
    command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done
if [ "$publish" -eq 1 ]; then
    command -v gh > /dev/null 2>&1 || die "--publish needs the GitHub CLI (gh)"
    [ -n "$version" ] || die "--publish needs an explicit version"
fi
if [ -n "$notes" ] && [ ! -f "$notes" ]; then
    die "notes file not found: $notes"
fi
if [ -n "$version" ]; then
    printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$' \
        || die "version '$version' is not like 1.2.3 or 1.2.3-beta.1"
fi

mkdir -p "$dist"
archive="$dist/Lidless.xcarchive"
app="$dist/Lidless.app"
staging="$dist/dmg-staging"
mountpoint=""

cleanup() {
    if [ -n "$mountpoint" ]; then
        hdiutil detach "$mountpoint" -quiet > /dev/null 2>&1 || hdiutil detach "$mountpoint" -force -quiet > /dev/null 2>&1 || true
        rmdir "$mountpoint" 2> /dev/null || true
    fi
    rm -rf "$staging"
}
trap cleanup EXIT

rm -rf "$archive" "$app" "$staging"

# 1. Archive (Release, stripped, arm64 only as set in the project).
say "Archiving Release with $(xcodebuild -version | tr '\n' ' ')"
quiet="-quiet"
[ "${VERBOSE:-0}" = "1" ] && quiet=""
# shellcheck disable=SC2086 # $quiet is empty or one flag
xcodebuild $quiet \
    -project "$project" \
    -scheme Lidless \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived" \
    -archivePath "$archive" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    ENABLE_HARDENED_RUNTIME=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    archive

[ -d "$archive/Products/Applications/Lidless.app" ] || die "archive has no Lidless.app"
ditto "$archive/Products/Applications/Lidless.app" "$app"
# Drop stray extended attributes (quarantine, Finder info); the signature doesn't
# cover them. com.apple.provenance can't be removed, but the zip below uses
# --norsrc so no attribute ships as a ._ file inside the bundle.
xattr -cr "$app" 2> /dev/null || true

# 2. Version must match the tag.
plist="$app/Contents/Info.plist"
app_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
app_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist")
if [ -z "$version" ]; then
    version="$app_version"
elif [ "$version" != "$app_version" ]; then
    die "version $version does not match the app's CFBundleShortVersionString $app_version (MARKETING_VERSION)"
fi
[ "$app_id" = "$bundle_id" ] || die "bundle identifier is $app_id, expected $bundle_id"
say "Lidless $version (build $app_build)"

# 3. Signature: ad hoc, sealed, no hardened runtime.
codesign --verify --deep --strict --verbose=2 "$app" 2>&1 | sed 's/^/    /'
sig=$(codesign -dvv "$app" 2>&1)
printf '%s\n' "$sig" | grep -q '^Signature=adhoc$' || die "app is not ad-hoc signed"
printf '%s\n' "$sig" | grep -q "^Identifier=$bundle_id\$" || die "signing identifier is not $bundle_id"
if printf '%s\n' "$sig" | grep -E '^CodeDirectory .*flags=' | grep -q 'runtime'; then
    die "hardened runtime is on; ad-hoc releases ship without it"
fi
# Release sets CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: no debugger entitlement.
if codesign -d --entitlements - --xml "$app" 2> /dev/null | grep -q 'get-task-allow'; then
    die "the app carries com.apple.security.get-task-allow; Release must not"
fi

# 4. Static checks: arm64 only, macOS 12 deployment target, weak links.
"$repo_root/scripts/check-availability.sh" "$app"

# 5. Zip with ditto (what Archive Utility expects); --norsrc keeps ._ files out.
zip="$dist/Lidless-$version.zip"
rm -f "$zip"
say "Packaging $(basename "$zip")"
ditto -c -k --norsrc --keepParent "$app" "$zip"

# 6. DMG: APFS, lzfse (ULFO), with an /Applications link for drag-to-install.
dmg="$dist/Lidless-$version.dmg"
rm -f "$dmg"
say "Packaging $(basename "$dmg")"
mkdir -p "$staging"
ditto "$app" "$staging/Lidless.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Lidless" -srcfolder "$staging" -fs APFS -format ULFO -ov "$dmg"
hdiutil verify -quiet "$dmg"

# Mount read-only without Finder to check what users will see.
mountpoint=$(mktemp -d "${TMPDIR:-/tmp}/lidless-dmg.XXXXXX")
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$mountpoint" "$dmg"
[ -d "$mountpoint/Lidless.app" ] || die "DMG has no Lidless.app"
[ "$(readlink "$mountpoint/Applications")" = "/Applications" ] || die "DMG has no /Applications link"
codesign --verify --deep --strict "$mountpoint/Lidless.app" || die "app inside the DMG fails codesign --verify"
dmg_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$mountpoint/Lidless.app/Contents/Info.plist")
[ "$dmg_version" = "$version" ] || die "DMG app version $dmg_version != $version"
hdiutil detach -quiet "$mountpoint"
rmdir "$mountpoint"
mountpoint=""

# 7. Checksums (relative names, so `shasum -c SHA256SUMS` works in dist/).
(cd "$dist" && shasum -a 256 "$(basename "$zip")" "$(basename "$dmg")" > SHA256SUMS)
say "SHA256SUMS"
sed 's/^/    /' "$dist/SHA256SUMS"

if [ "$publish" -eq 0 ]; then
    say "Done: $zip, $dmg, $dist/SHA256SUMS (not published)"
    exit 0
fi

# 8. Publish to an existing tag (--verify-tag stops gh from creating one).
tag="v$version"
if [ -z "$notes" ] && [ -f "$repo_root/.github/release-notes/$tag.md" ]; then
    notes="$repo_root/.github/release-notes/$tag.md"
fi
set -- "$tag" "$zip" "$dmg" "$dist/SHA256SUMS" --title "Lidless $version" --verify-tag
if [ -n "$notes" ]; then
    set -- "$@" --notes-file "$notes"
else
    set -- "$@" --generate-notes
fi
case "$version" in
    *-*) set -- "$@" --prerelease ;;
esac
say "Publishing GitHub release $tag"
gh release create "$@"
say "Published $tag"
