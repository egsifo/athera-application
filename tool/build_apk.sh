#!/usr/bin/env bash
# Builds an installable Android APK. Needs Flutter (https://docs.flutter.dev/get-started/install)
# and the Android SDK (installed with Android Studio). Run from the project root:  bash tool/build_apk.sh
set -euo pipefail

[ -d android ] || flutter create . --platforms=android --project-name athera --org com.athera

M=android/app/src/main/AndroidManifest.xml
# The app talks to your model server over plain http on a local network, so it needs
# internet permission and cleartext traffic. Use https for anything beyond local testing.
grep -q 'android.permission.INTERNET' "$M" || sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
grep -q 'usesCleartextTraffic' "$M" || sed -i '0,/<application/s//<application android:usesCleartextTraffic="true"/' "$M"

flutter pub get
flutter build apk --release
echo
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
