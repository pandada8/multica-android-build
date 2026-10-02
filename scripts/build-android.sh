#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source_dir=$(cd "${1:?Usage: build-android.sh /path/to/patched-upstream}" && pwd)
export EXPO_PUBLIC_API_URL=${EXPO_PUBLIC_API_URL:-https://api.multica.ai}
export EXPO_PUBLIC_WEB_URL=${EXPO_PUBLIC_WEB_URL:-https://multica.ai}
export ANDROID_PACKAGE=${ANDROID_PACKAGE:-ai.multica.mobile.android}
export ANDROID_VERSION_CODE=${ANDROID_VERSION_CODE:-1}
export APP_ENV=production NODE_ENV=production CI=1 EXPO_NO_DOTENV=1
node <<'JS'
for (const name of ['EXPO_PUBLIC_API_URL', 'EXPO_PUBLIC_WEB_URL']) {
  const url = new URL(process.env[name]);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error(`${name} must be an HTTP(S) URL without credentials, query or fragment`);
  }
}
if (!/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/.test(process.env.ANDROID_PACKAGE)) throw new Error('Invalid ANDROID_PACKAGE');
const code = Number(process.env.ANDROID_VERSION_CODE);
if (!Number.isInteger(code) || code < 1 || code > 2100000000) throw new Error('Invalid ANDROID_VERSION_CODE');
JS
cd "$source_dir/apps/mobile"
pnpm exec expo prebuild --platform android --no-install
cd android
# Expo's generated debug key signs this sideload-only release build.
# assembleRelease embeds the JS bundle; a Metro server is not needed.
./gradlew :app:assembleRelease --no-daemon --max-workers=2 -PreactNativeArchitectures=arm64-v8a,x86_64
mkdir -p "$root/artifacts"
cp app/build/outputs/apk/release/app-release.apk "$root/artifacts/multica.apk"
cd "$root/artifacts"
sha256sum multica.apk > multica.apk.sha256
{
  printf 'upstream_commit=%s\n' "$(git -C "$source_dir" rev-parse HEAD)"
  printf 'api_url=%s\nsite_url=%s\npackage=%s\nversion_code=%s\n' "$EXPO_PUBLIC_API_URL" "$EXPO_PUBLIC_WEB_URL" "$ANDROID_PACKAGE" "$ANDROID_VERSION_CODE"
  sha256sum "$root"/patches/*.patch
} > build-info.txt
