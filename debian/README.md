# Nexigon OS

Nexigon OS is a ready-to-flash Debian image built with Rugix Bakery.
This first variant contains the core Nexigon Agent integration only: devices boot unpaired, expose the local provisioning endpoint, and can be paired with a Nexigon project using a one-time pairing key.

## Systems

- `nexigon-os-efi-amd64`: generic 64-bit x86 EFI systems.
- `nexigon-os-efi-arm64`: generic 64-bit ARM EFI systems.
- `nexigon-os-efi-amd64-vm`: x86 EFI VM image with SSH enabled for staging validation.
- `nexigon-os-rpi5`: Raspberry Pi 5, Raspberry Pi 4, and CM4 with recent firmware.
- `nexigon-os-rpi4`: Raspberry Pi 4 and CM4 with bundled Pi 4 firmware update.

## Build

Build all images:

```sh
./scripts/build-images.sh
```

Build one image:

```sh
./scripts/build-images.sh nexigon-os-efi-amd64
```

Artifacts are written to `build/<system>/system.img`.

## Staging VM Test

Run a local EFI VM against `https://staging.nexigon.dev`:

```sh
./scripts/test-staging-vm.sh
```

To test full pairing, create a staging pairing key and provide it as:

```sh
NEXIGON_STAGING_PAIRING_KEY="..." ./scripts/test-staging-vm.sh
```

## Pairing

After flashing and booting, create a pairing key in Nexigon Hub and send it to the device:

```sh
curl --data "PAIRING-KEY" http://DEVICE_ADDRESS:6947/pair
```

The device hostname is set at boot from stable device identity data and follows `nexigon-<suffix>`.
