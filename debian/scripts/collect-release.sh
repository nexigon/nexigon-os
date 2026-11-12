#!/usr/bin/env bash
set -euo pipefail
cd -- "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SYSTEM:?Set SYSTEM to the image system to collect}"
if [[ ! "$SYSTEM" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "SYSTEM must be a system name without path separators." >&2
    exit 1
fi

required_artifacts=(
    system.img.xz
    system.rugixb
    system.rugixb-hash
    sbom.cdx.json
    sbom.spdx.json
    system-build-info.json
)
for artifact in "${required_artifacts[@]}"; do
    if [[ ! -f "build/$SYSTEM/$artifact" ]]; then
        echo "[ERROR] required artifact source is missing: build/$SYSTEM/$artifact" >&2
        exit 1
    fi
done

mkdir -p "../dist/${SYSTEM}"

collect_artifact() {
    local src="$1"
    local dest="$2"

    rm -f -- "${dest}"
    if ! ln -- "$src" "$dest" 2>/dev/null; then
        cp -- "$src" "$dest"
    fi
}

collect_artifact "build/${SYSTEM}/system.img.xz" "../dist/${SYSTEM}/${SYSTEM}.img.xz"
collect_artifact "build/${SYSTEM}/system.rugixb" "../dist/${SYSTEM}/${SYSTEM}.rugixb"
collect_artifact "build/${SYSTEM}/system.rugixb-hash" "../dist/${SYSTEM}/${SYSTEM}.rugixb-hash"

collect_artifact "build/${SYSTEM}/sbom.cdx.json" "../dist/${SYSTEM}/${SYSTEM}.cdx.json"
collect_artifact "build/${SYSTEM}/sbom.spdx.json" "../dist/${SYSTEM}/${SYSTEM}.spdx.json"
collect_artifact "build/${SYSTEM}/system-build-info.json" "../dist/${SYSTEM}/${SYSTEM}.build-info.json"
