#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="$ROOT_DIR/source/BuildInfo.mc"
STATE_FILE="$ROOT_DIR/.build_version_state"
BUMP_MODE="${1:-}"

current_version=0

if [[ -f "$OUTPUT_FILE" ]]; then
    extracted_version="$(sed -n 's/.*VERSION = "\([0-9][0-9]*\)".*/\1/p' "$OUTPUT_FILE" | head -n 1)"
    if [[ -n "${extracted_version:-}" ]]; then
        current_version="$extracted_version"
    fi
fi

hash_file() {
    local path="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
        return
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
        return
    fi

    openssl dgst -sha256 "$path" | sed -n 's/.*= //p'
}

collect_version_inputs() {
    local paths=(
        "$ROOT_DIR/manifest.xml"
        "$ROOT_DIR/monkey.jungle"
        "$ROOT_DIR/source"
        "$ROOT_DIR/resources"
        "$ROOT_DIR/scripts"
    )

    local files=()
    local path
    for path in "${paths[@]}"; do
        [[ -e "$path" ]] || continue
        if [[ -f "$path" ]]; then
            files+=("$path")
            continue
        fi

        while IFS= read -r file; do
            files+=("$file")
        done < <(find "$path" -type f | sort)
    done

    printf '%s\n' "${files[@]}"
}

compute_fingerprint() {
    local data=""
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        # BuildInfo is generated output; it must not affect increment decision.
        if [[ "$file" == "$OUTPUT_FILE" ]]; then
            continue
        fi

        local rel="${file#$ROOT_DIR/}"
        local digest
        digest="$(hash_file "$file")"
        data+="${rel}:${digest}"$'\n'
    done < <(collect_version_inputs)

    local tmp_file
    tmp_file="$(mktemp)"
    printf '%s' "$data" > "$tmp_file"
    local result
    result="$(hash_file "$tmp_file")"
    rm -f "$tmp_file"
    echo "$result"
}

write_build_info() {
    local version="$1"
    cat > "$OUTPUT_FILE" <<EOF
module BuildInfo {
    const VERSION = "$version";
}
EOF
}

previous_fingerprint=""
if [[ -f "$STATE_FILE" ]]; then
    previous_fingerprint="$(sed -n 's/^FINGERPRINT=//p' "$STATE_FILE" | head -n 1)"
fi

current_fingerprint="$(compute_fingerprint)"

if [[ "$BUMP_MODE" != "--bump" ]]; then
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        write_build_info "$current_version"
    fi
    echo "$current_version"
    exit 0
fi

if [[ "$current_version" -gt 0 && "$previous_fingerprint" == "$current_fingerprint" ]]; then
    build_version="$current_version"
else
    build_version=$((current_version + 1))
fi

if [[ ! -f "$OUTPUT_FILE" ]] || [[ "$build_version" != "$current_version" ]]; then
    write_build_info "$build_version"
fi

cat > "$STATE_FILE" <<EOF
FINGERPRINT=$current_fingerprint
VERSION=$build_version
EOF

echo "$build_version"
