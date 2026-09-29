#!/usr/bin/env bash
# Static "older macOS" smoke check for a built Lidless.app.
#
#   scripts/check-availability.sh path/to/Lidless.app [MIN_MACOS]
#
# MIN_MACOS defaults to 12.0. For every Mach-O file in the bundle it checks:
#   - the only architecture is arm64 (no x86_64, no arm64e);
#   - LC_BUILD_VERSION is platform MACOS with minos == MIN_MACOS;
#   - every system library it loads existed on MIN_MACOS, or is weak-linked
#     (LC_LOAD_WEAK_DYLIB) so dyld skips it on older systems;
#   - @rpath libraries are embedded in the bundle.
# It also checks that the app weak-links AppIntents (macOS 13), that
# LSMinimumSystemVersion matches, and that no Debug/test leftovers shipped.
#
# A strongly linked library that is in neither list below fails the check on
# purpose: look up when it first shipped, then add it to the right list.

set -euo pipefail

# Libraries that exist on macOS 12.0, so a strong link is fine. Frameworks by
# name, dylibs by base name without version suffix.
readonly on_macos_12="
    AppKit ApplicationServices AVFoundation Carbon Cocoa ColorSync Combine
    CoreAudio CoreFoundation CoreGraphics CoreImage CoreServices CoreText
    CoreVideo DiskArbitration Foundation IOKit Metal Network OSLog QuartzCore
    Security ServiceManagement SwiftUI SystemConfiguration
    UniformTypeIdentifiers UserNotifications
    libSystem libc++ libobjc libz
    libswiftCore libswiftCoreFoundation libswiftCoreGraphics libswiftCoreImage
    libswiftDarwin libswiftDispatch libswiftFoundation libswiftAppKit
    libswiftIOKit libswiftMetal libswiftObjectiveC libswiftQuartzCore
    libswiftos libswiftsimd libswift_Concurrency
"

# Libraries first shipped after macOS 12.0 (name:version). These must be
# weak-linked and only used behind `#available`.
readonly after_macos_12="
    AppIntents:13.0 BackgroundAssets:13.0 Charts:13.0 ExtensionFoundation:13.0
    ExtensionKit:13.0 MetalFX:13.0 SafetyKit:13.0 ScreenCaptureKit:12.3
    Cinematic:14.0 SensitiveContentAnalysis:14.0 SwiftData:14.0 Symbols:14.0
    TipKit:14.0 Translation:15.0 FoundationModels:26.0
    libswift_RegexParsing:13.0 libswift_StringProcessing:13.0
    libswiftRegexBuilder:13.0 libswiftDistributed:13.0 libswiftSpatial:13.0
    libswiftObservation:14.0 libswiftSynchronization:15.0
"

die() { printf 'error: %s\n' "$*" >&2; exit 2; }

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: $0 path/to/Lidless.app [MIN_MACOS]"
app="${1%/}"
min="${2:-12.0}"
[ -d "$app/Contents/MacOS" ] || die "not an app bundle: $app"
for tool in otool vtool lipo file /usr/libexec/PlistBuddy; do
    command -v "$tool" > /dev/null 2>&1 || die "missing tool: $tool"
done

failures=0
fail() {
    printf '  FAIL %s\n' "$*"
    failures=$((failures + 1))
}

in_list() { # name list
    case " $(printf '%s' "$2" | tr '\n' ' ') " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

introduced_in() { # name -> prints the version, or nothing
    local entry
    for entry in $after_macos_12; do
        if [ "${entry%%:*}" = "$1" ]; then
            printf '%s' "${entry#*:}"
            return
        fi
    done
}

library_name() { # load path -> Foundation, libswiftCore, libSystem, ...
    local base
    case "$1" in
        *.framework/*)
            base="${1%%.framework/*}"
            printf '%s' "${base##*/}"
            ;;
        *)
            base="${1##*/}"
            base="${base%.dylib}"
            printf '%s' "${base%%.*}"
            ;;
    esac
}

