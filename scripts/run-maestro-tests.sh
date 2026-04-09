#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/TalkToDo/TalkToDo.xcodeproj"
SCHEME="TalkToDo"
DEVICE_ID="${SIMULATOR_ID:-8FA6A311-D245-4201-ABEA-50DF9C78140D}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/TalkToDoMaestroDerivedData}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-llc.fungee.talktodo}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/TalkToDo.app"
SLOW_MOTION_MS="${SLOW_MOTION_MS:-0}"
SHOW_SIMULATOR=0

FLOWS=(
  "$ROOT_DIR/.maestro/01_launch_smoke.yaml"
  "$ROOT_DIR/.maestro/02_create_and_history.yaml"
  "$ROOT_DIR/.maestro/03_completion_undo_and_reset.yaml"
)

usage() {
  cat <<'EOF'
Usage: scripts/run-maestro-tests.sh [--slow] [--slow-ms <milliseconds>] [--watch]

  --slow                  Run with a watchable default pause between UI actions.
  --slow-ms <ms>          Override the pause duration for slow mode.
  --watch                 Open Simulator before running the suite.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slow)
      if [[ "$SLOW_MOTION_MS" == "0" ]]; then
        SLOW_MOTION_MS=750
      fi
      SHOW_SIMULATOR=1
      ;;
    --slow-ms)
      shift
      if [[ $# -eq 0 || "$1" != <-> ]]; then
        echo "Expected an integer millisecond value after --slow-ms" >&2
        exit 1
      fi
      SLOW_MOTION_MS="$1"
      SHOW_SIMULATOR=1
      ;;
    --watch)
      SHOW_SIMULATOR=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$SHOW_SIMULATOR" == "1" ]]; then
  open -a Simulator
fi

xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH"

launch_fresh_app() {
  xcrun simctl terminate "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEVICE_ID" "$APP_PATH"

  SIMCTL_CHILD_TALKTODO_UI_TEST_MODE=1 \
  SIMCTL_CHILD_TALKTODO_DISABLE_CLOUDKIT=1 \
  xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$APP_BUNDLE_ID" >/dev/null

  sleep 2
}

for flow in "${FLOWS[@]}"; do
  launch_fresh_app
  maestro test -e SLOW_MOTION_MS="$SLOW_MOTION_MS" "$flow"
done
