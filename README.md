# Nexigon OS

> [!CAUTION]
> This is a prototype. **Do not use in production.**

Nexigon OS is a ready-made Linux-based OS for embedded devices built around the
[Nexigon](https://nexigon.cloud) device management platform. It is the easiest
way to get started and features a container-based deployment model for
application workloads using [Rugix Apps](https://rugix.org).

## Quick Start

Get yourself a Nexigon account and create an organization.

Select an image suitable for your device from the GitHub releases page.

Flash the image onto the device.

Create a pairing key in the Nexigon UI and pair the device with:

```sh
curl --data PAIRING_KEY http://DEVICE_ADDRESS:6947/pair
```
