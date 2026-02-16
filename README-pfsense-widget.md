# pfSense Widget (gtex62-tech-hud)

A dedicated pfSense Conky widget with live multi-arc traffic markers, load/memory meters,
totals table, and pfBlockerNG/Pi-hole status. Data is collected via SSH and rendered in Lua.

## Status

Active and fully wired.

## Files

- `widgets/pfsense-conky.conf` - Conky entry point for the pfSense arcs widget
- `widgets/sitrep.conky.conf` - SITREP panel entry point (pfSense summary only, no arcs)
- `lua/widgets/pf_widget.lua` - renderer and logic (arcs, markers, meters, tables, status)
- `lua/widgets/pf_reader.lua` - k=v section parser used by the pfSense reader
- `lua/widgets/sitrep.lua` - SITREP renderer (pfSense summary header/tables)
- `theme-pf.lua` - pfSense theme knobs (layout, scaling, colors, arcs)
- `theme-sitrep.lua` - SITREP overrides (pfSense header, totals table, status block)
- `scripts/pf-fetch-basic.sh` - data fetch (pfSense + Pi-hole)
- `scripts/pf-ssh-gate.sh` - SSH safety gate/circuit breaker
- `scripts/pf-rate-all-test.sh` - manual rate/smoothing test (not used by widget)
- `scripts/pf-rate-infra-test.sh` - manual rate test for INFRA (not used by widget)

## Features

- Multi-arc traffic markers for WAN/HOME/IOT/GUEST/INFRA/CAM
- LOAD (per-core) and MEM% center meters
- Interface totals table (cumulative bytes in/out)
- pfBlockerNG summary (IP/DNSBL/Total Queries)
- Pi-hole status line (active/offline, load, totals, domains)
- Theme-driven geometry, colors, fonts, and spacing
- SITREP panel can display pfSense summary lines using the same cached data

## Screenshots

Add screenshots under `screenshots/` as the widget evolves.

## Data sources

### pfSense (via SSH)

- `pfctl -vvsr` for pfBlockerNG IP packet counts (USER_RULE: pfB_, excluding DNSBL)
- `sqlite3 /var/unbound/pfb_py_dnsbl.sqlite` for DNSBL counters
- `sqlite3 /var/unbound/pfb_py_resolver.sqlite` for total queries
- `top`, `uptime`, `sysctl`, `netstat` for system + interface counters

Note: The Conky widget fetch does not execute PHP on pfSense. If you see crash-report PHP fatals mentioning `Command line code` and missing `/usr/local/www/pfblockerng/pfblockerng.inc`, that comes from ad-hoc CLI testing

(`php -r ...`) or a separate pfSense-side script/cron. On pfSense 2.8.1 with pfBlockerNG-devel, the correct include path is `/usr/local/pkg/pfblockerng/pfblockerng.inc`.

### Pi-hole (via SSH to host in theme)

- `systemctl is-active pihole-FTL`
- `/proc/loadavg`
- `sqlite3 /etc/pihole/pihole-FTL.db`
- `sqlite3 /etc/pihole/gravity.db`

Note: `scripts/pf-fetch-basic.sh` uses `sudo -n sqlite3` on the Pi-hole host. Configure sudoers accordingly if needed.

## SSH Safety and Mitigation

The widget polls pfSense via SSH and includes a circuit-breaker to prevent sshguard lockouts.
If repeated SSH failures occur, polling is intentionally paused for a short cooldown.
During this time, the UI displays: `SSH PAUSED - <reason> - <Ns>`.

While paused:

- pfSense is still considered ONLINE.
- Traffic arcs drop to zero to indicate polling is paused.

After the cooldown, polling resumes automatically.

Common reasons and what they mean:

- AUTH: SSH authentication failed or credentials are not accepted.
- PF_SSH_FAIL: pfSense SSH failed from the fetch script.
- PF_LUA_SSH_FAIL: pfSense SSH failed from the Lua metadata fetch.

Manual recovery: run `scripts/pf-ssh-gate.sh reset` to clear the pause.

## Configuration

### Widget entries

`widgets/pfsense-conky.conf` loads `lua/widgets/pf_widget.lua` and controls window placement.

`widgets/sitrep.conky.conf` loads `lua/widgets/sitrep.lua` and renders the SITREP panel
with pfSense summary lines only (no arcs).

### Theme knobs

`theme-pf.lua` is the primary control surface for the arcs (visuals). The SITREP data blocks live in `theme-sitrep.lua` so you can keep the arcs without always showing the data.

Key arc sections:

