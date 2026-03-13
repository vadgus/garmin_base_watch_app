#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
SDK_HOME_DEFAULT="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa"
SDK_HOME="${CIQ_SDK_HOME:-$SDK_HOME_DEFAULT}"
MONKEYC_BIN="$SDK_HOME/bin/monkeyc"
PRODUCT="${CIQ_PRODUCT:-venu3}"
APP_FILE_NAME="garmin_base_watch_app.prg"
UPDATE_BUILD_VERSION_SCRIPT="$ROOT_DIR/scripts/update_build_version.sh"
SHOULD_BUMP_BUILD_VERSION="${CIQ_BUMP_BUILD_VERSION:-0}"
DEV_KEY_PATH="${CIQ_DEV_KEY_PATH:-${1:-}}"
SIGNING_KEY_DER_PATH=""

cleanup() {
    if [[ -n "$SIGNING_KEY_DER_PATH" && "$SIGNING_KEY_DER_PATH" == /tmp/* ]]; then
        rm -f "$SIGNING_KEY_DER_PATH" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

key_bits_from_pem() {
    local key_path="$1"
    openssl pkey -in "$key_path" -text -noout 2>/dev/null | sed -n 's/.*(\([0-9][0-9]*\) bit.*/\1/p' | head -n 1
}

key_bits_from_der() {
    local key_path="$1"
    openssl pkey -inform DER -in "$key_path" -text -noout 2>/dev/null | sed -n 's/.*(\([0-9][0-9]*\) bit.*/\1/p' | head -n 1
}

prepare_signing_key_der() {
    local key_path="$1"

    if [[ "$key_path" == *.pem ]]; then
        local bits
        bits="$(key_bits_from_pem "$key_path")"
        if [[ "$bits" != "4096" ]]; then
            echo "Developer key must be RSA 4096-bit. Current key size: ${bits:-unknown}"
            exit 1
        fi

        local der_path="/tmp/garmin_base_watch_app_key_$$.der"
        openssl pkcs8 -topk8 -inform PEM -outform DER -in "$key_path" -out "$der_path" -nocrypt >/dev/null 2>&1
        echo "$der_path"
        return 0
    fi

    local bits
    bits="$(key_bits_from_der "$key_path")"
    if [[ "$bits" != "4096" ]]; then
        echo "Developer key must be RSA 4096-bit DER or PEM. Current key size: ${bits:-unknown}"
        exit 1
    fi

    echo "$key_path"
}

if [[ -z "$DEV_KEY_PATH" ]]; then
    echo "Usage:"
    echo "  CIQ_DEV_KEY_PATH=/path/to/developer_key.pem ./build_releases.sh"
    echo "  or ./build_releases.sh /path/to/developer_key.pem"
    exit 1
fi

if [[ ! -x "$MONKEYC_BIN" ]]; then
    echo "monkeyc not found at: $MONKEYC_BIN"
    echo "Set CIQ_SDK_HOME to your SDK path."
    exit 1
fi

if [[ ! -f "$DEV_KEY_PATH" ]]; then
    echo "Developer key not found: $DEV_KEY_PATH"
    exit 1
fi

if [[ ! -x "$UPDATE_BUILD_VERSION_SCRIPT" ]]; then
    echo "Build version script not found or not executable: $UPDATE_BUILD_VERSION_SCRIPT"
    exit 1
fi

SIGNING_KEY_DER_PATH="$(prepare_signing_key_der "$DEV_KEY_PATH")"
if [[ "$SHOULD_BUMP_BUILD_VERSION" == "1" ]]; then
    BUILD_VERSION="$($UPDATE_BUILD_VERSION_SCRIPT --bump)"
else
    BUILD_VERSION="$($UPDATE_BUILD_VERSION_SCRIPT)"
fi

mkdir -p "$BUILD_DIR"
OUTPUT_PRG="$BUILD_DIR/$APP_FILE_NAME"

echo "Building PRG for $PRODUCT..."
echo "Build version: $BUILD_VERSION"
"$MONKEYC_BIN" \
    -f "$ROOT_DIR/monkey.jungle" \
    -d "$PRODUCT" \
    -o "$OUTPUT_PRG" \
    -y "$SIGNING_KEY_DER_PATH" \
    -w

echo "Built: $OUTPUT_PRG"
