#!/usr/bin/env bash

set -euo pipefail

curl -fsSL https://test.docker.com -o /tmp/install-docker.sh
sh /tmp/install-docker.sh
rm /tmp/install-docker.sh

docker compose version >/dev/null

install -D -m 755 \
    "${RECIPE_DIR}/files/rugix-docker-runtime-components" \
    -t /usr/libexec/rugix
install -D -m 644 \
    "${RECIPE_DIR}/files/docker.toml" \
    -t /etc/rugix/state
install -D -m 644 \
    "${RECIPE_DIR}"/files/*.service \
    -t /usr/lib/systemd/system

systemctl enable \
    docker.service \
    rugix-docker-runtime-components.service \
    rugix-apps-restore-units.service \
    rugix-apps-recover.service
