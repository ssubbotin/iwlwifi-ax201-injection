# KICKOFF: patch iwlwifi for reliable 802.11 frame injection on the AX201

## Goal

Patch the `iwlwifi` driver so this laptop's Intel AX201 transmits arbitrary,
raw 802.11 management and data frames from a monitor-mode interface, reliably,
on a chosen channel, at a chosen rate, without being associated to an access
point. Monitor-mode reception already works; the deliverable is transmission of
injected frames.

Success: a crafted frame handed to the monitor netdev leaves the radio and is
captured by an independent sniffer. Acceptance test: `aireplay-ng --test`
passes on the patched driver and a second adapter records the frames.

The patch is the whole project. An external USB adapter is an explicit
**non-goal** (see below): the point is to make this radio do it.

## Hardware and software baseline (measured 2026-10-10)

- Adapter: Intel Wi-Fi 6 AX201, PCI id `8086:a0f0` (rev 20), `00:14.3`.
- Driver: `iwlwifi` / `mvm` opmode (in-tree), firmware `iwlwifi-*.ucode` from
  linux-firmware.
- Kernel: `7.0.0-38-generic`.
- Monitor interface `wlp0s20f3mon` already present and receiving; `phy0`
  advertises `monitor` in supported interface modes.
- `aircrack-ng` installed and is the reference test harness.

## Root cause, precisely

`mac80211` accepts an injected frame on the monitor netdev and hands it to the
low-level driver TX path. `iwlwifi`/`mvm` transmits every frame on a firmware
TX queue that belongs to a *station context*. With no station there is no
queue, so an injected frame from an unassociated monitor interface is dropped
inside the driver before it reaches the air.

The lever is that `mvm` already owns two stationless contexts:

- the **AUX** station (`mvm->aux_sta`, scan/offchannel), and
- the **sniffer** station (`mvm->snif_sta` + `mvm->snif_queue`), created for the
  monitor vif in `iwl_mvm_add_snif_sta()`.

The sniffer station is the natural home for injected monitor TX: it exists
precisely for a monitor vif and already has a queue. The work is to route
injected frames onto it and make the firmware accept them off-association.

## Code map (where the work happens)

In `drivers/net/wireless/intel/iwlwifi/mvm/`:

- `mac80211.c` : `iwl_mvm_mac_tx()` / the `.tx` op. Entry point for every TX,
  including injected frames. This is where a frame with no associated `sta`
  must be recognised and steered to the sniffer/aux queue instead of dropped.
- `tx.c` : `iwl_mvm_tx_skb_sta()`, `iwl_mvm_tx_mpdu()`,
  `iwl_mvm_set_tx_params()`. Builds the `TX_CMD`. Must honour the radiotap
  rate/flags on the injected skb (`IEEE80211_TX_CTL_INJECTED`,
  `info->control.rates`) rather than substituting association rates, and must
  pick the sniffer queue for the stationless case.
- `sta.c` : `iwl_mvm_add_snif_sta()` / `iwl_mvm_rm_snif_sta()`. Confirm the
  sniffer station and its queue are created and kept alive whenever the monitor
  vif is up, so there is always a queue to inject on.
- `mvm.h` : `snif_sta`, `snif_queue`, `aux_sta`, queue id defines.

Grep anchors to start from: `IEEE80211_TX_CTL_INJECTED`, `snif_sta`,
`snif_queue`, `aux_sta`, `iwl_mvm_tx_skb_sta`, `IWL_MVM_INVALID_STA`.

## Workstreams

### W1. Empirical baseline (no code, first)

Measure exactly what the stock driver does before touching it.

- Fixed-channel monitor iface, then `aireplay-ng --test <mon>` (`-9`). Record
  working / partial / none, per band (2.4 vs 5 GHz behave differently).
- Repeat while associated to an owned test AP on the same channel to confirm
  the station-queue hypothesis.
- Confirm with a capture on a second adapter; `aireplay` reports can be
  optimistic.
