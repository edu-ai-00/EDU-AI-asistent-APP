#!/bin/bash
set -euo pipefail

# Xcode Cloud hook: runs after xcodebuild. Writes the TestFlight "What to Test"
# notes from the latest eduai-app commits; the TestFlight post-actions read them
# from ios/TestFlight/WhatToTest.<locale>.txt. Then uploads the archive's dSYMs
# to Sentry (see the end of this file). Setup: docs/store-builds.md.

# Only an archive goes to TestFlight. Apple's sample checks
# CI_APP_STORE_SIGNED_APP_PATH instead, but with it build 38 wrote no notes.
if [ "${CI_XCODEBUILD_ACTION:-}" != archive ]; then
  echo "No What to Test notes for a ${CI_XCODEBUILD_ACTION:-unknown} action"
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"
# Xcode Cloud clones shallow.
git fetch --quiet --deepen 50 || true

notes=eduai-app/ios/TestFlight/WhatToTest.cs.txt
mkdir -p "$(dirname "$notes")"
# Testers care about app changes, not CI or chores.
# "fix(app): Foo (BR-123)" → "- Foo (BR-123)"
git log -15 --no-merges -E --invert-grep --grep='^(chore|ci|docs|test)' --pretty='- %s' -- eduai-app \
  | sed -E 's/^- [a-z]+(\([^)]*\))?!?: /- /' \
  > "$notes"

echo "What to Test notes ($notes):"
cat "$notes"

# Sentry: the archive's dSYMs make native iOS crashes readable, the Flutter
# frames in them included (App.framework.dSYM). Sentry matches a dSYM to a
# crash by its UUID, so no release name is involved. Runs only when the
# workflow's environment has SENTRY_AUTH_TOKEN (an organization auth token,
# marked secret), and never fails the build: the archive is made by now.
# sentry-cli is the version sentry_dart_plugin 3.4.0 pins, checked against
# the checksum that plugin ships.
SENTRY_CLI_VERSION=2.58.6
SENTRY_CLI_SHA256=728d5a8c48d3e94d0a3e644431dcaad19c28b126a00eb37930e67bd146905d96

upload_dsyms() {
  local dsyms="${CI_ARCHIVE_PATH:-}/dSYMs" cli
  if [ ! -d "$dsyms" ]; then
    echo "No dSYMs at $dsyms"
    return 1
  fi
  cli="$(mktemp -d)/sentry-cli"
  curl -fsSL -o "$cli" \
    "https://downloads.sentry-cdn.com/sentry-cli/$SENTRY_CLI_VERSION/sentry-cli-Darwin-universal" || return 1
  echo "$SENTRY_CLI_SHA256  $cli" | shasum -a 256 -c - || return 1
  chmod +x "$cli" || return 1
  "$cli" debug-files upload --org no-big-deals --project eduai-app "$dsyms"
}

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "No SENTRY_AUTH_TOKEN, skipping the Sentry dSYM upload"
elif ! upload_dsyms; then
  echo "Sentry dSYM upload failed; the build goes on without it" >&2
fi
