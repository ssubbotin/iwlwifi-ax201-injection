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
- **M3.1** – instrumented TX path; found the real root cause. Done (see
  [`DIAGNOSIS.md`](DIAGNOSIS.md)): injected frames were dropped in **mac80211**
  by the regulatory `No IR` gate, before iwlwifi, not for lack of a TX queue.
- **M3.2 (reg)** – `iwlwifi.inject` param (default off) withholds `NO_IR`.
  Done: with it, ch36 loses `No IR` and injected frames reach the firmware
  (0 → 11 TX-ring events); ch9 already worked.
- **M3.3 (firmware stability)** – Done. Isolated the `Microcode SW error`
  (`ADVANCED_SYSASSERT 0x4217`) to **raw control frames** injected on the
  stationless sniffer context; management, auth and data frames inject cleanly
  (15/15 to the TX ring, no assert). The driver now drops injected control
  frames in inject mode to protect the firmware. Result: mgmt + data injection
  works, unassociated, on ch36.
- **M4** – reliable unassociated injection independently captured on a second
  radio. Mechanism proven (frames on the TX ring + aireplay "Injection is
  working!"); a dedicated capture radio is still needed for the final proof.

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
