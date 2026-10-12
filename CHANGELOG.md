# Changelog

All notable changes to Aman Check are documented here.

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
