#!/usr/bin/env bash

set -euo pipefail

VM_DIR=".staging-vm"
KEY_PATH="${VM_DIR}/id_ed25519"
SSH_PARAM_FILE="${VM_DIR}/ssh.toml"
LOG_PATH="${VM_DIR}/run.log"
SYSTEM="${NEXIGON_STAGING_VM_SYSTEM:-nexigon-os-efi-amd64-vm}"
SSH_PORT="${NEXIGON_STAGING_VM_SSH_PORT:-2222}"
NEXIGON_CLI="${NEXIGON_CLI:-nexigon-cli}"

mkdir -p "${VM_DIR}"

if [ ! -f "${KEY_PATH}" ]; then
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -q -N "" -C "nexigon-os-staging-vm"
fi

public_key=$(cat "${KEY_PATH}.pub")
cat >"${SSH_PARAM_FILE}" <<EOF
["ssh"]
root_authorized_keys = "${public_key}"
EOF

ssh_cmd=(
    ssh
    -i "${KEY_PATH}"
    -p "${SSH_PORT}"
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    "root@127.0.0.1"
)

run_cli() {
    if [ -n "${NEXIGON_CLI_CONFIG:-}" ]; then
        "${NEXIGON_CLI}" --config "${NEXIGON_CLI_CONFIG}" "$@"
    else
        "${NEXIGON_CLI}" "$@"
    fi
}

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    if [ -n "${vm_pid:-}" ] && kill -0 "${vm_pid}" >/dev/null 2>&1; then
        kill "${vm_pid}" >/dev/null 2>&1 || true
        wait "${vm_pid}" >/dev/null 2>&1 || true
    fi
    if [ -n "${created_device_id:-}" ] \
        && [ "${NEXIGON_STAGING_KEEP_DEVICE:-false}" != true ]; then
        run_cli devices delete "${created_device_id}" >/dev/null 2>&1 || true
    fi
    if [ -n "${pairing_key_id:-}" ] && [ "${pairing_key_redeemed:-false}" != true ]; then
        revoke_input=$(jq -nc \
            --arg pairing_key_id "${pairing_key_id}" \
            '{pairingKeyId: $pairing_key_id}')
        run_cli actions execute projects_RevokeDevicePairingKey \
            "${revoke_input}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "[INFO] starting ${SYSTEM}; log: ${LOG_PATH}"
./run-bakery run \
    --param-file params/staging.toml \
    --param-file "${SSH_PARAM_FILE}" \
    "${SYSTEM}" >"${LOG_PATH}" 2>&1 &
vm_pid=$!

echo "[INFO] waiting for SSH on 127.0.0.1:${SSH_PORT}"
for _ in $(seq 1 180); do
    if "${ssh_cmd[@]}" true >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${vm_pid}" >/dev/null 2>&1; then
        echo "[ERROR] VM exited before SSH became available" >&2
        tail -n 120 "${LOG_PATH}" >&2 || true
        exit 1
    fi
    sleep 2
done

if ! "${ssh_cmd[@]}" true >/dev/null 2>&1; then
    echo "[ERROR] timed out waiting for SSH" >&2
    tail -n 120 "${LOG_PATH}" >&2 || true
    exit 1
fi

echo "[INFO] checking staged agent configuration"
"${ssh_cmd[@]}" 'grep -q "https://staging.nexigon.dev" /etc/nexigon/agent.toml'

echo "[INFO] checking Rugix Apps runtime"
"${ssh_cmd[@]}" 'systemctl is-active --quiet docker'
"${ssh_cmd[@]}" 'docker compose version >/dev/null'
"${ssh_cmd[@]}" 'systemctl is-enabled --quiet rugix-apps-recover.service'
"${ssh_cmd[@]}" 'systemctl is-enabled --quiet rugix-apps-restore-units.service'
"${ssh_cmd[@]}" 'systemctl is-enabled --quiet rugix-docker-runtime-components.service'
"${ssh_cmd[@]}" 'systemctl is-active --quiet rugix-apps-restore-units.service'
runtime_components_result=$("${ssh_cmd[@]}" \
    'systemctl show --property=Result --value rugix-docker-runtime-components.service')
test "${runtime_components_result}" = success
"${ssh_cmd[@]}" 'grep -Fq "id = \"runtime.docker\"" /run/rugix/components/docker.toml'
"${ssh_cmd[@]}" 'grep -Fq "id = \"runtime.docker-compose\"" /run/rugix/components/docker.toml'
"${ssh_cmd[@]}" 'systemctl is-active --quiet rugix-apps-recover.service'

