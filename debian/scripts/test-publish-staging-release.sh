#!/usr/bin/env bash

# Exercises a complete staging publication with all supported system artifacts.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT

mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/dist"

cat >"${TEST_DIR}/bin/nexigon-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${NEXIGON_CLI_LOG}"

case "$1 $2 $3" in
    "repositories s3 get")
        printf '%s\n' \
            '{"s3Config":{"endpoint":"https://s3.example.test","bucket":"test","accessKeyId":"access"}}'
        ;;
    "repositories packages list")
        printf '%s\n' '{"packages":[]}'
        ;;
    "repositories packages create")
        printf '%s\n' '{"packageId":"package-1"}'
        ;;
    "repositories versions resolve")
        printf '%s\n' '{"result":"NotFound"}'
        ;;
    "repositories versions create")
        printf '%s\n' '{"versionId":"version-1"}'
        ;;
    "repositories versions info")
        printf '%s\n' '{"assets":[]}'
        ;;
    "repositories assets upload")
        printf '%s\n' '{"assetId":"asset-1"}'
        ;;
    "repositories versions assets"|"repositories versions tag")
        printf '%s\n' '{}'
        ;;
    *)
        echo "unexpected nexigon-cli invocation: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "${TEST_DIR}/bin/nexigon-cli"

systems=(
    nexigon-os-efi-amd64
    nexigon-os-efi-arm64
    nexigon-os-rpi5
    nexigon-os-rpi4
)

for system in "${systems[@]}"; do
    mkdir -p "${TEST_DIR}/dist/${system}"
    for suffix in img.xz rugixb spdx.json cdx.json; do
        touch "${TEST_DIR}/dist/${system}/${system}.${suffix}"
    done
    printf '%s\n' 'sha512-256:expected' \
        >"${TEST_DIR}/dist/${system}/${system}.rugixb-hash"
    printf '%s\n' '{"release":{"version":"build-test"}}' \
        >"${TEST_DIR}/dist/${system}/${system}.build-info.json"
done

export NEXIGON_CLI_LOG="${TEST_DIR}/nexigon-cli.log"

ARTIFACT_DIR="${TEST_DIR}/dist" \
NEXIGON_CLI="${TEST_DIR}/bin/nexigon-cli" \
NEXIGON_REPOSITORY="test-repository" \
BUILD_TAG="build-test" \
SOURCE_COMMIT="test-commit" \
FLOATING_TAG="latest-build-main" \
PUBLISH_STAGING="true" \
    "${ROOT}/scripts/publish-staging-release.sh" >/dev/null

grep -q 'repositories versions create test-repository/nexigon-os' \
    "${NEXIGON_CLI_LOG}"
grep -q '^repositories packages create test-repository nexigon-os$' \
    "${NEXIGON_CLI_LOG}"
grep -q '"bundleHash":"sha512-256:expected"' "${NEXIGON_CLI_LOG}"
grep -q -- '--tag latest-build-main,reassign --tag staging,reassign' \
    "${NEXIGON_CLI_LOG}"

asset_add_count=$(grep -c '^repositories versions assets add ' \
    "${NEXIGON_CLI_LOG}")
if [ "${asset_add_count}" -ne 24 ]; then
    echo "expected 24 attached assets, found ${asset_add_count}" >&2
    exit 1
fi
