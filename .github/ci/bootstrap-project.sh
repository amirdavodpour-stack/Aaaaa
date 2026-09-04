#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
WORK_DIR="${ROOT_DIR}/.ci-work"
SOURCE_DIR="${WORK_DIR}/source"

rm -rf "${WORK_DIR}"
mkdir -p "${SOURCE_DIR}"

echo "=== HOPE Runtime Bootstrap ==="
echo "Repository root: ${ROOT_DIR}"

ZIP_FILE=""

# Prefer the expected controlled archive name.
if [[ -f "${ROOT_DIR}/HOPE-V7-S27-CONTROLLED.zip" ]]; then
  ZIP_FILE="${ROOT_DIR}/HOPE-V7-S27-CONTROLLED.zip"
else
  # Fallback: find the first repository zip.
  mapfile -t ZIPS < <(find "${ROOT_DIR}" -maxdepth 2 -type f -name '*.zip' \
    ! -path "${WORK_DIR}/*" | sort)

  if [[ "${#ZIPS[@]}" -eq 1 ]]; then
    ZIP_FILE="${ZIPS[0]}"
  fi
fi

if [[ -z "${ZIP_FILE}" ]]; then
  echo "::error::No project ZIP archive was found."
  echo "Expected: ${ROOT_DIR}/HOPE-V7-S27-CONTROLLED.zip"
  exit 1
fi

echo "ZIP: ${ZIP_FILE}"
sha256sum "${ZIP_FILE}" | tee "${RUNNER_TEMP}/hope-input-sha256.txt"

echo
echo "=== ZIP listing (first 200 entries) ==="
unzip -l "${ZIP_FILE}" | head -n 202

echo
echo "=== Extract ==="
unzip -q "${ZIP_FILE}" -d "${SOURCE_DIR}"

echo
echo "=== Detect project root ==="

PROJECT_DIR=""

# Direct extraction
if [[ -f "${SOURCE_DIR}/pubspec.yaml" && -f "${SOURCE_DIR}/backend/package.json" ]]; then
  PROJECT_DIR="${SOURCE_DIR}"
else
  # Search for the actual project root.
  while IFS= read -r pubspec; do
    candidate="$(dirname "${pubspec}")"
    if [[ -f "${candidate}/backend/package.json" ]]; then
      PROJECT_DIR="${candidate}"
      break
    fi
  done < <(find "${SOURCE_DIR}" -type f -name pubspec.yaml | sort)
fi

if [[ -z "${PROJECT_DIR}" ]]; then
  echo "::error::Could not find a project root containing both:"
  echo "  pubspec.yaml"
  echo "  backend/package.json"
  echo
  echo "Detected files:"
  find "${SOURCE_DIR}" -maxdepth 4 -type f \
    \( -name 'pubspec.yaml' -o -name 'package.json' \) | sort
  exit 1
fi

export PROJECT_DIR

echo "PROJECT_DIR=${PROJECT_DIR}" | tee "${RUNNER_TEMP}/hope-project-dir.txt"

{
  echo "project_dir=${PROJECT_DIR}"
  echo "flutter_root=$(dirname "${PROJECT_DIR}")"
  echo "zip=${ZIP_FILE}"
  echo "sha256=$(sha256sum "${ZIP_FILE}" | awk '{print $1}')"
} | tee "${RUNNER_TEMP}/hope-bootstrap.txt"

echo
echo "=== Project structure ==="
cd "${PROJECT_DIR}"

printf '%s\n' "--- Root ---"
find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort

printf '%s\n' "--- Flutter ---"
test -f pubspec.yaml
test -d lib
test -d android

printf '%s\n' "--- Backend ---"
test -f backend/package.json
test -f backend/package-lock.json || true

printf '%s\n' "--- Runtime scripts ---"
for f in \
  backend/src/migrate.js \
  backend/docker-compose.yml \
  backend/scripts/dr-restore-drill.sh
do
  if [[ -e "$f" ]]; then
    echo "FOUND: $f"
  else
    echo "MISSING: $f"
  fi
done

echo
echo "BOOTSTRAP PASS"
