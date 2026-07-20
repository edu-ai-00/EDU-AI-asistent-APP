#!/bin/bash
source "$(dirname "$0")/.env" 2>/dev/null

echo "Starting iOS Simulator..."
open -a Simulator
sleep 3
flutter run -d "iPhone 17 Pro" \
  --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
  --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
  --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
