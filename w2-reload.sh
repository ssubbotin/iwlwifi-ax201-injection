#!/usr/bin/env bash
# W2: reload the iwlwifi stack in ONE self-contained run and wait for Wi-Fi to
# come back before returning. Reloading drops the connection, and over Wi-Fi
# that also drops any remote control of this machine, so this script must never
# leave the radio unloaded: the load step always runs and we poll for reconnect.
#
# NB: /etc/modprobe.d/iwlwifi.conf installs a custom `remove iwlwifi` rule that
# tears down iwlmvm/iwldvm/iwlwifi/mac80211 together. So remove iwlwifi ALONE;
# do not also name iwlmvm or the rule's `xargs rmmod` gets empty input.
set -u
ARG="${1:-}"   # optional: module params passed to modprobe, e.g. inject_mon=1

echo "== removing iwlwifi (custom conf rule tears down the whole stack) =="
sudo modprobe -r iwlwifi || true
sleep 1
echo "== loading iwlwifi ${ARG} =="
sudo modprobe iwlwifi ${ARG}

echo "== waiting for wlp0s20f3 to reconnect (up to 40s) =="
ok=0
for i in $(seq 1 20); do
  st=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | sed -n 's/^wlp0s20f3://p')
  if [[ "$st" == "connected" ]] && ip route get 1.1.1.1 >/dev/null 2>&1; then ok=1; break; fi
  sleep 2
done
echo "device state: $(nmcli -t -f DEVICE,STATE device 2>/dev/null | sed -n 's/^wlp0s20f3://p')"
echo "loaded: $(modinfo -n iwlwifi 2>/dev/null)"
lsmod | grep -E '^iwl'
if [[ $ok == 1 ]]; then echo "OK: reconnected, internet reachable"; else
  echo "WARN: not reconnected after 40s"; fi
