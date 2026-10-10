#!/usr/bin/env bash
# W1 baseline: measure stock iwlwifi injection on the AX201.
# Mirrors the proven monitor setup from ~/wifi-deauth-test.sh (airmon-ng
# start, single channel to avoid the firmware wedge), then runs the
# aireplay-ng -9 injection test. Restores the adapter and reconnects on exit.
# Target AP (owned): Abracadabra, channel 36 (5180 MHz).
set -uo pipefail

IFACE="wlp0s20f3"
CHANNEL=36
AP_BSSID="cc:d8:43:b2:dd:27"
MON=""
PREV_SSID=""

tlog() { echo "[$(date +%T)] $*"; }

PREV_SSID=$(iw dev "$IFACE" info 2>/dev/null | awk '/ssid/{print $2; exit}' || true)
tlog "pre-state SSID: ${PREV_SSID:-<none>}"

cleanup() {
    echo "--- restoring adapter ---"
    if [ -n "$MON" ] && ip link show "$MON" >/dev/null 2>&1; then
        timeout -k 5 15 airmon-ng stop "$MON" >/dev/null 2>&1 || ip link del "$MON" 2>/dev/null || true
    fi
    # kill any stale concurrent monitor vif too
    ip link del wlp0s20f3mon 2>/dev/null || true
    ip link set "$IFACE" up 2>/dev/null || true
    if [ -n "$PREV_SSID" ] && command -v nmcli >/dev/null 2>&1; then
        for a in 1 2; do
            timeout -k 5 15 nmcli device wifi connect "$PREV_SSID" >/dev/null 2>&1 && { tlog "reconnected '$PREV_SSID'"; break; }
            [ "$a" = 1 ] && sleep 5
        done
    fi
    tlog "restore done"
}
trap cleanup EXIT INT TERM

# Remove the stale concurrent monitor vif before airmon-ng, so detection is clean.
ip link del wlp0s20f3mon 2>/dev/null || true

tlog "starting monitor on $IFACE channel $CHANNEL"
airmon-ng start "$IFACE" "$CHANNEL" >/dev/null 2>&1
sleep 2   # let the monitor vif register before we probe for it
MON=$(iw dev 2>/dev/null | awk '/Interface /{n=$2} /type monitor/{print n; exit}' || true)
if [ -z "$MON" ]; then echo "ERROR: no monitor interface created"; exit 1; fi
tlog "monitor interface: $MON"
iw dev "$MON" info 2>/dev/null | grep -E 'channel|type' | sed 's/^/      /'

echo
echo "===== RX sanity: 6s beacon capture ====="
timeout 6 tcpdump -i "$MON" -nn -c 8 "type mgt subtype beacon" 2>/dev/null | grep -c Beacon | sed 's/^/beacons seen (approx frames): /' || true
timeout 4 tcpdump -i "$MON" -nn -c 5 2>/dev/null | wc -l | sed 's/^/any frames in 4s: /'

echo
echo "===== INJECTION TEST 1: broadcast (-9) ====="
timeout 30 aireplay-ng -9 "$MON" 2>&1 | sed 's/^/  /'

echo
echo "===== INJECTION TEST 2: directed (-9 -a owned AP) ====="
timeout 30 aireplay-ng -9 -a "$AP_BSSID" "$MON" 2>&1 | sed 's/^/  /'

echo
tlog "tests complete"
