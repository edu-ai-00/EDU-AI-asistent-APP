#!/bin/bash
# Chrome on fixed port 5000 so origin matches the Google Web client whitelist.
source "$(dirname "$0")/.env" 2>/dev/null
flutter run -d chrome --web-port=5000 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
  --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
  --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
