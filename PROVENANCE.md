# Source provenance

The `src/drivers/net/wireless/intel/iwlwifi/` subtree is a verbatim copy of the
Intel `iwlwifi` driver extracted from the Ubuntu kernel source package:

- Package: `linux-source-7.0.0`
- Version: `7.0.0-38.38`
- Path in archive: `linux-source-7.0.0/drivers/net/wireless/intel/iwlwifi/`
- Target kernel on the development machine: `7.0.0-38-generic`
- Adapter: Intel Wi-Fi 6 AX201 (`8086:a0f0`), `mvm` opmode
- Firmware in use: `QuZ-a0-hr-b0-77.ucode` (API 77)

The driver is licensed GPL-2.0 (see SPDX headers in each file). This repository
redistributes it under the same licence together with the modifications made in
later commits.

The base commit contains the pristine upstream source with no modifications, so
that every change in this repository is visible as a diff against it.