# Mach-O files anywhere in the bundle (the app, embedded frameworks, helpers).
machos=()
while IFS= read -r path; do
    case "$(file -b "$path")" in
        Mach-O*) machos+=("$path") ;;
    esac
done < <(find "$app" -type f ! -path "*/_CodeSignature/*" | LC_ALL=C sort)
[ ${#machos[@]} -gt 0 ] || die "no Mach-O files in $app"

main="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")"
[ -f "$main" ] || die "main executable not found: $main"

printf 'Checking %s for macOS %s, arm64 only\n' "$app" "$min"

for macho in "${machos[@]}"; do
    rel="${macho#"$app"/}"
    printf '%s\n' "$rel"

    archs=$(lipo -archs "$macho")
    if [ "$archs" = "arm64" ]; then
        printf '  ok   arch arm64\n'
    else
        fail "architectures are '$archs', expected only arm64"
    fi

    build=$(vtool -show-build "$macho" | awk '/^ *platform /{p=$2} /^ *minos /{print p, $2}' | sort -u | paste -sd ',' -)
    if [ "$build" = "MACOS $min" ]; then
        printf '  ok   LC_BUILD_VERSION MACOS minos %s\n' "$min"
    else
        fail "LC_BUILD_VERSION is '${build:-missing}', expected 'MACOS $min'"
    fi

    strong=""
    while read -r cmd path; do
        name=$(library_name "$path")
        weak=0
        [ "$cmd" = "LC_LOAD_WEAK_DYLIB" ] && weak=1
        case "$path" in
            @rpath/* | @executable_path/* | @loader_path/*)
                embedded="$app/Contents/Frameworks/${path#*/}"
                if [ -e "$embedded" ]; then
                    printf '  ok   %s (embedded)\n' "$name"
                else
                    fail "$path is not embedded in Contents/Frameworks"
                fi
                continue
                ;;
        esac
        newer=$(introduced_in "$name")
        if [ "$weak" -eq 1 ]; then
            printf '  ok   %s (weak%s)\n' "$name" "${newer:+, macOS $newer+}"
        elif [ -n "$newer" ]; then
            fail "$name is strongly linked but first shipped in macOS $newer; weak-link it (-weak_framework $name) and guard its use with #available"
        elif in_list "$name" "$on_macos_12"; then
            strong="$strong $name"
        else
            fail "$name ($path) is strongly linked and unknown to this check; confirm it exists on macOS $min, then add it to a list in $0"
        fi
    done < <(otool -l "$macho" | awk '
        /^ *cmd / { cmd = $2 }
        /^ *name / && cmd ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB$/ { print cmd, $2 }
    ')
    [ -z "$strong" ] || printf '  ok   on macOS %s:%s\n' "$min" "$strong"
done

printf 'Bundle\n'
if otool -l "$main" | awk '/^ *cmd /{cmd=$2} /^ *name /{print cmd, $2}' \
    | grep -q '^LC_LOAD_WEAK_DYLIB /System/Library/Frameworks/AppIntents.framework/'; then
    printf '  ok   AppIntents is LC_LOAD_WEAK_DYLIB in %s\n' "${main##*/}"
else
    fail "${main##*/} does not weak-link AppIntents (OTHER_LDFLAGS -weak_framework AppIntents)"
fi

lsmin=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$app/Contents/Info.plist" 2> /dev/null || true)
if [ "$lsmin" = "$min" ]; then
    printf '  ok   LSMinimumSystemVersion %s\n' "$min"
else
    fail "LSMinimumSystemVersion is '${lsmin:-missing}', expected $min"
fi

leftovers=$(find "$app" \( -name "*.xctest" -o -name "*.debug.dylib" -o -name "__preview.dylib" \) -print)
if [ -z "$leftovers" ]; then
    printf '  ok   no test bundles or debug dylibs\n'
else
    fail "Debug/test leftovers in the bundle: $(printf '%s' "$leftovers" | tr '\n' ' ')"
fi

if [ "$failures" -gt 0 ]; then
    printf '%d check(s) failed\n' "$failures"
    exit 1
fi
printf 'All availability checks passed\n'
