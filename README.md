# Nexigon OS

> [!CAUTION]
> This is a prototype. **Do not use in production.**

Nexigon OS is a ready-made Linux-based OS for embedded devices built around the
[Nexigon](https://nexigon.cloud) device management platform. It is the easiest
way to get started and features a container-based deployment model for
application workloads using [Rugix Apps](https://rugix.org).

The prototype provides:

- pairing-key provisioning and remote administration through Nexigon;
- Docker and Docker Compose as the Rugix Apps runtime;
- application deploy, start, stop, rollback, and removal commands;
- A/B operating-system updates with automatic rollback protection; and
- bundle verification against hashes stored in authenticated Nexigon metadata.

Images are built for generic 64-bit x86 and ARM EFI systems, Raspberry Pi 5,
Raspberry Pi 4, and Compute Module 4. An x86 VM variant is included for local
validation.

## Quick Start

Get yourself a Nexigon account and create an organization.

Select an image suitable for your device from the GitHub releases page.

Flash the image onto the device.

Create a pairing key in the Nexigon UI and pair the device with:

```sh
curl --data PAIRING_KEY http://DEVICE_ADDRESS:6947/pair
```

After pairing, applications can be deployed from Nexigon package versions as
Rugix App bundles. OS updates are selected through the
`dev.nexigon.ota.config` device property, for example:

```json
{ "path": "REPOSITORY/nexigon-os/staging" }
```

## Prototype Security Model

The staging publisher attaches Rugix bundle hashes to application and OS asset
metadata (currently SHA-512/256), and Nexigon OS uses these hashes when they are
present. Because devices obtain metadata and download URLs through their
authenticated Nexigon connection, this protects the prototype against
corrupted or substituted downloads. An asset without hash metadata is left to
Rugix's normal signature verification, allowing properly signed bundles to be
installed. Metadata hashes are not independent publisher signatures: a
compromised Nexigon account or service could replace both an artifact and its
hash.

See [`debian/README.md`](debian/README.md) for build, staging publication, and
VM validation instructions.
