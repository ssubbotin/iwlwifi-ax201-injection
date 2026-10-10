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
