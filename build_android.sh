#!/bin/bash
set -euo pipefail

# Release App Bundle for Google Play.
# dart-define values are compile-time — they MUST be passed here or the OAuth
# client IDs bake in empty (Microsoft login then fails with AADSTS900144).
# Export the vars in your shell (or a .env you source) before running; the
# full list lives in dart_defines.sh. Extra arguments go to flutter, e.g.
# --build-number=142.
# Store builds normally come from GitHub Actions — see docs/store-builds.md.

: "${MICROSOFT_CLIENT_ID:?export MICROSOFT_CLIENT_ID before building}"
# Google needs the *web* client id as serverClientId on Android; empty means
# authenticate() cannot mint an id_token and sign-in silently dies.
: "${GOOGLE_WEB_CLIENT_ID:?export GOOGLE_WEB_CLIENT_ID before building}"

source "$(dirname "$0")/dart_defines.sh"

flutter build appbundle --release "${DART_DEFINES[@]}" "$@"

echo "AAB built at build/app/outputs/bundle/release/app-release.aab."
