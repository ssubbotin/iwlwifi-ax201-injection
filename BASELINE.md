# W1 Baseline: stock iwlwifi injection on the AX201

Measured 2026-10-10. Defines what the injection patch (W3) must beat.

## Environment

- Adapter: Intel Wi-Fi 6 AX201, PCI `8086:a0f0` (rev 20), driver `iwlwifi`/`mvm`.
- Kernel: `7.0.0-38-generic`.
- Tooling: `aireplay-ng` (aircrack-ng), `tcpdump`. bettercap v2.24.1 also present.
- Monitor setup: `airmon-ng start wlp0s20f3 36` → `wlp0s20f3mon`, type monitor,
  channel 36 / 5180 MHz, 20 MHz width. On this single-radio card monitor mode
  **disables the station vif**, so the laptop is offline during the test and is
  reconnected afterwards by the harness script's cleanup trap.
- Target: owned AP "Abracadabra", BSSID `cc:d8:43:b2:dd:27`, channel 36 (5 GHz).
- Harness: `w1-baseline.sh` in this directory (restores WiFi on EXIT/INT/TERM).

## Method

The concurrent NM-created monitor vif (`wlp0s20f3mon` present alongside an
active association) is unusable: it reports channel -1 and receives only data
frames, no beacons, so aireplay cannot even start. The working path is the
proven one from `~/wifi-deauth-test.sh`: tear the association down and put the
single radio into a dedicated monitor on one fixed channel (an all-channel scan
wedges the firmware).

Two tests on channel 36:

1. `aireplay-ng -9 wlp0s20f3mon` (broadcast + per-AP directed probe injection).
2. `aireplay-ng -9 -a cc:d8:43:b2:dd:27 wlp0s20f3mon` (directed at the owned AP).

## Results

### RX (receive) — works

- 6 s beacon capture: ~8 beacon frames.
- 4 s unfiltered capture: frames present.
- Conclusion: monitor-mode reception is fine. The receiver is not the problem.

### TX injection — 0%, does not work

Broadcast probe: **"No Answer"**. Directed-probe injection to every AP heard
returned **0 of 30** responses:

| AP (BSSID)                         | Channel | Injection result |
|------------------------------------|---------|------------------|
| Novkovic-5G (`38:88:1E:B1:34:C0`)  | 36      | `0/30  0%`       |
| HotelLoRa 12-5G (`B0:76:1B:AB:C1:D0`) | 36   | `0/30  0%`       |
| Abracadabra (owned, `CC:D8:43:B2:DD:27`) | 36 | `0/30  0%`       |

The APs were *found* (from passively received beacons during the probe phase),
but **no injected probe request drew a single response** from any of them,
including the owned AP on the same channel. Injection success rate: **0%**.

## Interpretation

Stock iwlwifi on the AX201 transmits no injected frames from a monitor
interface: RX is fine, TX injection is dead. This matches the root cause in
KICKOFF.md: `mvm` only transmits on a firmware TX queue owned by a station
context, and an unassociated monitor interface has none, so injected frames are
dropped in the driver before they reach the air.

This is the floor. M4 is reached when a patched driver turns at least one of
these `0/30` lines into a non-zero success rate, confirmed by an independent
capture on a second adapter.

## Follow-up tests (2026-10-10)

### 2.4 GHz band — not run, no owned target

A no-disconnect scan (`iw dev wlp0s20f3 scan`) shows Abracadabra is 5 GHz-only
(ch36). The only 2.4 GHz APs in range (Belano-2.4G, Hotel Lora 16-2.4G, Laki)
are not owned. `aireplay-ng -9` fires directed probe requests at every AP it
hears, so a 2.4 GHz run would probe third-party networks. Deferred until an
owned 2.4 GHz AP is available.

### Injection while associated — inconclusive, needs a second adapter

Method: add a monitor vif (`mon0`) alongside the live station association on
ch36 (keeps WiFi up), then `aireplay-ng -9` on `mon0`. The station stayed
associated, but aireplay never reached injection: on the concurrent monitor vif
it could not hear the AP beacon (`channel -1`, "No such BSSID available"). While
the station vif holds the 160 MHz association, the monitor vif does not receive
management frames, so the beacon-wait stalls before any frame is injected.

Consequence: the "an associated station queue makes injection work" hypothesis
cannot be settled with one adapter and aireplay, because aireplay's measurement
depends on the same concurrent-vif RX that is degraded. Settling it requires
injecting on `mon0` and confirming receipt on a **second independent adapter**
(the W3/M4 setup). Noted, not yet measured.

## Open hardware need

A second capture adapter (any monitor-capable radio) is required to prove both
M4 and the associated-injection hypothesis. Without it, injection can be shown
to fail (0%) but a success cannot be independently confirmed.
