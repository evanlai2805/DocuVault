---
name: run-device
description: Build DocuVault for Evan's connected iPhone, install it, and launch it. Use when he asks to run, install, deploy, or try a change on the phone.
allowed-tools: Bash Read Grep
---
Run `scripts/run-device.sh` from the repo root.

Preconditions it checks for you:
1. `.env.local` holds `DOCUVAULT_TEAM_ID`. If missing, ask Evan for his Apple Team ID
   (Xcode → Settings → Accounts → his team → Team ID) and write the file yourself:
   `echo 'DOCUVAULT_TEAM_ID=XXXXXXXXXX' > .env.local`. Never commit it.
2. An iPhone is paired and reachable (cable or same Wi-Fi), unlocked, Developer Mode on.

Read the result:
- `DEVICE RUN: LAUNCHED` → tell Evan the app is on the phone and what to test, in one or two lines.
- Build fails → first `error:` line in `build/device.log`; signing errors mean the Team ID is wrong or
  the device is not registered — `-allowProvisioningUpdates` normally fixes registration on first run.
- "No paired iPhone found" → ask him to plug in, unlock, and tap Trust.
- The keyboard extension ships inside the app. iOS caches keyboards: switch keyboards with the globe key
  and back if the old one still shows.

Do not use `xcodebuild … -destination 'platform=iOS,name=…' run`; install + launch via devicectl is the path that works headless.
