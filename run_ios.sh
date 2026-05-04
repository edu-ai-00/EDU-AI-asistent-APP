#!/bin/bash

echo "Starting iOS Simulator..."
open -a Simulator
sleep 3
flutter run -d "iPhone 17 Pro"
