#!/usr/bin/env bash
# bloodborne-ios: puts the built-in JIT helper into a built app (scripts/build-ipa.sh calls it).
#   scripts/build-jit-helper.sh path/to/Bloodborne.app
# - StikJIT (github.com/StikDebug/StikJIT, MPL-2.0) built from its source at STIKJIT_TAG into
#   out/stikjit/ (kept between builds) and embedded unmodified as Frameworks/StikJIT.framework;
# - app/JITHelper/ compiled as PlugIns/BloodborneJITHelper.appex, linked against it;
# - the app's Info.plist given what StikJIT needs (local network for LocalDevVPN's tunnel) and
#   file sharing (the pairing file goes into Documents/StikJIT/pairingFile.plist).
# Signing is left to the caller.
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:?the .app to add the helper to}
STIKJIT_TAG=${STIKJIT_TAG:-2.0.1}
work=$PWD/out/stikjit
source=$work/src-$STIKJIT_TAG
framework=$work/StikJIT-$STIKJIT_TAG/StikJIT.framework

if [[ ! -d $framework ]]; then
    echo "== StikJIT $STIKJIT_TAG"
    command -v xcodegen >/dev/null || { echo "build-jit-helper.sh: needs xcodegen (brew install xcodegen)" >&2; exit 1; }
    mkdir -p "$work"
    [[ -d $source ]] || git -c advice.detachedHead=false clone -q --depth 1 -b "$STIKJIT_TAG" \
        https://github.com/StikDebug/StikJIT.git "$source"
    (cd "$source" && xcodegen generate >/dev/null &&
     xcodebuild archive -project StikJIT.xcodeproj -scheme StikJIT -destination 'generic/platform=iOS' \
         -archivePath "$work/archive-$STIKJIT_TAG" BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO \
         CODE_SIGNING_ALLOWED=NO > "$work/build.log" 2>&1) ||
        { grep -E "error:" "$work/build.log" | head -20 >&2; echo "StikJIT failed ($work/build.log)" >&2; exit 1; }
    mkdir -p "$(dirname "$framework")"
    cp -R "$work/archive-$STIKJIT_TAG.xcarchive/Products/Library/Frameworks/StikJIT.framework" "$framework"
fi

info=$app/Info.plist
app_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info")
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info" 2>/dev/null || echo 1.0)

echo "== JIT helper"
mkdir -p "$app/Frameworks" "$app/PlugIns"
rm -rf "$app/Frameworks/StikJIT.framework"
cp -R "$framework" "$app/Frameworks/"
appex=$app/PlugIns/BloodborneJITHelper.appex
rm -rf "$appex" && mkdir -p "$appex"
xcrun -sdk iphoneos swiftc -target arm64-apple-ios26.0 -swift-version 5 -O -parse-as-library -application-extension \
    -module-name BloodborneJITHelper -F "$(dirname "$framework")" -framework StikJIT \
    -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -rpath -Xlinker @executable_path/../../Frameworks \
    app/JITHelper/JITHelper.swift -o "$appex/BloodborneJITHelper"
sed -e "s/BUNDLE_ID/$app_id.JITHelper/" -e "s/VERSION/$version/g" app/JITHelper/Info.plist > "$appex/Info.plist"

# StikJIT finds LocalDevVPN's tunnel through Bonjour (its INTEGRATION.md); the pairing file is
# copied in with Files or the Apple Devices app.
plutil -replace NSLocalNetworkUsageDescription -string "Bloodborne enables JIT through LocalDevVPN (StikJIT)." "$info"
plutil -replace NSBonjourServices -json '["_remotepairing._tcp"]' "$info"
plutil -replace UIFileSharingEnabled -bool YES "$info"
plutil -replace LSSupportsOpeningDocumentsInPlace -bool YES "$info"
echo "$appex"
