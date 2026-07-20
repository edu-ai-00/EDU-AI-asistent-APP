#!/bin/bash
source "$(dirname "$0")/.env" 2>/dev/null

echo "Select platform:"
echo "1) iOS Simulator"
echo "2) Android Emulator"
echo "3) Both"
read -p "Enter choice [1-3]: " choice

case $choice in
  1)
    echo "Opening iOS Simulator..."
    open -a Simulator
    sleep 3
    flutter run -d "iPhone 17 Pro" \
      --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
      --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
      --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
    ;;
  2)
    echo "Launching Android Emulator..."
    flutter emulators --launch Medium_Phone_API_36.1
    sleep 8
    flutter run -d emulator \
      --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
      --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
      --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
    ;;
  3)
    echo "Opening iOS Simulator..."
    open -a Simulator
    echo "Launching Android Emulator..."
    flutter emulators --launch Medium_Phone_API_36.1
    sleep 8
    echo "Running on both simulators..."
    flutter run -d "iPhone 17 Pro" -d emulator \
      --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-} \
      --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-} \
      --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac
