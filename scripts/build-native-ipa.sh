#!/usr/bin/env bash
# bloodborne-ios: the native app (app/native/: a settings screen before Play, as nxnative's) with
# the game inside, packed as out/Bloodborne.ipa for a sideloading tool to sign. It replaces
# bloodborne-launcher's Tauri app on iOS (scripts/build-ipa.sh): no web view, no Rust or npm.
# The game side is the launcher build's (app_main.c with BB_IOS_IN_LAUNCHER and the built-in
# JIT); no game files and no recompiled library go in.
#   scripts/build-native-ipa.sh            # out/Bloodborne.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
if [[ -f runtime/out/ios/librecomp.dylib ]]; then
    echo "build-native-ipa.sh: runtime/out/ios/librecomp.dylib is built from a game dump and must not go into an IPA; move it away first" >&2
    exit 1
fi
bash runtime/scripts/ios/build-core.sh >/dev/null
bash runtime/scripts/ios/build-gpu.sh >/dev/null
deps=$PWD/runtime/deps/ios-arm64/lib gpu=$PWD/runtime/out/ios/gpu out=$PWD/out/native
rm -rf "$out" && mkdir -p "$out/obj"
cc=(xcrun -sdk iphoneos clang -target arm64-apple-ios26.0 -O2 -g)
game=(-DBB_IOS_IN_LAUNCHER -DBB_IOS_BUILTIN_JIT -I"$PWD/runtime/deps/ios-arm64/include")
"${cc[@]}" "${game[@]}" -c app/app_main.c -o "$out/obj/app_main.o"
for source in app/metal_test.m app/orientation.m app/jit_builtin.m; do
    "${cc[@]}" "${game[@]}" -fobjc-arc -c "$source" -o "$out/obj/$(basename "$source").o"
done
for source in app/native/*.m; do
    "${cc[@]}" -fobjc-arc -Wall -Wextra -Wno-unused-parameter -c "$source" -o "$out/obj/native_$(basename "$source").o"
done
frameworks=()
for f in AVFoundation AudioToolbox CoreAudio CoreBluetooth CoreFoundation CoreGraphics CoreHaptics \
         CoreMedia CoreMotion CoreVideo Foundation GameController IOSurface Metal MetalFX OpenGLES \
         QuartzCore Security UIKit UniformTypeIdentifiers VideoToolbox; do frameworks+=(-framework "$f"); done
app=$out/Bloodborne.app
mkdir -p "$app"
"${cc[@]}" "$out"/obj/*.o "$PWD/runtime/out/ios/libbbios.a" \
    "$gpu/libbbgpu.a" "$gpu/third_party/sirit/src/libsirit.a" \
    "$deps"/libspirv-cross-{msl,glsl,core}.a "$deps"/lib{fmt,miniz,xxhash}.a \
    "$deps"/lib{avformat,avcodec,swscale,swresample,avutil}.a "$deps"/libboost_container.a "$deps/libSDL3.a" \
    "${frameworks[@]}" -lc++ -lz -lbz2 -liconv -Wl,-rpath,@executable_path/Frameworks \
    -o "$app/Bloodborne"
# The bundle: Info.plist (the version from Git), the icon (actool), the game's patch file.
version=$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0)
# Apple's formats: up to three numbers (2026.11.6), and a build number that only grows.
short=$(date -u +%Y.%-m.%-d)
sed -e "s/<string>VERSION<\/string>/<string>$short<\/string>/" app/native/Info.plist > "$app/Info.plist"
plutil -replace CFBundleVersion -string "$(date -u +%Y%m%d%H%M)" "$app/Info.plist"
plutil -replace BBCommit -string "$version" "$app/Info.plist"
printf 'APPL????' > "$app/PkgInfo"
xcrun actool app/native/Assets.xcassets --compile "$app" --platform iphoneos --minimum-deployment-target 26.0 \
    --target-device iphone --target-device ipad --app-icon AppIcon \
    --output-partial-info-plist "$out/icon.plist" > "$out/actool.log"
/usr/libexec/PlistBuddy -c "Merge $out/icon.plist" "$app/Info.plist" >/dev/null
mkdir -p "$app/patches"
cp -f runtime/patches/Bloodborne.xml "$app/patches/"
# The built-in JIT: StikJIT and the helper extension Play starts.
bash scripts/build-jit-helper.sh "$app"
# Ad hoc signature with the entitlements the sideloading tool carries over (get-task-allow for the
# JIT debugger, the increased memory limit where the App ID has it), inside out.
cat > "$out/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>get-task-allow</key>
    <true/>
    <key>com.apple.developer.kernel.increased-memory-limit</key>
    <true/>
</dict>
</plist>
PLIST
shopt -s nullglob
for code in "$app"/Frameworks/*.framework "$app"/Frameworks/*.dylib "$app"/PlugIns/*.appex; do
    codesign --force --sign - --timestamp=none "$code"
done
shopt -u nullglob
codesign --force --sign - --entitlements "$out/entitlements.plist" --timestamp=none "$app"
codesign --verify --deep --strict "$app"
rm -rf "$out/Payload" out/Bloodborne.ipa
mkdir -p "$out/Payload"
cp -R "$app" "$out/Payload/"
(cd "$out" && zip -qry ../Bloodborne.ipa Payload)
rm -rf "$out/Payload"
ls -la "$app"
echo out/Bloodborne.ipa
