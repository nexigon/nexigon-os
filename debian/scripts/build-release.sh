#!/usr/bin/env bash
set -euo pipefail

cd -- "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SYSTEM:?Set SYSTEM to the image system to build}"
: "${VERSION:?Set VERSION to the release version}"
if [[ ! "$SYSTEM" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "SYSTEM must be a system name without path separators." >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "VERSION may contain only letters, numbers, dots, underscores, and hyphens." >&2
    exit 1
fi

echo "[INFO] building image and update bundle for '$SYSTEM' (version: $VERSION)"
./run-bakery bake bundle "$SYSTEM" \
    --release-version "$VERSION" \
    --param-file params/staging.toml

image_path="build/$SYSTEM/system.img"
if [[ ! -f "$image_path" ]]; then
    echo "[ERROR] expected image not found at '$image_path'" >&2
    exit 1
fi

echo "[INFO] compressing '$SYSTEM' image"
xz -T0 -f "$image_path"
sudo chown -R "$(id -u):$(id -g)" "build/$SYSTEM"
