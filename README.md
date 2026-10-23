# loocist.iot — Omarchy IoT plugin

Discover, control, and open the web UI of the IoT devices on your LAN,
straight from the Omarchy bar.

```
~/.config/omarchy/plugins/loocist.iot/
├── manifest.json     # plugin manifest (bar-widget, Network)
├── Panel.qml         # bar icon + popup panel
├── Model.js          # pure string/JSON helpers
└── bin/omarchy-iot   # discovery + control helper (bash + jq + curl + avahi)
```

## What it does

- **Discovery** — scans the LAN over mDNS (`avahi-browse`). Shelly devices
  (Gen1, Gen2, Gen3), Home Assistant, Philips Hue, ESPHome, Matter/HomeKit
  devices and anything else advertising a web UI show up automatically.
- **Control** — any unauthenticated Shelly switch can be toggled from the
  panel: Gen1 over `/relay/N?turn=on`, Gen2/Gen3 over RPC `/rpc/Switch.Set`.
  Live power draw (W) is displayed per device and summed in the hero.
  A Shelly with authentication enabled is listed but marked protected.
- **Web UI** — the link button opens any device's own web interface.

## Panel

- Left-click the bar icon: open the panel
- Right/middle-click the bar icon: rescan
- `r`: rescan · `o`: open the cursor device's web UI
- Arrow keys + Enter/Space: drive switches from the keyboard

## IPC (from scripts or keybindings)

```
omarchy-shell loocist.iot open
omarchy-shell loocist.iot set 192.168.1.60 on     # or off
omarchy-shell loocist.iot toggleDevice 192.168.1.60
omarchy-shell loocist.iot openDevice 192.168.1.60
omarchy-shell loocist.iot list                   # device names
omarchy-shell loocist.iot count
```

## Standalone CLI

`bin/omarchy-iot` is a usable CLI on its own (symlink it into `~/.local/bin`):

```
omarchy-iot list [--cache <sec>]   # JSON inventory of LAN devices
omarchy-iot status <ip>
omarchy-iot set <ip> <on|off>
omarchy-iot toggle <ip>
```

## Requirements

`curl`, `jq`, `avahi` (avahi-browse) — all part of a standard Omarchy install.
No other external dependencies.

## Installation

```
omarchy plugin add https://github.com/Loocist23/omarchy-iot-plugin.git --enable
```

Then place the widget on the bar (right section, next to the network widgets):

```
omarchy bar move loocist.iot --section right --index 5
```

## Removal

```
omarchy plugin disable loocist.iot
omarchy plugin remove loocist.iot --yes
```

`omarchy plugin remove` disables the plugin first, then deletes the cloned
repo from `~/.config/omarchy/plugins/loocist.iot`. The upstream repository is
untouched, so the plugin can be reinstalled with the install command above.

## Extending

New device vendors go in `vendor_of()` in `bin/omarchy-iot`; new drivable
protocols get a branch in `find_component()` / `cmd_set()` and a `*_object()`
builder. The QML renders anything with `controllable: true` as a switch row
and everything else as an "open web UI" row.