- Deliverable: `BASELINE.md` with exact commands, kernel/firmware versions,
  raw results. This defines what the patch must beat.

### W2. Build environment: out-of-tree iwlwifi

Iterate on the driver without rebuilding the whole kernel.

- Build `backport-iwlwifi` (iwlwifi-dkms) against `7.0.0-38-generic`, load it,
  re-run W1 to confirm the out-of-tree stock driver matches the in-tree
  baseline. This is the tree the patch lands in.
- Keep it a DKMS package so install/uninstall on the laptop is one command and
  fully reversible.
- Deliverable: clean-building DKMS package; Wi-Fi still works normally with it
  loaded.

### W3. The injection patch

The core work, built in reviewable steps, each re-running the W1 matrix.

1. **Queue routing.** In `iwl_mvm_mac_tx()`, detect injected frames with no
   associated station and route them to `snif_queue` (falling back to the aux
   queue) instead of dropping. Confirm frames now reach the firmware.
2. **Honour radiotap.** In `tx.c`, carry the injected skb's radiotap rate and
   flags into the `TX_CMD` so channel/rate are the caller's choice, not the
   association's.
3. **Stationless lifetime.** Ensure the sniffer station/queue is created when
   the monitor vif comes up and torn down cleanly, so injection works with no
   association at all. Set channel via the monitor iface and verify the
   firmware transmits on it.
4. **Safety switch.** Gate every behaviour change behind a module parameter,
   default off, so a bad build never breaks normal Wi-Fi on this daily driver.

Deliverable: injected frames, unassociated, captured on a second adapter, on at
least one band first, then both with a usable rate set.

### W4. Firmware limits (bounds the patch)

- Record which firmware API version the running `.ucode` negotiates; test
  whether another linux-firmware revision changes TX acceptance. Pin and record
  each combination (newer is not assumed better).
- Document any hard firmware refusals (frame types / rates / channels the
  firmware rejects regardless of driver). These are the ceiling on W3.
- Deliverable: firmware-version-to-behaviour note.

## Explicit non-goal

A USB adapter with an injection-friendly chipset (MT7612U, AR9271, RTL8812AU)
would make injection trivial. That is deliberately out of scope here: the goal
is the AX201 itself. Do not let it creep back in as "the pragmatic path".

## Milestones

- M1: W1 baseline captured and written up. DONE 2026-10-10 (see BASELINE.md):
  stock injection 0/30 (0%) on ch36, RX fine. This is the floor to beat.
- M2: iwlwifi (from linux-source-7.0.0, 7.0.0-38.38) builds out-of-tree and as
  a DKMS package; Wi-Fi still normal. DONE 2026-10-10: the DKMS build loads from
  `updates/dkms/`, firmware 77 negotiates cleanly, laptop stays usable.
  (Chose the distro kernel's own iwlwifi over backport-iwlwifi: it matches API
  77 and kernel 7.0 exactly.)
- M3: Queue-routing step (W3.1) lands behind the module param; injected frames
  reach the firmware. PROVEN by driver-side TX confirmation.
- M4: Unassociated injection works and is captured on a second adapter.
  PROVEN end to end by the independent capture, on both bands with a usable
  rate set.

## Guardrails

- Daily-driver laptop: every driver change is default-off and removable by
  uninstalling the DKMS package. Never ship something that can brick Wi-Fi.
- Heavy builds do not run on this laptop (overheats, little RAM). Build the
  DKMS module on the compute box over ssh (`ssh aeronav-llm`); install and test
  only the resulting package locally.
- All on-air transmission targets the operator's own APs and devices on a quiet
  channel. Keep a second owned AP as the injection target.

## Open questions for session 1

1. Exact firmware revision and TX API version loaded now (read from `dmesg`
   after a fresh `modprobe iwlwifi`).
2. Does the stock sniffer station already have a live queue when the monitor
   vif is up, or does it need to be forced up for stationless TX?
3. Which band to target first for M4 (2.4 GHz is usually the easier firmware
   path).
