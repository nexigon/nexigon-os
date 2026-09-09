#!/usr/bin/env bash

set -euo pipefail

NEXIGON_CLI=${NEXIGON_CLI:-nexigon-cli}
NEXIGON_PACKAGE=${NEXIGON_PACKAGE:-nexigon-os}
ARTIFACT_DIR=${ARTIFACT_DIR:-dist}
SYSTEMS=(
    nexigon-os-efi-amd64
    nexigon-os-efi-arm64
    nexigon-os-rpi5
    nexigon-os-rpi4
)

require_variable() {
    if [ -z "${!1:-}" ]; then
        echo "[ERROR] $1 is not set" >&2
        exit 1
    fi
}

run_cli() {
    if [ -n "${NEXIGON_CLI_CONFIG:-}" ]; then
        "${NEXIGON_CLI}" --config "${NEXIGON_CLI_CONFIG}" "$@"
    else
        "${NEXIGON_CLI}" "$@"
    fi
}

find_artifact() {
    local filename="$1"
    local nested_path="${ARTIFACT_DIR}/${filename%%.*}/${filename}"
    local flat_path="${ARTIFACT_DIR}/${filename}"

    if [ -f "${nested_path}" ]; then
        printf '%s\n' "${nested_path}"
    elif [ -f "${flat_path}" ]; then
        printf '%s\n' "${flat_path}"
    else
        echo "[ERROR] required artifact '${filename}' is missing" >&2
        exit 1
    fi
}

validate_repository_storage() {
    local storage_info

    storage_info=$(run_cli repositories s3 get "${NEXIGON_REPOSITORY}")
    if ! jq -e '
        .s3Config.endpoint | type == "string" and length > 0
    ' <<<"${storage_info}" >/dev/null \
        || ! jq -e '
            .s3Config.bucket | type == "string" and length > 0
        ' <<<"${storage_info}" >/dev/null \
        || ! jq -e '
            .s3Config.accessKeyId | type == "string" and length > 0
        ' <<<"${storage_info}" >/dev/null; then
        echo "[ERROR] repository asset storage is not configured" >&2
        exit 1
    fi
}

ensure_package() {
    local package_path="${NEXIGON_REPOSITORY}/${NEXIGON_PACKAGE}"
    local package_info package_count

    package_info=$(run_cli repositories packages list "${NEXIGON_REPOSITORY}")
    package_count=$(jq -er \
        --arg name "${NEXIGON_PACKAGE}" \
        '[.packages[] | select(.name == $name)] | length' \
        <<<"${package_info}")

    case "${package_count}" in
        1)
            ;;
        0)
            echo "[INFO] creating package '${package_path}'" >&2
            run_cli repositories packages create \
                "${NEXIGON_REPOSITORY}" "${NEXIGON_PACKAGE}" >/dev/null
            ;;
        *)
            echo "[ERROR] multiple packages named '${NEXIGON_PACKAGE}' exist in '${NEXIGON_REPOSITORY}'" >&2
            exit 1
            ;;
    esac
}

resolve_or_create_version() {
    local package_path="${NEXIGON_REPOSITORY}/${NEXIGON_PACKAGE}"
    local version_info result metadata

    version_info=$(run_cli repositories versions resolve \
        "${package_path}/${BUILD_TAG}")
    result=$(jq -er '.result' <<<"${version_info}")

    case "${result}" in
        Found)
            jq -er '.versionId | select(type == "string" and length > 0)' \
                <<<"${version_info}"
            ;;
        NotFound)
            metadata=$(jq -nc \
                --arg image_version "${BUILD_TAG}" \
                --arg source_commit "${SOURCE_COMMIT}" \
                '{imageVersion: $image_version, sourceCommit: $source_commit}')
            run_cli repositories versions create "${package_path}" \
                --tag "${BUILD_TAG},locked" \
                --metadata "${metadata}" \
                | jq -er '.versionId | select(type == "string" and length > 0)'
            ;;
        *)
            echo "[ERROR] unable to resolve '${package_path}/${BUILD_TAG}'" >&2
            exit 1
            ;;
    esac
}

