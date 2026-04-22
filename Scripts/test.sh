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
DESTINATION="${DESTINATION:-}"
PREFERRED_DEVICE_NAMES="${DESTINATION_DEVICE_NAMES:-iPhone 17|iPhone 16 Pro|iPhone 16|iPhone 15 Pro|iPhone 15|iPhone 14}"

cd "$ROOT_DIR"

find_ios_device_id() {
  xcrun simctl list devices available | awk -v names="$PREFERRED_DEVICE_NAMES" '
    BEGIN {
      n = split(names, prefs, "|")
    }
    /^-- iOS / {
      ios = 1
      next
    }
    /^-- / {
      ios = 0
      next
    }
    ios {
      if (match($0, /\([0-9A-Fa-f-][0-9A-Fa-f-]*\)/)) {
        uuid = substr($0, RSTART + 1, RLENGTH - 2)
        if (index($0, "    iPhone ") == 1) {
          fallback = uuid
        }
        for (i = 1; i <= n; i++) {
          if (prefs[i] != "" && index($0, "    " prefs[i] " (") == 1) {
            best[i] = uuid
          }
        }
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        if (best[i] != "") {
          print best[i]
          exit
        }
      }
      if (fallback != "") {
        print fallback
      }
    }
  '
}

latest_ios_runtime_id() {
  xcrun simctl list runtimes available | awk '/^iOS / { runtime = $NF } END { print runtime }'
}

preferred_device_type_id() {
  xcrun simctl list devicetypes | awk -v names="$PREFERRED_DEVICE_NAMES" '
    BEGIN {
      n = split(names, prefs, "|")
    }
    {
      for (i = 1; i <= n; i++) {
        if (prefs[i] != "" && index($0, prefs[i] " (") == 1) {
          if (match($0, /\([^()]*\)$/)) {
            print substr($0, RSTART + 1, RLENGTH - 2)
            exit
          }
        }
      }
    }
  '
}

resolve_destination() {
  if [ -n "$DESTINATION" ]; then
    printf '%s\n' "$DESTINATION"
    return
  fi

  device_id=$(find_ios_device_id)
  if [ -z "$device_id" ]; then
    runtime_id=$(latest_ios_runtime_id)
    device_type_id=$(preferred_device_type_id)

    if [ -z "$runtime_id" ] || [ -z "$device_type_id" ]; then
      printf 'Unable to find an available iOS simulator runtime and device type.\n' >&2
      exit 70
    fi

    device_id=$(xcrun simctl create "Orbital CI iPhone" "$device_type_id" "$runtime_id")
  fi

  printf 'platform=iOS Simulator,id=%s\n' "$device_id"
}

DESTINATION=$(resolve_destination)

if [ "${1:-}" = "--resolve-destination" ]; then
  printf '%s\n' "$DESTINATION"
  exit 0
fi

echo "Destination: $DESTINATION"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION" \
  -only-testing:OrbitalTests \
  test
