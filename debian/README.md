# Nexigon OS

Nexigon OS is a ready-to-flash Debian image built with Rugix Bakery. Devices
boot unpaired, expose the local provisioning endpoint, and can be paired with a
Nexigon project using a one-time pairing key. Every release target contains the
Nexigon Agent, Docker and Docker Compose, the Rugix Apps runtime, and Rugix A/B
system updates.

## Systems

- `nexigon-os-efi-amd64`: generic 64-bit x86 EFI systems.
- `nexigon-os-efi-arm64`: generic 64-bit ARM EFI systems.
- `nexigon-os-efi-amd64-vm`: x86 EFI VM with SSH for staging validation.
- `nexigon-os-rpi5`: Raspberry Pi 5, Raspberry Pi 4, and CM4 with recent
  firmware.
- `nexigon-os-rpi4`: Raspberry Pi 4 and CM4 with a bundled Pi 4 firmware
  update.

## Build

Build all images and full-system update bundles:

```sh
./scripts/build-images.sh
```

Build one target:

```sh
./scripts/build-images.sh nexigon-os-efi-amd64
```

Artifacts are written to `build/<system>/`. The important outputs are
`system.img`, `system.rugixb`, `system.rugixb-hash`, the SPDX and CycloneDX
SBOMs, and `system-build-info.json`.

To build an artifact with staging Agent configuration and an explicit version:

```sh
./run-bakery bake bundle nexigon-os-efi-amd64 \
    --release-version build-example \
    --param-file params/staging.toml
```

## Staging VM Test

Run a local EFI VM against `https://staging.nexigon.dev`:

```sh
./scripts/test-staging-vm.sh
```

The smoke test checks the staged Agent configuration, Docker and Compose, Rugix
Apps services, Nexigon app commands, OTA hash enforcement, and the local pairing
endpoint. To test full pairing, use a host-side Nexigon CLI configuration with
an organization API token and identify the destination project:

```sh
NEXIGON_CLI_CONFIG="/private/path/cli.toml" \
NEXIGON_STAGING_PROJECT_ID="project-id" \
    ./scripts/test-staging-vm.sh
```

The script uses the organization token only through the host-side CLI. It
issues a short-lived one-time pairing key, sends only that key to the VM, and
then verifies through Nexigon that the paired device is connected. An unused
key is revoked automatically if the test exits early, and a device created by
the test is deleted during cleanup. Set `NEXIGON_STAGING_KEEP_DEVICE=true` to
retain it for inspection. For compatibility, a manually issued key can instead
be provided as:

```sh
NEXIGON_STAGING_PAIRING_KEY="..." ./scripts/test-staging-vm.sh
```

## Pairing

After flashing and booting, create a pairing key in Nexigon Hub and send it to
the device:

```sh
curl --data "PAIRING-KEY" http://DEVICE_ADDRESS:6947/pair
```

The device hostname is set at boot from stable device identity data and follows
`nexigon-<suffix>`.

## Applications

Nexigon OS uses Docker as the runtime for Rugix Apps. The Nexigon Agent exposes
commands for listing, deploying, starting, stopping, rolling back, and removing
apps. When a `.rugixb` app asset includes a Rugix bundle hash at
`metadata.rugix.bundleHash`, deployment passes it to Rugix Ctrl. Without this
metadata, Rugix Ctrl performs its normal signature verification.

## OS Updates

The OTA timer remains idle until the device property
`dev.nexigon.ota.config` supplies a Nexigon version path:

```json
{ "path": "REPOSITORY/nexigon-os/staging" }
```

The selected package version must have `metadata.imageVersion` and contain one
bundle named `<system>.rugixb` for each target. Bundle assets can carry
`metadata.rugix.bundleHash`; when absent, Rugix Ctrl verifies the bundle's
signature instead. Successful boots are committed automatically; an uncommitted
update reboots back to the previous system after the watchdog's 30-minute
timeout.

## Staging Publication

The GitHub Actions workflow builds all release targets with
`params/staging.toml`, runs a credential-free x86 VM smoke test, and can publish
the resulting images, update bundles, hashes, SBOMs, and build information to
`https://staging.nexigon.dev`.

Configure these repository settings:

- Variable `NEXIGON_STAGING_REPOSITORY`: destination repository name or ID.
  Leaving this unset disables staging publication.
- Variable `NEXIGON_STAGING_PACKAGE`: destination package name; defaults to
  `nexigon-os`.
- Secret `NEXIGON_STAGING_TOKEN`: token used by Nexigon CLI.

The organization token remains in a temporary CLI configuration on the GitHub
runner and is never embedded in an image or passed to a VM. Publication needs
repository view and asset permissions plus package view and version
permissions; creating the `nexigon-os` package on its first run additionally
needs package-management permission.

Each build receives a locked version tag. The newest build of a branch also
receives `latest-build-<branch>`, and the newest `main` build receives the
`staging` tag.

The publisher is idempotent for assets already attached to a build version. It
also checks that every target's embedded release version matches the Nexigon
version before uploading anything. The destination repository must have
working S3-compatible asset storage configured. Link it to every project whose
devices should be able to install these artifacts.

## Prototype Security Model

Nexigon OS uses Rugix bundle hashes for application and OS updates when they are
available. The staging publisher includes these hashes in asset metadata
received through the device's authenticated Nexigon connection. This verifies
download integrity, but is not an independent publisher signature: an account
or service able to replace both an artifact and its metadata remains trusted.
When hash metadata is absent, normal Rugix signing and configured trust roots
apply.
