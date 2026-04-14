#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
LIBSSH_SRC="$VENDOR_DIR/libssh-0.12.0"
MBEDTLS_SRC="$VENDOR_DIR/mbedtls-3.6.5"
OUTPUT_DIR="$VENDOR_DIR/Build"
TMP_ROOT="${TMPDIR:-/tmp}/orbital-libssh-build"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-16.0}"
CLANG="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"

common_cmake_flags=(
  -G "Unix Makefiles"
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_C_COMPILER="$CLANG"
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
)

libssh_feature_flags=(
  -DWITH_MBEDTLS=ON
  -DBUILD_SHARED_LIBS=OFF
  -DBUILD_STATIC_LIB=ON
  -DWITH_GSSAPI=OFF
  -DWITH_ZLIB=OFF
  -DWITH_SERVER=OFF
  -DWITH_PCAP=OFF
  -DWITH_EXAMPLES=OFF
  -DWITH_NACL=OFF
  -DWITH_FIDO2=OFF
  -DWITH_PKCS11_URI=OFF
  -DWITH_PKCS11_PROVIDER=OFF
  -DUNIT_TESTING=OFF
  -DCLIENT_TESTING=OFF
  -DSERVER_TESTING=OFF
  -DGSSAPI_TESTING=OFF
  -DPICKY_DEVELOPER=OFF
  -DWITH_SYMBOL_VERSIONING=OFF
  -DCMAKE_C_STANDARD=11
)

build_mbedtls() {
  local platform="$1"
  local sysroot="$2"
  local archs="$3"
  local build_dir="$TMP_ROOT/mbedtls-$platform"
  local stage_dir="$TMP_ROOT/stage/mbedtls-$platform"

  cmake --fresh \
    -S "$MBEDTLS_SRC" \
    -B "$build_dir" \
    "${common_cmake_flags[@]}" \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DENABLE_PROGRAMS=OFF \
    -DENABLE_TESTING=OFF \
    -DMBEDTLS_FATAL_WARNINGS=OFF \
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
    -DCMAKE_INSTALL_PREFIX="$stage_dir"

  cmake --build "$build_dir" --parallel 8
  cmake --install "$build_dir"
}

build_libssh() {
  local platform="$1"
  local sysroot="$2"
  local archs="$3"
  local mbedtls_stage="$TMP_ROOT/stage/mbedtls-$platform"
  local build_dir="$TMP_ROOT/libssh-$platform"
  local stage_dir="$TMP_ROOT/stage/libssh-$platform"

  cmake --fresh \
    -S "$LIBSSH_SRC" \
    -B "$build_dir" \
    "${common_cmake_flags[@]}" \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" \
    -DMBEDTLS_INCLUDE_DIR="$mbedtls_stage/include" \
    -DMBEDTLS_SSL_LIBRARY="$mbedtls_stage/lib/libmbedtls.a" \
    -DMBEDTLS_CRYPTO_LIBRARY="$mbedtls_stage/lib/libmbedcrypto.a" \
    -DMBEDTLS_X509_LIBRARY="$mbedtls_stage/lib/libmbedx509.a" \
    -DCMAKE_INSTALL_PREFIX="$stage_dir" \
    "${libssh_feature_flags[@]}"

  cmake --build "$build_dir" --parallel 8
  cmake --install "$build_dir"
}

combine_archives() {
  local platform="$1"
  local mbedtls_stage="$TMP_ROOT/stage/mbedtls-$platform"
  local libssh_stage="$TMP_ROOT/stage/libssh-$platform"
  local out_dir="$TMP_ROOT/combined/$platform"

  mkdir -p "$out_dir"

  libtool -static \
    -o "$out_dir/LibsshVendor.a" \
    "$libssh_stage/lib/libssh.a" \
    "$mbedtls_stage/lib/libmbedcrypto.a" \
    "$mbedtls_stage/lib/libmbedx509.a" \
    "$mbedtls_stage/lib/libmbedtls.a" \
    "$mbedtls_stage/lib/libeverest.a" \
    "$mbedtls_stage/lib/libp256m.a"
}

create_framework() {
  local platform="$1"
  local libssh_stage="$TMP_ROOT/stage/libssh-$platform"
  local combined_dir="$TMP_ROOT/combined/$platform"
  local framework_dir="$combined_dir/LibsshVendor.framework"
  local headers_dir="$framework_dir/Headers"
  local modules_dir="$framework_dir/Modules"

  mkdir -p "$headers_dir/libssh" "$modules_dir"
  cp "$combined_dir/LibsshVendor.a" "$framework_dir/LibsshVendor"
  cp -R "$libssh_stage/include/libssh/." "$headers_dir/libssh/"
  perl -0pi -e 's/#include <libssh\/libssh_version\.h>/#include "libssh_version.h"/g; s/#include "libssh\/legacy.h"/#include "legacy.h"/g' "$headers_dir/libssh/libssh.h"

  cat > "$headers_dir/LibsshVendor.h" <<'EOF'
#include "libssh/libssh.h"
EOF

  cat > "$modules_dir/module.modulemap" <<'EOF'
framework module LibsshVendor {
  umbrella header "LibsshVendor.h"

  export *
  module * { export * }
}
EOF

  cat > "$framework_dir/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LibsshVendor</string>
  <key>CFBundleIdentifier</key>
  <string>dev.orbital.LibsshVendor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LibsshVendor</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
EOF
}

create_xcframework() {
  local device_framework="$TMP_ROOT/combined/iphoneos/LibsshVendor.framework"
  local sim_framework="$TMP_ROOT/combined/iphonesimulator/LibsshVendor.framework"

  mkdir -p "$OUTPUT_DIR"
  xcodebuild -create-xcframework \
    -framework "$device_framework" \
    -framework "$sim_framework" \
    -output "$OUTPUT_DIR/LibsshVendor.xcframework"
}

main() {
  build_mbedtls "iphonesimulator" "iphonesimulator" "arm64;x86_64"
  build_libssh "iphonesimulator" "iphonesimulator" "arm64;x86_64"
  combine_archives "iphonesimulator"
  create_framework "iphonesimulator"

  build_mbedtls "iphoneos" "iphoneos" "arm64"
  build_libssh "iphoneos" "iphoneos" "arm64"
  combine_archives "iphoneos"
  create_framework "iphoneos"

  create_xcframework

  echo "Created $OUTPUT_DIR/LibsshVendor.xcframework"
}

main "$@"
