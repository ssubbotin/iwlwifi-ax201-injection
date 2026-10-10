#!/usr/bin/env bash
# W2: fully remove the DKMS package and restore the stock in-tree iwlwifi.
set -euo pipefail

PKG="iwlwifi-ax201-inject"
VER="0.1"

echo "== dkms remove =="
sudo dkms remove -m "$PKG" -v "$VER" --all 2>/dev/null || true
sudo rm -rf "/usr/src/${PKG}-${VER}"

# Drop any leftover modules from the updates/ dir and refresh deps.
sudo rm -f "/lib/modules/$(uname -r)/updates/iwlwifi.ko"* \
          "/lib/modules/$(uname -r)/updates/mvm/iwlmvm.ko"* \
          "/lib/modules/$(uname -r)/updates/mld/iwlmld.ko"* \
          "/lib/modules/$(uname -r)/updates/dvm/iwldvm.ko"* 2>/dev/null || true
sudo depmod -a

echo "== done. Stock driver restored. Reload with: =="
echo "sudo modprobe -r iwlmvm iwlwifi && sudo modprobe iwlwifi"
echo "Confirm: modinfo -n iwlwifi   (should point under kernel/, not updates/)"
