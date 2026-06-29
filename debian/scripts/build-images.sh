#!/usr/bin/env bash

set -euo pipefail

DEFAULT_SYSTEMS=(
    nexigon-os-efi-amd64
    nexigon-os-efi-arm64
    nexigon-os-rpi5
    nexigon-os-rpi4
)

if [ "$#" -eq 0 ]; then
    systems=("${DEFAULT_SYSTEMS[@]}")
else
    systems=("$@")
fi

for system in "${systems[@]}"; do
    echo "[INFO] building image for '${system}'"
    ./run-bakery bake image "${system}"
done

