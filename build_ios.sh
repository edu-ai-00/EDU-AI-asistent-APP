#!/bin/bash
set -euo pipefail

# Release IPA for TestFlight / App Store.
# dart-define values are compile-time — they MUST be passed here or the OAuth
# client IDs bake in empty (Microsoft login then fails with AADSTS900144).
# Export the vars in your shell (or a .env you source) before running; the
# full list lives in dart_defines.sh. Extra arguments go to flutter, e.g.
# --build-number=42.
# Store builds normally come from Xcode Cloud — see docs/store-builds.md.

: "${MICROSOFT_CLIENT_ID:?export MICROSOFT_CLIENT_ID before building}"

source "$(dirname "$0")/dart_defines.sh"

flutter build ipa --release "${DART_DEFINES[@]}" "$@"

echo "IPA built at build/ios/ipa/. Upload via Transporter or: xcrun altool / Xcode Organizer."
