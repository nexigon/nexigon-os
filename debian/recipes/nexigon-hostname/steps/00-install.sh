#!/usr/bin/env bash

set -euo pipefail

install -D -m 755 "${RECIPE_DIR}/files/nexigon-configure-hostname" -t /usr/libexec/nexigon
install -D -m 644 "${RECIPE_DIR}/files/nexigon-configure-hostname.service" -t /etc/systemd/system
systemctl enable nexigon-configure-hostname.service

