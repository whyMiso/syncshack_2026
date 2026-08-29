#!/bin/zsh
# Builds SayHi and assembles a runnable .app bundle.
# Usage: ./build.sh [--debug] [--run]
set -euo pipefail

CONFIG=release
RUN=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug ;;
    --run)   RUN=1 ;;
  esac
done

cd "$(dirname "$0")"

swift build -c "$CONFIG"

BIN=".build/$CONFIG/SayHi"
APP="build/SayHi.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SayHi"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signing identity decides whether macOS permissions survive a rebuild.
#
# An ad-hoc signature has no stable identity, so TCC keys the grant to the
# binary's cdhash — which changes on every build. Camera, Screen Recording and
# Accessibility grants are then silently invalidated each time, and macOS
# prompts again. Signing with a real certificate gives the app a stable
# identity (team + bundle id), so grants persist across rebuilds.
#
# Override with SAYHI_SIGN_IDENTITY; falls back to ad-hoc if nothing is found.
SIGN_ID="${SAYHI_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Developer ID Application|"Apple Development/ { print $2; exit }')
fi

if [[ -n "$SIGN_ID" ]]; then
  codesign --force --sign "$SIGN_ID" "$APP"
  echo "Signed with stable identity ${SIGN_ID:0:12}… (permissions persist across rebuilds)"
else
  codesign --force --sign - "$APP"
  echo "WARNING: no signing identity found; signed ad-hoc." >&2
  echo "         macOS will re-ask for Camera/Screen Recording after every rebuild." >&2
fi

echo "Built $APP"
if [[ "$RUN" == 1 ]]; then
  open "$APP"
fi
