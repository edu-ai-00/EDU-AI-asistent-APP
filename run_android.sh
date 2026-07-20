#!/bin/bash
source "$(dirname "$0")/.env" 2>/dev/null

echo "Launching Android Emulator..."
flutter emulators --launch Medium_Phone_API_36.1
sleep 8
flutter run -d emulator \
  --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
  --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
  --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
