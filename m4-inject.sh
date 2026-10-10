#!/usr/bin/env bash
# M4: inject uniquely-tagged probe requests (TA 02:de:ad:be:ef:01, SSID
# INJTEST-M4) on a dedicated ch9 monitor so an independent radio can capture
# them. Restores + settles Wi-Fi before returning.
set -uo pipefail
IFACE=wlp0s20f3; CH=9; MON=""; PREV_SSID=""; INJ="$(cd "$(dirname "$0")" && pwd)/tools/inject.py"
tlog(){ echo "[$(date +%T)] $*"; }
PREV_SSID=$(iw dev "$IFACE" info 2>/dev/null | awk '/ssid/{print $2;exit}' || true)
cleanup(){
  echo "--- restoring ---"
  [ -n "$MON" ] && timeout -k5 15 sudo airmon-ng stop "$MON" >/dev/null 2>&1 || true
  sudo ip link del wlp0s20f3mon 2>/dev/null || true
  sudo ip link set "$IFACE" up 2>/dev/null || true
  [ -n "$PREV_SSID" ] && for a in 1 2 3; do timeout -k5 20 nmcli device wifi connect "$PREV_SSID" >/dev/null 2>&1 && break; sleep 4; done
  for i in $(seq 1 8); do ip route get 1.1.1.1 >/dev/null 2>&1 && getent hosts api.anthropic.com >/dev/null 2>&1 && { tlog "link settled (try $i)"; break; }; sleep 2; done
  tlog "restore done"
}
trap cleanup EXIT INT TERM
sudo ip link del wlp0s20f3mon 2>/dev/null || true
tlog "monitor on $IFACE ch$CH"
sudo airmon-ng start "$IFACE" "$CH" >/dev/null 2>&1; sleep 2
MON=$(iw dev 2>/dev/null | awk '/Interface /{n=$2} /type monitor/{print n;exit}')
[ -z "$MON" ] && { echo "no monitor"; exit 1; }
tlog "monitor $MON; injecting 120 INJTEST-M4 probes over ~25s"
sudo python3 -I "$INJ" "$MON" m4 120
tlog "injection done"
