# M3.1 diagnosis: where injected frames actually die

Measured 2026-10-10 on the instrumented driver (this repo), AX201, kernel
7.0.0-38-generic, firmware `QuZ-a0-hr-b0-77.ucode` (API 77).

## Result: the KICKOFF root cause was wrong

Injected frames do **not** reach iwlwifi at all. They are dropped inside
**mac80211**, before the driver's `.tx` op runs. The `snif_sta` / `snif_queue`
/ `tx.c` queue-routing theory in KICKOFF cannot be the fix, because `tx.c`
never executes for these frames.

## Evidence

The driver was instrumented with a runtime param `iwlmvm.inject_dbg` that logs
every injected-frame (`IEEE80211_TX_CTL_INJECTED`) decision in
`iwl_mvm_mac_tx()` and the common chokepoint `iwl_mvm_tx_skb()`. ftrace was
armed on `iwlwifi_dev_tx` (fires only when a frame hits a hardware TX ring) and
`iwlwifi_dev_ucode_event`.

Running `aireplay-ng -9` on a ch36 monitor (`m3-diagnose-inject.sh`), with
`inject_dbg=1`:

- `inject:` driver logs fired: **0**
- `iwlwifi_dev_tx` ring events: **0**
- `iwlwifi_dev_ucode_event`: **0**
- `"No queue was found. Dropping TX"` (IWL_ERR, always compiled): **absent**
- WARNING / microcode error: **absent**

Nothing in the driver was reached. The frame was dropped upstream.

## The drop site, in mac80211

`net/mac80211/tx.c`, `ieee80211_monitor_start_xmit()` (kernel 7.0.0-38):

```c
if (chanctx_conf)                chandef = &chanctx_conf->def;
else if (local->emulate_chanctx) chandef = &local->hw.conf.chandef;
else                             goto fail_rcu;

if (!cfg80211_chandef_usable(hw.wiphy, chandef, IEEE80211_CHAN_DISABLED))
    goto fail_rcu;
if (!cfg80211_reg_can_beacon(hw.wiphy, chandef, sdata->vif.type))
    goto fail_rcu;     /* <-- injected frame freed here */
```

iwlwifi is a full channel-context driver (`emulate_chanctx == false`), so an
injected frame survives only if its channel permits initiating radiation.

## Why ch36 fails: regulatory `No IR`

`iw` on this machine:

- `phy0` is **self-managed**, regdomain **country CN** (from the firmware NVM).
- **Channel 36 (5180 MHz) is flagged `No IR`** (No Initiating Radiation), plus
  `IR-CONCURRENT` (TX permitted only while concurrently associated).
- 2.4 GHz channels (1, 6, ...) carry **no** `No IR` flag.

So `cfg80211_reg_can_beacon()` returns false on ch36 and mac80211 drops every
injected frame. This also explains the two hints in KICKOFF: 2.4 GHz is the
easier path (no `No IR`), and injection works while associated (`IR-CONCURRENT`
lifts the restriction).

Because the phy is self-managed, userspace `iw reg set` cannot change this; the
`No IR` flag is set by **iwlwifi itself**.

## Where iwlwifi sets `No IR` (the fix target)

`drivers/net/wireless/intel/iwlwifi/iwl-nvm-parse.c`:

- channel flags: lines 295-299, `flags |= IEEE80211_CHAN_NO_IR` when the NVM
  channel lacks the `IBSS` / `ACTIVE` bits. This flag is what
  `cfg80211_reg_can_beacon()` checks.
- regdomain rules: line 1551, `flags |= NL80211_RRF_NO_IR`.

## Planned fix (W3)

Add an `iwlwifi.inject` module parameter, default off (the W3.4 safety switch).
When set, do not apply `NO_IR` while building the channel list, so mac80211
permits injection on any channel including ch36. The parameter lives in the core
`iwlwifi` module (`iwl_mod_params`) so both `iwl-nvm-parse.c` and the mvm opmode
can read it. Regulatory tables are derived at NVM init, so the parameter is read
at module load; changing it takes effect on the next driver reload.

## Confirmation on 2.4 GHz (ch9, no No-IR) — 2026-10-10

Re-ran the traced injection on channel 9 against the owned 2.4 GHz AP
`cc:d8:43:b2:dd:26` (`CHANNEL=9 AP_BSSID=... m3-diagnose-inject.sh`), same
instrumented-but-behaviorally-stock driver. Unlike ch36:

- aireplay reported **"Injection is working!"**.
- `iwlwifi_dev_tx` ring events: **11** (vs 0 on ch36) — frames reached hardware.
- `inject: mac_tx ... viftype=6 (MONITOR) sta=NULL offchan=0` logs fired: frames
  now reach iwlwifi and take the non-sta monitor path to `snif_queue`.

This proves the regulatory `No IR` flag is the sole reason ch36 fails, and that
the AX201 can inject on an IR-allowed channel.

### Second problem, now exposed: firmware instability on the sniffer queue

After the first ~11 frames, the firmware crashed:

```
iwlwifi 0000:00:14.3: Microcode SW error detected. Restarting 0x0.
Transport status: 0x0000004A
Loaded firmware version: 77.f39cc7f9.0 QuZ-a0-hr-b0-77.ucode
```

`iwl_mvm_tx_skb()` then logged **119** `tx_skb DROP (free_txskb)` for the
remaining frames (while the firmware was in error/restart), and the directed
phase read 0/30. The adapter auto-restarted and reconnected; no lasting harm.

So reliable injection needs two things, in order:

1. **Regulatory**: withhold `NO_IR` so mac80211 permits injection on any channel
   (the `iwlwifi.inject` patch). Primary; unblocks 5 GHz.
2. **Firmware/TX params**: the sniffer-queue injection path destabilises the
   microcode after a few frames. Likely the injected frames carry a rate or
   TX_CMD format the firmware rejects. This is the W3.2 (honour radiotap rate)
   and W4 (firmware limits) work.

## M3.3: isolated and fixed the firmware assert — 2026-10-10

With `iwlwifi.inject=1`, a controlled single-frame-type injector (one 802.11
type per batch, on a dedicated ch36 monitor) isolated the assert cleanly:

```
probe : ring_delta=15  assert=0
auth  : ring_delta=15  assert=0
data  : ring_delta=15  assert=0
rts   : ring_delta=2    assert=1   <- ADVANCED_SYSASSERT 0x4217
```

The firmware asserts only on **raw control frames** (RTS, `fc=0x00b4`) injected
on the stationless sniffer context. Management, authentication and data frames
inject fine, 15 of 15 to the TX ring, no assert. aireplay-ng `-9` crashed the
firmware only because its test sequence includes control frames.

Fix (in `iwl_mvm_tx_skb_non_sta`, inject mode only): drop injected control
frames before they reach the firmware. After the fix the `rts` batch is dropped
cleanly (`ring_delta=0 assert=0`) while probe/auth/data still inject 15/15.

Net result: management and data frame injection works on the AX201,
unassociated, on ch36, without destabilising the firmware. Control-frame
injection is intentionally not supported (the firmware rejects it; the firmware
generates its own control frames anyway).

Harnesses: `m3-isolate.sh` (per-type isolation) with a stdlib radiotap injector.
