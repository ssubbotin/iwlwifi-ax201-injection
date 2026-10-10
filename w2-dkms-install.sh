#!/usr/bin/env bash
# W2: register, build and install the iwlwifi modules as a DKMS package.
# Reversible with ./w2-dkms-remove.sh. Installs into /lib/modules/<ver>/updates/
# which modprobe prefers over the stock in-tree modules.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
PKG="iwlwifi-ax201-inject"
VER="0.1"
SRC="$REPO/src/drivers/net/wireless/intel/iwlwifi"
DST="/usr/src/${PKG}-${VER}"

if [[ ! -d "$SRC" ]]; then echo "source tree not found: $SRC" >&2; exit 1; fi

echo "== staging source into $DST =="
sudo rm -rf "$DST"
sudo mkdir -p "$DST"
sudo cp -a "$SRC"/. "$DST"/
sudo cp "$REPO/packaging/dkms.conf" "$DST/dkms.conf"
# strip any stray build artifacts from the staged copy
sudo find "$DST" \( -name '*.o' -o -name '*.ko' -o -name '*.cmd' \
  -o -name '*.mod' -o -name '*.mod.c' -o -name 'modules.order' \
  -o -name 'Module.symvers' \) -delete 2>/dev/null || true

echo "== dkms add/build/install =="
sudo dkms remove -m "$PKG" -v "$VER" --all 2>/dev/null || true
sudo dkms add "$DST"
sudo dkms build -m "$PKG" -v "$VER"
sudo dkms install -m "$PKG" -v "$VER" --force

echo "== status =="
dkms status "$PKG/$VER"
echo "Installed modules:"
ls -1 "/lib/modules/$(uname -r)/updates/" 2>/dev/null | grep -E 'iwl' || true
echo
echo "Reload with:  sudo modprobe -r iwlmvm iwlwifi && sudo modprobe iwlwifi"
echo "Then confirm: modinfo -n iwlwifi   (should point under /updates/)"
