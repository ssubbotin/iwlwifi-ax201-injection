#!/usr/bin/env bash
# W2: quick out-of-tree build of the iwlwifi modules against the running
# kernel's headers, for fast iteration during patch development. Does NOT
# install anything (use w2-dkms-install.sh for that). Modest -j to keep this
# laptop cool.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
M="$REPO/src/drivers/net/wireless/intel/iwlwifi"
B="/lib/modules/$(uname -r)/build"
JOBS="${JOBS:-2}"

[[ -d "$B" ]] || { echo "kernel headers not found: $B" >&2; exit 1; }

echo "== building iwlwifi (-j$JOBS) against $B =="
make -C "$B" M="$M" -j"$JOBS" modules
echo
echo "== built modules =="
find "$M" -name '*.ko' | sed "s|$M/|  |"
echo
echo "vermagic: $(modinfo "$M/mvm/iwlmvm.ko" 2>/dev/null | awk '/^vermagic/{ $1=""; print }')"
echo "running : $(uname -r) ..."
