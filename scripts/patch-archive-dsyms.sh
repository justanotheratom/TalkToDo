#!/bin/sh

set -eu

ARCHIVE_PATH="${1:-${ARCHIVE_PATH:-}}"

if [ -z "${ARCHIVE_PATH}" ]; then
  echo "error: archive path is required" >&2
  exit 1
fi

case "${ARCHIVE_PATH}" in
  *.xcarchive)
    ;;
  *)
    ARCHIVE_PATH="${ARCHIVE_PATH}.xcarchive"
    ;;
esac

APPLICATIONS_DIR="${ARCHIVE_PATH}/Products/Applications"
DSYM_OUTPUT_DIR="${ARCHIVE_PATH}/dSYMs"

if [ ! -d "${APPLICATIONS_DIR}" ]; then
  echo "error: archive applications directory not found at ${APPLICATIONS_DIR}" >&2
  exit 1
fi

APP_PATH="$(find "${APPLICATIONS_DIR}" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "${APP_PATH}" ]; then
  echo "error: no app bundle found under ${APPLICATIONS_DIR}" >&2
  exit 1
fi

FRAMEWORKS_DIR="${APP_PATH}/Frameworks"
if [ ! -d "${FRAMEWORKS_DIR}" ]; then
  echo "error: frameworks directory not found at ${FRAMEWORKS_DIR}" >&2
  exit 1
fi

FRAMEWORK_NAMES="
LeapSDK
LeapModelDownloader
inference_engine
inference_engine_executorch_backend
inference_engine_llamacpp_backend
"

mkdir -p "${DSYM_OUTPUT_DIR}"

for FRAMEWORK_NAME in ${FRAMEWORK_NAMES}; do
  BINARY_PATH="${FRAMEWORKS_DIR}/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"
  DSYM_PATH="${DSYM_OUTPUT_DIR}/${FRAMEWORK_NAME}.framework.dSYM"

  if [ ! -f "${BINARY_PATH}" ]; then
    echo "warning: missing framework binary at ${BINARY_PATH}"
    continue
  fi

  rm -rf "${DSYM_PATH}"
  echo "Generating archive dSYM for ${FRAMEWORK_NAME}"
  xcrun dsymutil "${BINARY_PATH}" -o "${DSYM_PATH}"
done
