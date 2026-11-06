#!/usr/bin/env bash
# bloodborne-ios: puts an IPA on this repository's ios-test pre-release as Bloodborne.ipa,
# replacing the one there (GitHub Actions: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA).
#   scripts/publish-ipa.sh path/to/Bloodborne.ipa [source run URL]
set -euo pipefail
ipa=${1:?the IPA to publish}
source=${2:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}}
tag=ios-test
# A broken download is what this replaces: refuse an IPA that is not a whole zip with the app.
unzip -l "$ipa" | grep -q 'Payload/Bloodborne.app/PlugIns/BloodborneJITHelper.appex/' ||
    { echo "publish-ipa.sh: $ipa is not a complete Bloodborne IPA" >&2; exit 1; }
size=$(stat -f%z "$ipa" 2>/dev/null || stat -c%s "$ipa")
sum=$(shasum -a 256 "$ipa" | cut -d' ' -f1)
notes="Test build of the iOS app with the built-in JIT (StikJIT), from ${source}.
No game files are included: you need your own dump of Bloodborne (CUSA03173, 1.09).

Bloodborne.ipa: ${size} bytes, SHA-256 ${sum}. Install it with Sideloadly; see the README."
if gh release view "$tag" >/dev/null 2>&1; then
    gh release edit "$tag" --prerelease --title "iOS test build" --notes "$notes"
else
    gh release create "$tag" --prerelease --target "${GITHUB_SHA:-main}" --title "iOS test build" --notes "$notes"
fi
gh release upload "$tag" "$ipa#Bloodborne.ipa" --clobber
echo "https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/Bloodborne.ipa ($size bytes)"
# Downloaded back from the public link, as a player would: the same bytes and a zip that opens.
url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag}/Bloodborne.ipa"
check=$(mktemp)
for attempt in 1 2 3 4 5 6; do
    curl -fsSL -o "$check" "$url" && [[ $(shasum -a 256 "$check" | cut -d' ' -f1) == "$sum" ]] && break
    sleep 10
done
[[ $(shasum -a 256 "$check" | cut -d' ' -f1) == "$sum" ]] ||
    { echo "publish-ipa.sh: the published IPA does not download as uploaded" >&2; exit 1; }
unzip -tq "$check"
echo "Downloaded back: $(wc -c < "$check") bytes, SHA-256 matches, the zip tests OK"
rm -f "$check"
