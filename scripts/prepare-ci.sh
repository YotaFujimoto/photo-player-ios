#!/bin/bash
set -euo pipefail
mkdir -p build dist

actual_xcode="$(xcodebuild -version)"
printf '%s\n' "$actual_xcode" | tee build/toolchain.txt
test "$actual_xcode" = "$(printf 'Xcode %s\nBuild version %s' "$EXPECTED_XCODE_VERSION" "$EXPECTED_XCODE_BUILD")"
printf 'DEVELOPER_DIR=%s\nImageOS=%s\nImageVersion=%s\n' \
  "$DEVELOPER_DIR" "${ImageOS:-unknown}" "${ImageVersion:-unknown}" | tee -a build/toolchain.txt
xcrun --sdk iphoneos --show-sdk-version | tee -a build/toolchain.txt
swift --version | tee -a build/toolchain.txt

# The browser download URL repeatedly returned 504, including bounded retries.
# Use GitHub's official asset API for the same pinned 2.46.0 xcodegen.zip.
# Only this idempotent GET is retried; the pinned digest/version remain mandatory.
curl --fail --location --retry 3 --retry-all-errors \
  --connect-timeout 30 --max-time 120 --retry-max-time 240 \
  --header 'Accept: application/octet-stream' \
  --header "Authorization: Bearer ${GH_TOKEN}" \
  --dump-header build/xcodegen-response-headers.txt \
  "https://api.github.com/repos/yonaskolb/XcodeGen/releases/assets/${XCODEGEN_ASSET_ID}" \
  --output build/xcodegen.zip || {
    download_status=$?
    # Do not publish authorization headers or signed redirect URLs.
    awk 'tolower($0) ~ /^(http\/|x-ratelimit-(limit|remaining|reset):|retry-after:)/ { print }' \
      build/xcodegen-response-headers.txt
    exit "$download_status"
  }
printf '%s  %s\n' "$XCODEGEN_SHA256" build/xcodegen.zip | shasum -a 256 -c -
unzip -q build/xcodegen.zip -d build/xcodegen
xcodegen_bin="$(find build/xcodegen -type f -name xcodegen | head -n 1)"
test -n "$xcodegen_bin"
chmod +x "$xcodegen_bin"
test "$("$xcodegen_bin" --version)" = "Version: $XCODEGEN_VERSION"
"$xcodegen_bin" --version | tee -a build/toolchain.txt
"$xcodegen_bin" generate --spec project.yml

cat build/toolchain.txt >> "$GITHUB_STEP_SUMMARY"