- `T.ifaces` - interface map (WAN/HOME/IOT/GUEST/INFRA/CAM)
- `T.link_mbps`, `T.link_mbps_in`, `T.link_mbps_out` - caps for normalization
- `T.scale` - linear/log/sqrt scaling and floors
- `T.pf.arc`, `T.pf.deltaR`, `T.pf.anchor_strength` - arc geometry
- `T.pf.arc_names` - dash leader + name labels
- `T.poll` - fetch cadence (interfaces fast, full data slower)

`theme-sitrep.lua` controls the SITREP pfSense block:

- `pf.totals_table` - totals table layout
- `pf.status_block` - pfBlockerNG + Pi-hole status lines
- `pf.load` - pfSense load line (window/cores)
- `sitrep.pfsense` - header/label text

## Usage

Start Conky with:

```bash
conky -c "${CONKY_SUITE_DIR:-$HOME/.config/conky/gtex62-tech-hud}/widgets/pfsense-conky.conf"
```

Or run the SITREP panel:

```bash
conky -c "${CONKY_SUITE_DIR:-$HOME/.config/conky/gtex62-tech-hud}/widgets/sitrep.conky.conf"
```

## Installation

### 1) Install local dependencies

```bash
sudo apt update
sudo apt install -y conky-all openssh-client sqlite3
```

### 2) Ensure SSH access

```bash
ssh pf
ssh pi5
```

Note: `scripts/pf-fetch-basic.sh` uses the SSH host aliases `pf` (pfSense) and `pi5` (Pi-hole).
Define those in `~/.ssh/config`, or update the script to match your hostnames.

The Pi-hole host is configured in `theme-sitrep.lua` (see `pf.status_block.pihole.host`), or you can disable the Pi-hole line entirely.

### 3) Optional: passwordless sqlite3 on Pi-hole

If `sudo -n sqlite3` is not allowed on Pi-hole, add a sudoers rule:

```conf
pi ALL=(root) NOPASSWD: /usr/bin/sqlite3
```

## Quick Start (Minimal Setup)

1) Configure SSH host aliases. Add `Host pf` (pfSense) and `Host pi5` (Pi-hole) to `~/.ssh/config`, or edit `scripts/pf-fetch-basic.sh` to use your hostnames.

2) Set interface map and speeds in `theme-pf.lua`: `T.ifaces`, `T.link_mbps`, `T.link_mbps_in`, `T.link_mbps_out`.

3) Verify `scripts/pf-fetch-basic.sh` runs without prompts: `"${CONKY_SUITE_DIR:-$HOME/.config/conky/gtex62-tech-hud}/scripts/pf-fetch-basic.sh" full | head -n 20`.

4) Start the widget: `conky -c "${CONKY_SUITE_DIR:-$HOME/.config/conky/gtex62-tech-hud}/widgets/pfsense-conky.conf"`.

Optional (SITREP):

- Pi-hole line: set `pf.status_block.pihole.enabled = false` to disable it.
- pfBlockerNG line: set `pf.status_block.pfb.enabled = false` to disable it.

## Troubleshooting

- If markers do not move at low rates, lower `T.scale.sqrt.gamma` or the per-interface floors.
- If data updates feel jerky, increase `T.poll.medium` to reduce slow full fetch frequency.
- If Pi-hole stats are zero, verify SSH to `pf.status_block.pihole.host` and sudo for sqlite3.

## Porting notes

This widget is tailored to a specific pfSense + Pi-hole setup. To reuse it on another system:

- Configure SSH host aliases for pfSense and Pi-hole, or update `scripts/pf-fetch-basic.sh`.
- Set `T.ifaces` in `theme-pf.lua` to your pfSense interface names.
- Update `T.link_mbps`, `T.link_mbps_in`, and `T.link_mbps_out` to match your link speeds.
- Ensure SSH access to pfSense and the Pi-hole host (or disable the Pi-hole line in `pf.status_block`).
- Adjust layout offsets and sizes in `theme-pf.lua` for your display resolution.

## Notes

- The rate test scripts are optional helpers for porting/diagnostics and are not used by the widget.
- All fetch output is k=v sections parsed by `lua/widgets/pf_widget.lua`.

## Host configuration (pfSense)

There are two related settings:

1) **SSH host alias** (required for data fetch). `scripts/pf-fetch-basic.sh` uses `ssh pf` and `ssh pi5`. Configure these in `~/.ssh/config`, or edit the script.

2) **Theme label** (optional). `theme-pf.lua` reads `PFSENSE_HOST` to label the pfSense host; set it in your environment or in `scripts/conky-env.sh`. You can also hardcode `T.host` directly in `theme-pf.lua`.

If both are set, the environment variable wins.
