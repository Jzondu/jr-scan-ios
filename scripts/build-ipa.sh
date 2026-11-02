#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs .tools
exec > >(tee build/logs/build.log) 2>&1
# Use the runner's stable default, not a guessed /Applications/Xcode path.
xcodebuild -version | tee build/logs/xcode.txt
xcrun --sdk iphoneos --show-sdk-version | tee build/logs/sdk.txt
sw_vers > build/logs/macos.txt
sdk_major=$(xcrun --sdk iphoneos --show-sdk-version | cut -d. -f1)
[[ "$sdk_major" -ge 18 ]] || { echo 'An iOS 18+ SDK is required'; exit 1; }
if xcodebuild -version | grep -Eiq 'beta|preview'; then
  echo 'Use a stable Xcode release'; exit 1
fi
curl --fail --location --retry 3 https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip -o .tools/xcodegen.zip
echo 'a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73  .tools/xcodegen.zip' | shasum -a 256 -c -
unzip -oq .tools/xcodegen.zip -d .tools/xcodegen
.tools/xcodegen/xcodegen/bin/xcodegen --version | tee build/logs/xcodegen.txt
.tools/xcodegen/xcodegen/bin/xcodegen generate --spec project.yml
build_number="${GITHUB_RUN_NUMBER:-1}"
xcodebuild -project JRScan.xcodeproj -scheme JRScan -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  CURRENT_PROJECT_VERSION="$build_number" build
app=build/DerivedData/Build/Products/Release-iphoneos/JRScan.app
[[ -d "$app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" == fi.jzondu.jrscan ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print DTPlatformName' "$app/Info.plist")" == iphoneos ]]
lipo -info "$app/JRScan" | tee build/logs/architecture.txt
lipo "$app/JRScan" -verify_arch arm64
mkdir -p build/package/Payload
# Work only within the build directory; ditto preserves app bundle metadata.
ditto "$app" build/package/Payload/JRScan.app
(cd build/package && /usr/bin/zip -qry ../JRScan.ipa Payload)
unzip -t build/JRScan.ipa
unzip -Z1 build/JRScan.ipa | grep -qx 'Payload/JRScan.app/Info.plist'
{
  echo 'JR Scan — unsigned device IPA, install with AltStore Classic'
  echo "Commit: $(git rev-parse HEAD)"
  echo "Build: $build_number"
  echo "Version: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")"
  echo 'Bundle ID: fi.jzondu.jrscan'
  echo 'Deployment target: iOS 18.0'
  echo "Runner image: ${ImageOS:-local} ${ImageVersion:-unknown}"
  echo "Runner architecture: ${RUNNER_ARCH:-$(uname -m)}"
  date -u
  cat build/logs/xcode.txt build/logs/sdk.txt build/logs/xcodegen.txt
  shasum -a 256 build/JRScan.ipa
} > build/build-info.txt
cat build/build-info.txt