echo "[INFO] checking Nexigon Rugix commands and OTA configuration"
"${ssh_cmd[@]}" 'test -f /etc/nexigon/agent/commands/nexigon.rugix-apps.deploy.toml'
"${ssh_cmd[@]}" 'test -f /etc/nexigon/agent/commands/nexigon.rugix-apps.list.toml'
"${ssh_cmd[@]}" 'grep -q "NEXIGON_RUGIX_APPS_USE_BUNDLE_HASH:-true" /usr/libexec/nexigon/nexigon-rugix-apps-deploy'
"${ssh_cmd[@]}" 'test -f /etc/nexigon-rugix-ota.json'
"${ssh_cmd[@]}" 'jq -e ".rugix.useBundleHash == true" /etc/nexigon-rugix-ota.json >/dev/null'
"${ssh_cmd[@]}" 'systemctl is-enabled --quiet nexigon-rugix-ota.timer'
"${ssh_cmd[@]}" 'systemctl is-active --quiet nexigon-rugix-ota.timer'
"${ssh_cmd[@]}" 'systemctl start nexigon-rugix-ota.service'
"${ssh_cmd[@]}" 'journalctl -u nexigon-rugix-ota.service --no-pager | grep -q "OTA remains idle"'

echo "[INFO] waiting for provisioning endpoint"
for _ in $(seq 1 60); do
    if "${ssh_cmd[@]}" 'curl -fsS http://127.0.0.1:6947/' >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

"${ssh_cmd[@]}" 'curl -fsS http://127.0.0.1:6947/'
echo

pairing_key="${NEXIGON_STAGING_PAIRING_KEY:-}"
if [ -z "${pairing_key}" ]; then
    if [ -z "${NEXIGON_STAGING_PROJECT_ID:-}" ]; then
        echo "[INFO] readiness check passed; set NEXIGON_STAGING_PROJECT_ID to issue a key and test full staging pairing"
        exit 0
    fi
    if [ -z "${NEXIGON_CLI_CONFIG:-}" ]; then
        echo "[ERROR] NEXIGON_CLI_CONFIG is required to issue a staging pairing key" >&2
        exit 1
    fi

    echo "[INFO] issuing a one-time staging pairing key"
    create_input=$(jq -nc \
        --arg project_id "${NEXIGON_STAGING_PROJECT_ID}" \
        '{projectId: $project_id, name: "nexigon-os-staging-vm", validForSecs: 600}')
    pairing_info=$(run_cli actions execute \
        projects_CreateDevicePairingKey "${create_input}")
    pairing_key_id=$(jq -er \
        '.Ok.pairingKeyId | select(type == "string" and length > 0)' \
        <<<"${pairing_info}")
    pairing_key=$(jq -er \
        '.Ok.pairingKey | select(type == "string" and length > 0)' \
        <<<"${pairing_info}")
    pairing_key_issued=true
fi

echo "[INFO] redeeming staging pairing key"
printf '%s' "${pairing_key}" \
    | "${ssh_cmd[@]}" 'curl -fsS --data-binary @- http://127.0.0.1:6947/pair'
echo
pairing_key_redeemed=true
pairing_key=""

echo "[INFO] checking provisioned credentials"
"${ssh_cmd[@]}" 'test -s /var/lib/nexigon/agent/credentials.json'
"${ssh_cmd[@]}" 'grep -q "https://staging.nexigon.dev" /var/lib/nexigon/agent/credentials.json'

echo "[INFO] waiting for agent service after pairing"
for _ in $(seq 1 60); do
    if "${ssh_cmd[@]}" 'systemctl is-active --quiet nexigon-agent'; then
        break
    fi
    sleep 2
done

if ! "${ssh_cmd[@]}" 'systemctl is-active --quiet nexigon-agent'; then
    echo "[ERROR] nexigon-agent did not remain active after pairing" >&2
    "${ssh_cmd[@]}" 'journalctl -u nexigon-agent --no-pager -n 120' >&2 || true
    exit 1
fi

if [ "${pairing_key_issued:-false}" = true ]; then
    echo "[INFO] waiting for the paired device to connect to Nexigon staging"
    query_input=$(jq -nc \
        --arg project_id "${NEXIGON_STAGING_PROJECT_ID}" \
        '{projectId: $project_id}')

    for _ in $(seq 1 60); do
        pairing_keys=$(run_cli actions execute \
            projects_QueryDevicePairingKeys "${query_input}")
        device_id=$(jq -er \
            --arg pairing_key_id "${pairing_key_id}" \
            'first(.Ok.pairingKeys[] | select(.pairingKeyId == $pairing_key_id) | .deviceId) // empty' \
            <<<"${pairing_keys}" 2>/dev/null || true)

        if [ -n "${device_id}" ]; then
            created_device_id=${device_id}
            device_info=$(run_cli devices info "${device_id}")
            if jq -e '.isConnected == true' <<<"${device_info}" >/dev/null; then
                echo "[INFO] staging pairing and authenticated device connection passed"
                exit 0
            fi
        fi
        sleep 2
    done

    echo "[ERROR] paired device did not become connected in Nexigon staging" >&2
    "${ssh_cmd[@]}" 'journalctl -u nexigon-agent --no-pager -n 120' >&2 || true
    exit 1
fi

echo "[INFO] staging pairing test passed"
