#!/bin/sh

set -eu

if [ "${CONFIGURATION:-}" != "Debug" ]; then
  exit 0
fi

REPO_DOTENV="${SRCROOT}/../.env"
DESTINATION_DOTENV="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/talktodo.env"

if [ ! -f "${REPO_DOTENV}" ]; then
  rm -f "${DESTINATION_DOTENV}"
  exit 0
fi

mkdir -p "$(dirname "${DESTINATION_DOTENV}")"
cp "${REPO_DOTENV}" "${DESTINATION_DOTENV}"
