# iwlwifi-ax201-injection

Patched Intel `iwlwifi` driver that lets an **Intel Wi-Fi 6 AX201** transmit raw
802.11 frames from a monitor-mode interface, unassociated, for authorised
wireless testing on the operator's own networks.

Monitor-mode *reception* on this radio already works with the stock driver;
*injection* (transmit) does not, because `iwlwifi`/`mvm` only transmits on a
firmware TX queue owned by a station context and an unassociated monitor
interface has none. This repository routes injected frames onto the driver's
existing stationless (sniffer/aux) queue so they reach the air. See
[`KICKOFF.md`](KICKOFF.md) for the full problem statement and
[`BASELINE.md`](BASELINE.md) for the measured stock behaviour (0% injection).

## Status

- **M1** – stock baseline measured: injection 0/30, RX fine. Done.
- **M2** – out-of-tree / DKMS build, loads with Wi-Fi normal. Done.
- **M3** – queue-routing patch behind a module parameter. Planned.
- **M4** – unassociated injection captured on a second radio. Planned.

## Licence

The driver under `src/drivers/net/wireless/intel/iwlwifi/` is Intel's `iwlwifi`,
licensed **GPL-2.0** (SPDX headers in each file). All modifications in this
repository are released under the same GPL-2.0 licence. Source provenance is
recorded in [`PROVENANCE.md`](PROVENANCE.md).

## Build

Target: kernel `7.0.0-38-generic`, driver built against the installed headers.

```sh
./w2-build.sh            # quick out-of-tree build (no install)
./w2-dkms-install.sh     # register + build + install as a reversible DKMS package
./w2-dkms-remove.sh      # uninstall, restore the stock in-tree driver
```

The DKMS package installs into `/lib/modules/<ver>/updates/`, which `modprobe`
prefers over the stock in-tree modules, and is removed cleanly by the remove
script. Every behaviour change in the patch is gated behind a module parameter
that defaults to off, so a loaded build never disturbs normal Wi-Fi.

## Scope

This targets the AX201 itself. An injection-friendly USB adapter is an explicit
non-goal. On-air transmission targets only the operator's own access points and
devices on a quiet channel.
