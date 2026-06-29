#!/usr/bin/env bash

set -euo pipefail

VM_DIR=".rugix/staging-vm"
KEY_PATH="${VM_DIR}/id_ed25519"
SSH_PARAM_FILE="${VM_DIR}/ssh.toml"
LOG_PATH="${VM_DIR}/run.log"
SYSTEM="${NEXIGON_STAGING_VM_SYSTEM:-nexigon-os-efi-amd64-vm}"
SSH_PORT="${NEXIGON_STAGING_VM_SSH_PORT:-2222}"

mkdir -p "${VM_DIR}"

if [ ! -f "${KEY_PATH}" ]; then
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -q -N "" -C "nexigon-os-staging-vm"
fi

public_key=$(cat "${KEY_PATH}.pub")
cat >"${SSH_PARAM_FILE}" <<EOF
["core/ssh"]
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

cleanup() {
    if [ -n "${vm_pid:-}" ] && kill -0 "${vm_pid}" >/dev/null 2>&1; then
        kill "${vm_pid}" >/dev/null 2>&1 || true
        wait "${vm_pid}" >/dev/null 2>&1 || true
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

echo "[INFO] waiting for provisioning endpoint"
for _ in $(seq 1 60); do
    if "${ssh_cmd[@]}" 'curl -fsS http://127.0.0.1:51337/' >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

"${ssh_cmd[@]}" 'curl -fsS http://127.0.0.1:51337/'
echo

if [ -z "${NEXIGON_STAGING_PAIRING_KEY:-}" ]; then
    echo "[INFO] readiness check passed; set NEXIGON_STAGING_PAIRING_KEY to test full staging pairing"
    exit 0
fi

echo "[INFO] redeeming staging pairing key"
printf '%s' "${NEXIGON_STAGING_PAIRING_KEY}" \
    | "${ssh_cmd[@]}" 'curl -fsS --data-binary @- http://127.0.0.1:51337/pair'
echo

echo "[INFO] checking provisioned credentials"
"${ssh_cmd[@]}" 'test -s /var/lib/nexigon/agent/credentials.json'
"${ssh_cmd[@]}" 'grep -q "https://staging.nexigon.dev" /var/lib/nexigon/agent/credentials.json'

echo "[INFO] waiting for agent service after pairing"
for _ in $(seq 1 60); do
    if "${ssh_cmd[@]}" 'systemctl is-active --quiet nexigon-agent'; then
        echo "[INFO] staging pairing test passed"
        exit 0
    fi
    sleep 2
done

echo "[ERROR] nexigon-agent did not remain active after pairing" >&2
"${ssh_cmd[@]}" 'journalctl -u nexigon-agent --no-pager -n 120' >&2 || true
exit 1
