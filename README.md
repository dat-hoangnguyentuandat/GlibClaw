# GlibClaw

A Magisk/KernelSU module that installs [OpenClaw](https://openclaw.ai) on Android (aarch64) using a bundled glibc runtime.

## What's New in v1.0.2

- **No more heavy Node.js bundle!** — Downloads Node.js directly from [nodejs.org](https://nodejs.org) during flash
- **Action button starts gateway** — Press Action in Magisk/KSU to start OpenClaw + open dashboard in one tap

## Screenshots

<table>
  <tr>
    <td width="50%">
      <img src="images/1.jpg" alt="OpenClaw Terminal">
      <p align="center"><b>Terminal Interface</b></p>
    </td>
    <td width="50%">
      <img src="images/2.jpg" alt="OpenClaw Dashboard">
      <p align="center"><b>Dashboard</b></p>
    </td>
  </tr>
</table>

## Requirements

- Android device with root access (Magisk or KernelSU)
- Architecture: **aarch64 only**
- Internet connection required during flash

## Installation

1. Download `GlibClaw-v1.0.2.zip`
2. Flash via Magisk / KernelSU
3. Reboot

## Setup

After reboot, open a root terminal (via [Termux](https://github.com/termux/termux-app/releases/download/v0.119.0-beta.3/termux-app_v0.119.0-beta.3+apt-android-7-github-debug_arm64-v8a.apk)) and run:

### Configure OpenClaw

```sh
su -c /data/adb/openclaw/bin/openclaw configure
```

### Check Status

```sh
su -c /data/adb/openclaw/bin/openclaw status
```

### View Logs

```sh
su -c tail -f /data/adb/openclaw/openclaw.log
```

## Directory Layout

After install, OpenClaw lives at:

```
/data/adb/openclaw/
├── bin/openclaw          # main wrapper
├── glibc-node/           # bundled Node.js runtime
├── lib/node_modules/     # OpenClaw package
└── home/.openclaw/       # user config & workspace
```

## Using the Action Button

If OpenClaw stops running (e.g. after crash), tap **Action** in Magisk or KernelSU Manager:
1. It checks if the gateway is alive — starts it if not
2. Opens the dashboard in your browser

## Uninstall

Remove the module from Magisk/KernelSU app. User data at `/data/adb/openclaw/home` is preserved.

## License

MIT © TDat
