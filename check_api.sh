#!/bin/bash
set -euo pipefail

# Checks that an API server has every route this app calls: every path in
# lib/core/network/api_endpoints.dart. The App store build workflow runs it
# against production before a release, because a store app talks to the
# production API and must not ship ahead of it.
#
#   ./check_api.sh [API URL]    (default: production, https://app-api.edu-ai.eu)
#
# Laravel answers "The route … could not be found." only when no route matches
# the path. Any other answer (401, 405, 422, a 404 for a missing record…) means
# the route is there. Path parameters are probed as "1".

api=${1:-https://app-api.edu-ai.eu}
cd "$(dirname "$0")"

paths=$(grep -oE "'/api/[^']*'" lib/core/network/api_endpoints.dart \
  | tr -d "'" \
  | sed -E 's/\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*/1/g' \
  | sort -u)

route_missing() {
  [[ "$(curl -sS --retry 3 -H 'Accept: application/json' "$api$1")" == *"could not be found"* ]]
}

missing=()
for path in $paths; do
  # Some constants are prefixes the app extends: consentManage + "/$token".
  if route_missing "$path" && route_missing "$path/1"; then
    missing+=("$path")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "$api lacks ${#missing[@]} route(s) this app calls:"
  printf '  %s\n' "${missing[@]}"
  exit 1
fi
echo "$api has all $(wc -l <<< "$paths" | tr -d ' ') routes this app calls."
