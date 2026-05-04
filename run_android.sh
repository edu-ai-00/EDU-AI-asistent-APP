#!/bin/bash

echo "Launching Android Emulator..."
flutter emulators --launch Medium_Phone_API_36.1
sleep 8
flutter run -d emulator
