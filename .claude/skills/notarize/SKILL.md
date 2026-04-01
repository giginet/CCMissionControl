---
name: notarize
description: Build, sign, and notarize the macOS app with Developer ID
disable-model-invocation: true
allowed-tools: Bash
---

# Notarize CCMissionControl

Run the notarize script to archive, export with Developer ID signing, submit for notarization, and staple.

## Steps

1. Run `./scripts/notarize.sh` from the project root
2. Wait for notarization to complete (the script uses `--wait`)
3. Report the result to the user
