#!/usr/bin/env bash
# M3.2 isolation: on a dedicated monitor, inject separated batches of one frame
# type at a time (probe/auth/data/rts) to find which triggers firmware assert
# 0x4217. Reuses W1 monitor setup; restores Wi-Fi AND settles the link + API
# reachability before returning, so the caller is not left on a flapping link.
set -uo pipefail
IFACE="wlp0s20f3"; CHANNEL="${CHANNEL:-36}"; MON=""; PREV_SSID=""
INJ="/tmp/claude-1000/-home-sergey-iwlwifi-injection/870dd89e-a683-415c-aacc-743bc3272d2c/scratchpad/inject.py"
TR=/sys/kernel/debug/tracing
tlog(){ echo "[$(date +%T)] $*"; }
PREV_SSID=$(iw dev "$IFACE" info 2>/dev/null | awk '/ssid/{print $2;exit}' || true)
cleanup(){
  echo "--- restoring ---"
  sudo bash -c "echo 0 > $TR/tracing_on; echo 0 > $TR/events/iwlwifi/enable" 2>/dev/null || true
  [ -n "$MON" ] && timeout -k5 15 sudo airmon-ng stop "$MON" >/dev/null 2>&1 || true
  sudo ip link del wlp0s20f3mon 2>/dev/null || true
  sudo ip link set "$IFACE" up 2>/dev/null || true
  [ -n "$PREV_SSID" ] && for a in 1 2 3; do timeout -k5 20 nmcli device wifi connect "$PREV_SSID" >/dev/null 2>&1 && break; sleep 4; done
  # settle: confirm internet stable several times before returning
  for i in $(seq 1 8); do ip route get 1.1.1.1 >/dev/null 2>&1 && getent hosts api.anthropic.com >/dev/null 2>&1 && { tlog "link settled (try $i)"; break; }; sleep 2; done
  tlog "restore done"
}
trap cleanup EXIT INT TERM
sudo ip link del wlp0s20f3mon 2>/dev/null || true
tlog "monitor on $IFACE ch$CHANNEL"
sudo airmon-ng start "$IFACE" "$CHANNEL" >/dev/null 2>&1; sleep 2
MON=$(iw dev 2>/dev/null | awk '/Interface /{n=$2} /type monitor/{print n;exit}')
[ -z "$MON" ] && { echo "no monitor"; exit 1; }
tlog "monitor: $MON"
sudo bash -c "echo 1 > /sys/module/iwlmvm/parameters/inject_dbg"
sudo bash -c "echo 0 > $TR/tracing_on; : > $TR/trace; echo 1 > $TR/events/iwlwifi/iwlwifi_dev_tx/enable; echo 1 > $TR/tracing_on"
for t in probe auth data rts; do
  M="ISO-$t-$(date +%s)"; sudo bash -c "echo '$M' > /dev/kmsg"
  before=$(sudo grep -c iwlwifi_dev_tx $TR/trace); before=${before:-0}
  sudo python3 -I "$INJ" "$MON" "$t" 15 >/dev/null 2>&1
  sleep 1
  after=$(sudo grep -c iwlwifi_dev_tx $TR/trace); after=${after:-0}
  asrt=$(sudo dmesg | awk "/$M/{f=1} f" | grep -c 'Microcode SW error'); asrt=${asrt:-0}
  printf "  %-6s: ring_delta=%s assert=%s\n" "$t" "$((after-before))" "$asrt"
  sleep 2   # let any firmware restart finish before next type
done
tlog "isolation done"
