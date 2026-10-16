# Changelog

All notable changes to Aman Check are documented here.

## Unreleased

### Sensors
- New "Sensors" section: number of fans, current fan speed and processor temperature, read from the SMC (read only, no password). Fanless Macs show "No fan on this model". A fan the model should have but the Mac does not report is "to watch"; a high temperature at rest is never more than "to watch".
- New guided tests: lid sensor (sleep and wake detected automatically, or the person answers; adapted when an external display is connected), ambient light sensor (screen brightness measured on Intel Macs, otherwise the person answers; "automatic brightness off" is "not tested", not a failure), keyboard backlight.
- Not yet verified on Apple silicon (see `docs/VERIFICATION.md`).

### Trust and first launch
- First launch: a short notice says what Aman Check does and doesn't do (reads only, no connection, no password, no Apple Account needed). "Got It" hides it for good.
- The "Apple Account signed in" line now says that the app itself needs no account: it checks whether the seller's account is still linked to the Mac.
- Website: a trust line under the download button, an "Is it safe?" section with the Gatekeeper steps, a FAQ, and a French version.
- Notarization ready but not active (no Apple Developer ID yet): `scripts/notarize.sh`, `scripts/make-dmg.sh --notarize`, release process in `docs/RELEASE.md`. Releases stay signed ad hoc by default.

### Compatibility
- Runs on macOS 13 Ventura (was macOS 14). New Macs covered: MacBook Pro 2017, MacBook 2017 and iMac 2017, whose last macOS is Ventura.
- On macOS 14 and later nothing changes. On macOS 13 the Touch ID and speaker symbols do not animate.
- Not yet verified on a real Mac running macOS 13.
- The README and the website still say macOS 14 until this version is released.

## 1.0.1 — 2026-10-12

Corrections from a full review. The report says less when it knows less: nothing turns green without proof.

### Verdicts
- A component the model should have (battery, built-in camera, Touch ID) but the Mac does not report is a problem, not "absent".
- Apple Account: "no account signed in" is never green without proof.
- MDM: "no signal" is neutral information, not a strength.
- Battery: the macOS cross-check never downgrades a problem; unknown rated cycles are information.
- Storage: describes the drive that holds the boot volume; an unknown engine status leaves no storage line green.
- Serial number: the text says the last 4 characters rule out an obvious mix-up, nothing more.
- Latest macOS: compared with the running version; counted as a strength only while the app is less than 18 months old.

### Privacy
- MDM and SIP results store a normalized value, never the command output.
- Audio tests record the device category, never its name; an external device means "not tested".

### Online report (level 2)
- Publishing is hidden in this version until the real domain is set.
- The published report promises only what the server checks; the pre-send check has no more false positives.

### Guided tests
- Ports: no green with a partial test; hubs do not count.
- Keyboard: JIS layout, reset when an external keyboard is used, no Escape key on Macs without one, missing keys are a problem.
- Camera: the negative answer is always available, a notice after 8 seconds without image, built-in cameras only.
- Screen and Touch ID tests only on Macs with a built-in display.
- Guided tests done before the first analysis are kept and attached to it.

### Small fixes
- Timestamps carry the time zone; a saved JSON is never overwritten; English permission texts translated into the 17 other languages; real build number and date; menu item "Aman Check on GitHub (source code)…" translated.
- Shared engine updated with the Aman Disk 1.0.1 fixes.

## 1.0.0 — 2026-10-12

First public release.

### Condition report (level 1, local)
- Automatic analysis: Activation Lock, Apple Account signed in (count and Find My only, never the e-mail), MDM enrollment, firmware password, SIP, FileVault, virtual machine detection, configuration profiles, security chip.
- Battery: charge cycles, current full-charge capacity vs. original capacity, condition reported by macOS, power source, temperature.
- Storage: S.M.A.R.T. health, SSD power-on hours, data written, wear, spare capacity, data errors, temperature, model and interface, using the Aman Disk engine.
- Configuration: model, model identifier and release year, processor and cores, graphics, memory, storage, display, installed and latest supported macOS, Wi‑Fi and Bluetooth.
- Guided tests: display, keyboard (ANSI/ISO auto-detection), Touch Bar, trackpad, speakers, microphone, camera, Touch ID, ports (USB ports, charging, video output, headphone jack, SD card reader).
- Report: PDF (A4) and JSON export, diagnostic log export. Counters only, no global score; provenance shown on every line; serial number limited to its last 4 characters.
- Interface in 18 languages (English and French in code, 16 others from `scripts/translations/`), right-to-left layout for Arabic.
- Design tokens and components shared with Aman Disk.

### Verifiable online report (level 2)
- Optional publication of a report to a server, with a public page, a QR code in the PDF and an A5 shop sheet.
- Nothing is sent without an explicit click; the full serial number never leaves the Mac.
- `server/`: Cloudflare Workers + Hono + D1, Ed25519 signatures, licence keys, payment webhook. Not deployed yet (domain not chosen).
