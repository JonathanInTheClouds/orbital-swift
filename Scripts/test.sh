#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

export HOME="$ROOT_DIR"
export TMPDIR="${TMPDIR:-/tmp/}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/OrbitalModuleCache}"
export SWIFTPM_PACKAGECACHE_PATH="${SWIFTPM_PACKAGECACHE_PATH:-/tmp/OrbitalSwiftPMCache}"
export CFFIXED_USER_HOME="$HOME"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT_DIR/.cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/OrbitalSwiftModuleCache}"

PROJECT="Orbital.xcodeproj"
SCHEME="Orbital"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OrbitalDerivedData}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

cd "$ROOT_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" \
  -only-testing:OrbitalTests \
  test
