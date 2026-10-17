#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=$(cd "${1:?Usage: build-ios.sh /path/to/patched-upstream}" && pwd)
if [[ $(uname -s) != Darwin ]]; then
  echo 'iOS builds require macOS and Xcode.' >&2
  exit 1
fi
export EXPO_PUBLIC_API_URL=${EXPO_PUBLIC_API_URL:-https://api.multica.ai}
export EXPO_PUBLIC_WEB_URL=${EXPO_PUBLIC_WEB_URL:-https://multica.ai}
export EXPO_BUNDLE_IDENTIFIER_PROD=${IOS_BUNDLE_IDENTIFIER:-ai.multica.mobile.sideload}
export IOS_BUILD_NUMBER=${IOS_BUILD_NUMBER:-1}
export APP_ENV=production NODE_ENV=production CI=1 EXPO_NO_DOTENV=1
node <<'JS'
for (const name of ['EXPO_PUBLIC_API_URL', 'EXPO_PUBLIC_WEB_URL']) {
  const url = new URL(process.env[name]);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error(`${name} must be an HTTP(S) URL without credentials, query or fragment`);
  }
}
if (!/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(process.env.EXPO_BUNDLE_IDENTIFIER_PROD)) throw new Error('Invalid IOS_BUNDLE_IDENTIFIER');
if (!/^[1-9][0-9]{0,8}$/.test(process.env.IOS_BUILD_NUMBER)) throw new Error('Invalid IOS_BUILD_NUMBER');
JS
cd "$source_dir/apps/mobile"
pnpm exec expo prebuild --platform ios --no-install
(cd ios && pod install)
# Expo derives both the native project and shared scheme from the app name.
workspaces=(ios/*.xcworkspace)
[[ ${#workspaces[@]} == 1 && -d ${workspaces[0]} ]] || { echo 'Expected one app workspace' >&2; exit 1; }
scheme=$(basename "${workspaces[0]}" .xcworkspace)
mkdir -p "$root/artifacts/ios"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/multica-ios.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
# Device Release archive embeds JS/Hermes; no signing identity or Apple login.
xcodebuild -workspace "${workspaces[0]}" -scheme "$scheme" \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath "$build_dir/Multica.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  CURRENT_PROJECT_VERSION="$IOS_BUILD_NUMBER" archive
apps=("$build_dir/Multica.xcarchive/Products/Applications/"*.app)
[[ ${#apps[@]} == 1 && -d ${apps[0]} ]] || { echo 'Expected one archived app' >&2; exit 1; }
app=${apps[0]}
[[ -s "$app/main.jsbundle" ]] || { echo 'Release JS bundle is missing' >&2; exit 1; }
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
lipo -verify_arch arm64 "$app/$executable"
# exportArchive requires provisioning. Package the unsigned device app directly.
mkdir -p "$build_dir/package/Payload"
ditto "$app" "$build_dir/package/Payload/$(basename "$app")"
(cd "$build_dir/package" && /usr/bin/zip -qry "$root/artifacts/ios/multica-unsigned.ipa" Payload)
cd "$root/artifacts/ios"
shasum -a 256 multica-unsigned.ipa > multica-unsigned.ipa.sha256
{
  printf 'signing=unsigned-requires-local-resigning\n'
  printf 'upstream_commit=%s\n' "$(git -C "$source_dir" rev-parse HEAD)"
  printf 'bundle_identifier=%s\nbuild_number=%s\n' "$EXPO_BUNDLE_IDENTIFIER_PROD" "$IOS_BUILD_NUMBER"
  printf 'api_url=%s\nsite_url=%s\n' "$EXPO_PUBLIC_API_URL" "$EXPO_PUBLIC_WEB_URL"
  xcodebuild -version
  shasum -a 256 "$root"/patches/*.patch
} > build-info.txt
