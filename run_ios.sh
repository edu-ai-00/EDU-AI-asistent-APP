#!/bin/bash
source "$(dirname "$0")/.env" 2>/dev/null

echo "Starting iOS Simulator..."
open -a Simulator
sleep 3
flutter run -d "iPhone 17 Pro" \
  --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
  --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
  --dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY:-} \
  --dart-define=FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-} \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID:-} \
  --dart-define=FIREBASE_ANDROID_APP_ID=${FIREBASE_ANDROID_APP_ID:-} \
  --dart-define=FIREBASE_IOS_APP_ID=${FIREBASE_IOS_APP_ID:-} \
  --dart-define=FIREBASE_IOS_BUNDLE_ID=${FIREBASE_IOS_BUNDLE_ID:-} \
  --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
