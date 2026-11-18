#!/bin/bash
set -euo pipefail

# Xcode Cloud hook: runs after the clone, before xcodebuild archives
# ios/Runner.xcworkspace. Installs Flutter and writes the Flutter build config
# (ios/Flutter/Generated.xcconfig) — version, build number and the
# dart-defines, which a plain Xcode archive would otherwise drop.
# The dart-define values come from the workflow's environment variables
# (MICROSOFT_CLIENT_ID, GOOGLE_WEB_CLIENT_ID, MICROSOFT_TENANT_ID, FIREBASE_*).
# Setup and the overall flow: docs/store-builds.md.

# Keep in step with FLUTTER_VERSION in .github/workflows/app-store.yml.
FLUTTER_VERSION=3.47.0

: "${MICROSOFT_CLIENT_ID:?set MICROSOFT_CLIENT_ID in the Xcode Cloud workflow environment}"

cd "$CI_PRIMARY_REPOSITORY_PATH/eduai-app"

# The tag pushed by the App store workflow names the channel, which picks the
# API (dart_defines.sh), and the version (CFBundleShortVersionString):
# app-vX.Y.Z for a release, app-internal-X.Y.Z-N / app-beta-X.Y.Z-N for test
# builds. A start without such a tag has no channel and so is refused.
case "${CI_TAG:-}" in
  app-v*)
    export APP_CHANNEL=release
    version_name=${CI_TAG#app-v}
    ;;
  app-internal-* | app-beta-*)
    export APP_CHANNEL=$(sed -E 's/^app-([a-z]+)-.*/\1/' <<< "$CI_TAG")
    version_name=$(sed -E 's/^app-[a-z]+-(.+)-[0-9]+$/\1/' <<< "$CI_TAG")
    ;;
  *)
    echo "Start this build from the App store build workflow: it pushes the app-v / app-internal- / app-beta- tag that names the channel (got ${CI_TAG:-no tag})" >&2
    exit 1
    ;;
esac
if ! [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "No X.Y.Z version in tag ${CI_TAG:-(none)}" >&2
  exit 1
fi

git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"
flutter precache --ios

HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# flutter build runs pod install with its output buffered, so a slow or stuck
# install is silent, and Xcode Cloud kills the script after 15 minutes without
# output (it happened once). Install the pods here first, with the output in
# the log and a 10-minute limit, retrying once; flutter build below then finds
# them in place. The Podfile needs the Generated.xcconfig that pub get writes.
flutter pub get
for attempt in 1 2; do
  if (cd ios && COCOAPODS_DISABLE_STATS=true LANG=en_US.UTF-8 perl -e 'alarm shift; exec @ARGV' 600 pod install); then
    break
  fi
  [ "$attempt" = 2 ] && exit 1
  echo "pod install failed or stalled, retrying" >&2
done

source ./dart_defines.sh

# App Store Connect gets Xcode Cloud's own build counter as the build number;
# pass it here too so the archive and the upload agree. --config-only also
# runs pod install.
flutter build ios --config-only --release --build-name="$version_name" --build-number="$CI_BUILD_NUMBER" "${DART_DEFINES[@]}"