asset_metadata() {
    local filename="$1"
    local system="${filename%%.*}"
    local bundle_hash

    case "${filename}" in
        *.rugixb)
            bundle_hash=$(tr -d '\r\n' \
                <"$(find_artifact "${system}.rugixb-hash")")
            if [ -z "${bundle_hash}" ]; then
                echo "[ERROR] bundle hash for '${filename}' is empty" >&2
                exit 1
            fi
            jq -nc \
                --arg bundle_hash "${bundle_hash}" \
                --arg spdx "${system}.spdx.json" \
                --arg cdx "${system}.cdx.json" \
                --arg version "${BUILD_TAG}" \
                '{rugix: {bundleHash: $bundle_hash}, relations: {sbom: [$spdx, $cdx]}, version: $version}'
            ;;
        *.img.xz)
            jq -nc \
                --arg spdx "${system}.spdx.json" \
                --arg cdx "${system}.cdx.json" \
                '{relations: {sbom: [$spdx, $cdx]}}'
            ;;
    esac
}

validate_system_artifacts() {
    local system="$1"
    local baked_version filename
    local suffixes=(
        img.xz
        rugixb
        rugixb-hash
        spdx.json
        cdx.json
        build-info.json
    )

    for suffix in "${suffixes[@]}"; do
        filename="${system}.${suffix}"
        find_artifact "${filename}" >/dev/null
    done

    baked_version=$(jq -er '.release.version' \
        "$(find_artifact "${system}.build-info.json")")
    if [ "${baked_version}" != "${BUILD_TAG}" ]; then
        echo "[ERROR] '${system}' was built as '${baked_version}', expected '${BUILD_TAG}'" >&2
        exit 1
    fi

    asset_metadata "${system}.rugixb" >/dev/null
}

upload_assets() {
    local version_id="$1"
    local version_info asset_info asset_id metadata filename path
    local -A attached=()
    local suffixes=(
        spdx.json
        cdx.json
        build-info.json
        img.xz
        rugixb
        rugixb-hash
    )

    version_info=$(run_cli repositories versions info "${version_id}")
    while IFS= read -r filename; do
        attached["${filename}"]=1
    done < <(jq -r '.assets[]?.filename' <<<"${version_info}")

    for system in "${SYSTEMS[@]}"; do
        for suffix in "${suffixes[@]}"; do
            filename="${system}.${suffix}"
            if [ -n "${attached[${filename}]:-}" ]; then
                echo "[INFO] '${filename}' is already attached; skipping"
                continue
            fi

            path=$(find_artifact "${filename}")
            echo "[INFO] uploading '${filename}'"
            asset_info=$(run_cli repositories assets upload \
                "${NEXIGON_REPOSITORY}" "${path}")
            asset_id=$(jq -er \
                '.assetId | select(type == "string" and length > 0)' \
                <<<"${asset_info}")
            metadata=$(asset_metadata "${filename}")
            if [ -n "${metadata}" ]; then
                run_cli repositories versions assets add \
                    "${version_id}" "${asset_id}" "${filename}" \
                    --metadata "${metadata}"
            else
                run_cli repositories versions assets add \
                    "${version_id}" "${asset_id}" "${filename}"
            fi
            attached["${filename}"]=1
        done
    done
}

tag_version() {
    local version_id="$1"
    local tag_args=()

    if [ -n "${FLOATING_TAG:-}" ]; then
        tag_args+=(--tag "${FLOATING_TAG},reassign")
    fi
    if [ "${PUBLISH_STAGING:-false}" = true ]; then
        tag_args+=(--tag "staging,reassign")
    fi
    if [ "${#tag_args[@]}" -gt 0 ]; then
        run_cli repositories versions tag "${version_id}" "${tag_args[@]}"
    fi
}

require_variable NEXIGON_REPOSITORY
require_variable BUILD_TAG

if [ ! -d "${ARTIFACT_DIR}" ]; then
    echo "[ERROR] artifact directory '${ARTIFACT_DIR}' does not exist" >&2
    exit 1
fi

SOURCE_COMMIT=${SOURCE_COMMIT:-$(git rev-parse HEAD)}

for system in "${SYSTEMS[@]}"; do
    validate_system_artifacts "${system}"
done

validate_repository_storage
ensure_package
version_id=$(resolve_or_create_version)
upload_assets "${version_id}"
tag_version "${version_id}"

echo "[INFO] published '${BUILD_TAG}' to '${NEXIGON_REPOSITORY}/${NEXIGON_PACKAGE}'"
