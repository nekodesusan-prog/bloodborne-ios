#!/usr/bin/env bash
# bloodborne-ios: the launcher's app with the game inside (as scripts/build-launcher.sh), built
# without a signing team or a device and packed as an IPA that a sideloading tool (Sideloadly,
# AltStore, SideStore) signs on install. No game files and no recompiled library go in: the app
# reads the player's dump from its Documents/game, and the game's code runs through bbcpu's
# translator once JIT is enabled: by the app itself at Play (its StikJIT helper,
# scripts/build-jit-helper.sh) or by StikDebug; without JIT it is interpreted.
#   scripts/build-ipa.sh                # out/Bloodborne.ipa
# Needs what scripts/build-launcher.sh needs, without BB_IOS_TEAM and BB_IOS_DEVICE.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}
launcher=${BB_LAUNCHER:-$PWD/launcher}
config=${BB_LAUNCHER_CONFIG:-release}
if [[ -f runtime/out/ios/librecomp.dylib ]]; then
    echo "build-ipa.sh: runtime/out/ios/librecomp.dylib is built from a game dump and must not go into an IPA; move it away first" >&2
    exit 1
fi
bash runtime/scripts/ios/build-core.sh >/dev/null
bash runtime/scripts/ios/build-gpu.sh >/dev/null
deps=$PWD/runtime/deps/ios-arm64/lib gpu=$PWD/runtime/out/ios/gpu out=$PWD/out/ipa
mkdir -p "$out"
# The app's side of the game, for the launcher (as scripts/build-launcher.sh).
# BB_IOS_BUILTIN_JIT: Play enables JIT through the app's StikJIT helper (app/jit_builtin.m).
cc=(xcrun -sdk iphoneos clang -target arm64-apple-ios18.0 -O2 -g -DBB_IOS_IN_LAUNCHER -DBB_IOS_BUILTIN_JIT
    -I"$PWD/runtime/deps/ios-arm64/include")
"${cc[@]}" -c app/app_main.c -o "$out/app_main.o"
"${cc[@]}" -fobjc-arc -c app/metal_test.m -o "$out/metal_test.o"
"${cc[@]}" -fobjc-arc -c app/orientation.m -o "$out/orientation.o"
"${cc[@]}" -fobjc-arc -c app/jit_builtin.m -o "$out/jit_builtin.o"
rm -f "$out/libbbapp.a"
xcrun -sdk iphoneos ar rcs "$out/libbbapp.a" "$out/app_main.o" "$out/metal_test.o" "$out/orientation.o" "$out/jit_builtin.o"
libs=(-Wl,-force_load,"$out/libbbapp.a" -Wl,-u,_bb_ios_start_game "$PWD/runtime/out/ios/libbbios.a"
      "$gpu/libbbgpu.a" "$gpu/third_party/sirit/src/libsirit.a"
      "$deps"/libspirv-cross-{msl,glsl,core}.a "$deps"/lib{fmt,miniz,xxhash}.a
      "$deps"/lib{avformat,avcodec,swscale,swresample,avutil}.a "$deps"/libboost_container.a "$deps/libSDL3.a")
frameworks=()
for f in AVFoundation AudioToolbox CoreAudio CoreBluetooth CoreFoundation CoreGraphics CoreHaptics \
         CoreMedia CoreMotion CoreVideo Foundation GameController IOSurface Metal MetalFX OpenGLES \
         QuartzCore Security UIKit UniformTypeIdentifiers VideoToolbox; do frameworks+=(-framework "$f"); done
log=$out/xcodebuild.log
# The project copies gen/apple/assets (Tauri's folder, not in Git) into the app; the front end is
# embedded in the launcher's library (scripts/ios-rust.sh), so on a fresh checkout it is empty.
mkdir -p "$launcher/src-tauri/gen/apple/assets"
if ! (cd "$launcher/src-tauri/gen/apple" &&
      xcodebuild -project bloodborne-launcher.xcodeproj -scheme bloodborne-launcher_iOS -configuration "$config" \
          -destination 'generic/platform=iOS' -derivedDataPath "$out/xcode" \
          CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
          OTHER_LDFLAGS="\$(inherited) ${libs[*]} ${frameworks[*]} -lc++ -lz -lbz2 -liconv" \
          build) > "$log" 2>&1; then
    grep -E "error:|Undefined symbols|^  \"_" "$log" | head -40 >&2
    echo "build-ipa.sh: xcodebuild failed ($log)" >&2
    exit 1
fi
app=$out/xcode/Build/Products/$config-iphoneos/Bloodborne.app
# The game's patch file: the game builds its patches from it at start (--patches -).
mkdir -p "$app/patches"
cp -f runtime/patches/Bloodborne.xml "$app/patches/"
# The built-in JIT: StikJIT and the helper extension Play starts.
bash scripts/build-jit-helper.sh "$app"
# Ad hoc signature with the entitlements the sideloading tool carries over when it signs:
# get-task-allow lets StikDebug attach (JIT), and the increased memory limit is granted where the
# App ID has it (GetMoreRam, or a paid team).
cat > "$out/entitlements.plist" <<'EOF'
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
EOF
# Inside out: the framework, the helper, then the app.
codesign --force --sign - --timestamp=none "$app/Frameworks/StikJIT.framework"
codesign --force --sign - --timestamp=none "$app/PlugIns/BloodborneJITHelper.appex"
codesign --force --sign - --entitlements "$out/entitlements.plist" --timestamp=none "$app"
rm -rf "$out/Payload" "$out/../Bloodborne.ipa"
mkdir -p "$out/Payload"
cp -R "$app" "$out/Payload/"
(cd "$out" && zip -qry ../Bloodborne.ipa Payload)
rm -rf "$out/Payload"
echo out/Bloodborne.ipa
