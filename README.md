# Glide

Glide is a free app that lets you securely share files and messages with nearby devices over your
local network, without needing an internet connection — a cross-platform alternative to AirDrop.

Glide is a fork of [LocalSend](https://github.com/localsend/localsend); see [NOTICE](NOTICE) for
attribution details.

- [About](#about)
- [Setup](#setup)
- [How It Works](#how-it-works)
- [Dependency Hierarchy](#dependency-hierarchy)
- [Getting Started](#getting-started)
- [Command Line Interface](#command-line-interface)
- [Troubleshooting](#troubleshooting)
- [Building](#building)

## About

Glide is a cross-platform app that enables secure communication between devices using a REST API
and HTTPS encryption. Unlike messaging apps that rely on external servers, Glide doesn't require
an internet connection or third-party servers, making it a fast and reliable solution for local
communication.

Glide is not yet published on any app store or package manager.

## Setup

In most cases, Glide should work out of the box. However, if you are having trouble sending or
receiving files, you may need to configure your firewall to allow Glide to communicate over your
local network.

| Traffic Type | Protocol | Port  | Action |
|--------------|----------|-------|--------|
| Incoming     | TCP, UDP | 53317 | Allow  |
| Outgoing     | TCP, UDP | Any   | Allow  |

On Linux, for example with `ufw`: `sudo ufw allow 53317`. With `firewalld`:
`sudo firewall-cmd --permanent --add-port=53317/tcp`, `sudo firewall-cmd --permanent --add-port=53317/udp`,
then `sudo firewall-cmd --reload`.

Also make sure to disable AP isolation on your router. It should usually be disabled by default but
some routers may have it enabled (especially guest networks). See [troubleshooting](#troubleshooting)
for more information.

**Compatibility**

| Platform | Minimum Version | Note                                                                                                                   |
|----------|-----------------|-------------------------------------------------------------------------------------------------------------------------|
| Android  | 5.0             | -                                                                                                                       |
| iOS      | 12.0            | -                                                                                                                       |
| macOS    | 11 Big Sur      | -                                                                                                                       |
| Windows  | 10              | -                                                                                                                       |
| Linux    | N.A.            | Deps: Gnome: `xdg-desktop-portal` and `xdg-desktop-portal-gtk`, KDE: `xdg-desktop-portal` and `xdg-desktop-portal-kde` |

## How It Works

Glide uses a secure communication protocol that allows devices to communicate with each other using
a REST API. All data is sent securely over HTTPS, and the TLS/SSL certificate is generated on the
fly on each device, ensuring maximum security. The protocol (inherited from LocalSend, default port
`53317`) is unchanged by this fork.

## Dependency Hierarchy

![Dependency hierarchy](support/docs/dependency-hierarchy.svg)

## Getting Started

To compile Glide from the source code, follow these steps:

1. Install [fvm](https://fvm.app) and use it to install the Flutter version pinned in [.fvmrc](.fvmrc)
2. Install [Rust](https://www.rust-lang.org/tools/install)
3. Clone this repository
4. Run `cd app` to enter the app directory
5. Run `fvm flutter pub get` to download dependencies
6. Run `fvm flutter run` to start the app

> [!NOTE]
> This project pins an exact Flutter version (see [.fvmrc](.fvmrc)) and always builds through
> [fvm](https://fvm.app) (`fvm flutter` / `fvm dart`) rather than a system-wide Flutter install, to
> keep builds reproducible.

## Command Line Interface

The Glide CLI is a terminal client built on the LocalSend Protocol v2.
Run `glide-cli --help` to see every available option and hotkey.

Use the `send` command with one or more files, directories, or a mixture of both:

```shell
glide-cli send report.pdf photo.jpg ./project-backup
```

The command opens the discovered-device list; select the destination interactively
and press Enter to start the transfer.

To select the destination without an interactive device list, pass its exact alias
or IP address:

```shell
glide-cli send --to "Cute Tomato" report.pdf
glide-cli send --to 192.168.27.26 report.pdf
```

An alias must uniquely identify a discovered device. An IP address is probed directly
over HTTPS on the default port (`53317`).

Directories are collected recursively. Their selected root names and nested paths
are preserved on the receiver. Empty directories are not sent because the protocol
transfers file entries rather than directory entries.

## Troubleshooting

| Issue              | Platform (Sending) | Platform (Receiving) | Solution                                                                                                                                |
|--------------------|--------------------|----------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| Device not visible | Any                | Any                  | Make sure to disable AP-Isolation on your router. If it is enabled, connections between devices are forbidden.                          |
| Device not visible | Any                | Windows              | Make sure to configure your network as a "private" network. Windows might be more restrictive when the network is configured as public. |
| Device not visible | macOS, iOS         | Any                  | You can try to toggle the "Local Network" permission under "Privacy" in the OS settings.                                                |
| Device not visible | Any                | Any                  | If a VPN is active, allow local/LAN traffic or temporarily disable the VPN. Some VPNs block local network connections by default.       |
| Device not visible | Any                | Any                  | Both devices must be on the same local network and have Glide open; discovery relies on UDP multicast, which some routers block.        |
| Speed too slow     | Any                | Any                  | Use 5 Ghz; Disable encryption on both devices                                                                                           |

## Building

These commands are intended for maintainers only. Make sure to run them from the `app` directory,
and always use `fvm flutter` / `fvm dart` (never the bare `flutter` / `dart` binaries).

### Android

Traditional APK

```bash
fvm flutter build apk
```

AppBundle for Google Play

```bash
fvm flutter build appbundle
```

### iOS

```bash
fvm flutter build ipa
```

### macOS

```bash
fvm flutter build macos
```

### Windows

**Traditional**

```bash
fvm flutter build windows
```

**Local MSIX App**

```bash
fvm dart run msix:create
```

**Store ready**

```bash
fvm dart run msix:create --store
```

### Linux

**Traditional**

```bash
fvm flutter build linux
```

**AppImage**

```bash
appimage-builder --recipe AppImageBuilder.yml
```

---

Glide is a fork of [LocalSend](https://github.com/localsend/localsend) (Apache-2.0). See
[NOTICE](NOTICE) for attribution details.
