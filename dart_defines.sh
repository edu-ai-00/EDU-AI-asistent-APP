# Compile-time dart-defines for release builds, read from the environment.
# Sourced by build_ios.sh, build_android.sh and ios/ci_scripts/ci_post_clone.sh
# (Xcode Cloud) — add a new define here and every store build picks it up.
#
# The API follows the store channel (APP_CHANNEL), so a build never talks to
# another environment's API:
#   internal  TestFlight internal, Play internal testing  dev API
#   beta      TestFlight public, Play open testing        staging API
#   release   App Store, Play production                  production API
# Store builds always set APP_CHANNEL: Xcode Cloud from its tag, the GitHub job
# from the channel it runs. Without one (a local build), API_URL decides and
# the app falls back to production when that is unset too.
#
# Push notifications: the FIREBASE_* vars are optional. Unset, the build has
# no push (the Novinky feed still carries every notification); set, they are
# the whole Firebase config — no google-services.json / GoogleService-Info.plist.
#
# Sentry needs none of these: its DSN is built in. SENTRY_PROGUARD_UUID is set
# only by the Android store job, which uploads the R8 mapping under it.

case "${APP_CHANNEL:-}" in
  internal) API_URL=https://api-dev-8b6a.up.railway.app ;;
  beta) API_URL=https://app-api-stage.edu-ai.eu ;;
  release) API_URL=https://app-api.edu-ai.eu ;;
  '')
    # A store job that lost its channel would quietly build against production.
    if [ -n "${GITHUB_ACTIONS:-}${CI_XCODE_CLOUD:-}" ]; then
      echo "APP_CHANNEL is not set (internal, beta or release)" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unknown APP_CHANNEL '$APP_CHANNEL' (internal, beta or release)" >&2
    exit 1
    ;;
esac

DART_DEFINES=(
  "--dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}"
  "--dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID:-}"
  "--dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY:-}"
  "--dart-define=FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-}"
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID:-}"
  "--dart-define=FIREBASE_ANDROID_APP_ID=${FIREBASE_ANDROID_APP_ID:-}"
  "--dart-define=FIREBASE_IOS_APP_ID=${FIREBASE_IOS_APP_ID:-}"
  "--dart-define=FIREBASE_IOS_BUNDLE_ID=${FIREBASE_IOS_BUNDLE_ID:-}"
  "--dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID:-common}"
  "--dart-define=SENTRY_PROGUARD_UUID=${SENTRY_PROGUARD_UUID:-}"
)
# An empty API_URL define would beat the production default in
# api_endpoints.dart, so pass it only with a value.
if [ -n "${API_URL:-}" ]; then
  DART_DEFINES+=("--dart-define=API_URL=$API_URL")
fi
echo "API: ${API_URL:-https://app-api.edu-ai.eu (default)}"
