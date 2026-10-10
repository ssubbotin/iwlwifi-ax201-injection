#!/usr/bin/env bash
# M3.1 diagnosis: find WHERE an injected frame dies on the stock-behaviour
# driver. The driver already routes monitor-vif non-sta frames to snif_queue
# (tx.c), so this answers: does an injected frame reach a hardware TX ring, or
# is it dropped in the driver first?
#
# Observation (no CONFIG_IWLWIFI_DEBUG in this build, so IWL_DEBUG_TX is out):
#   - ftrace iwlwifi_dev_tx        -> fires only when a frame hits a TX ring
#   - ftrace iwlwifi_dev_ucode_event -> firmware-side events
#   - dmesg "No queue was found"   -> driver drop (queue < 0)  [IWL_ERR, always on]
#   - dmesg WARNING / Microcode SW error -> bad queue id or firmware refusal
#
# Reuses the W1 monitor setup (single fixed channel) and restores Wi-Fi on exit.
set -uo pipefail

IFACE="wlp0s20f3"
CHANNEL=${CHANNEL:-36}
AP_BSSID=${AP_BSSID:-cc:d8:43:b2:dd:27}
TR=/sys/kernel/debug/tracing
MON=""
PREV_SSID=""

tlog() { echo "[$(date +%T)] $*"; }

PREV_SSID=$(iw dev "$IFACE" info 2>/dev/null | awk '/ssid/{print $2; exit}' || true)
tlog "pre-state SSID: ${PREV_SSID:-<none>}"

cleanup() {
    echo "--- restoring adapter ---"
    sudo sh -c "echo 0 > $TR/tracing_on" 2>/dev/null || true
    sudo sh -c "echo 0 > $TR/events/iwlwifi/enable" 2>/dev/null || true
    if [ -n "$MON" ] && ip link show "$MON" >/dev/null 2>&1; then
        timeout -k 5 15 sudo airmon-ng stop "$MON" >/dev/null 2>&1 || sudo ip link del "$MON" 2>/dev/null || true
    fi
    sudo ip link del wlp0s20f3mon 2>/dev/null || true
    sudo ip link set "$IFACE" up 2>/dev/null || true
    if [ -n "$PREV_SSID" ] && command -v nmcli >/dev/null 2>&1; then
        for a in 1 2 3; do
            timeout -k 5 20 nmcli device wifi connect "$PREV_SSID" >/dev/null 2>&1 && { tlog "reconnected '$PREV_SSID'"; break; }
            sleep 4
        done
    fi
    tlog "restore done"
}
trap cleanup EXIT INT TERM

sudo ip link del wlp0s20f3mon 2>/dev/null || true

tlog "starting monitor on $IFACE channel $CHANNEL"
sudo airmon-ng start "$IFACE" "$CHANNEL" >/dev/null 2>&1
sleep 2
MON=$(iw dev 2>/dev/null | awk '/Interface /{n=$2} /type monitor/{print n; exit}' || true)
[ -z "$MON" ] && { echo "ERROR: no monitor interface created"; exit 1; }
tlog "monitor interface: $MON"
iw dev "$MON" info 2>/dev/null | grep -E 'channel|type' | sed 's/^/      /'

# --- arm ftrace on the iwlwifi TX / ucode tracepoints ---
tlog "arming ftrace (iwlwifi_dev_tx, iwlwifi_dev_ucode_event)"
sudo sh -c "
  echo 0 > $TR/tracing_on
  echo nop > $TR/current_tracer
  echo > $TR/trace
  echo 1 > $TR/events/iwlwifi/iwlwifi_dev_tx/enable
  echo 1 > $TR/events/iwlwifi/iwlwifi_dev_ucode_event/enable
  echo 1 > $TR/tracing_on
"
DMESG_MARK="M3DIAG-$(date +%s)"
sudo sh -c "echo '$DMESG_MARK' > /dev/kmsg" 2>/dev/null || true

echo
echo "===== INJECTION: directed probe (-9 -a owned AP), 15s ====="
timeout 20 sudo aireplay-ng -9 -a "$AP_BSSID" "$MON" 2>&1 | sed 's/^/  /'

sudo sh -c "echo 0 > $TR/tracing_on"

echo
echo "===== ftrace result ====="
TXN=$(sudo grep -c 'iwlwifi_dev_tx' "$TR/trace" 2>/dev/null || echo 0)
UCN=$(sudo grep -c 'iwlwifi_dev_ucode_event' "$TR/trace" 2>/dev/null || echo 0)
echo "iwlwifi_dev_tx events during injection : $TXN"
echo "iwlwifi_dev_ucode_event events         : $UCN"
echo "--- sample of iwlwifi_dev_tx lines (up to 5) ---"
sudo grep 'iwlwifi_dev_tx' "$TR/trace" 2>/dev/null | head -5 | sed 's/^/  /' || true

echo
echo "===== dmesg since mark ($DMESG_MARK) ====="
sudo dmesg 2>/dev/null | awk "/$DMESG_MARK/{f=1} f" | \
    grep -iE 'iwlwifi|No queue|Microcode|WARNING|Call Trace|Dropping' | sed 's/^/  /' || echo "  (no relevant dmesg lines)"

echo
tlog "diagnosis complete"
