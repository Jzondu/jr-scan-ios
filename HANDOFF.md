# JR Scan handoff — 2026-11-02

## Current state

- Workspace: C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner
- Public repository: https://github.com/Jzondu/jr-scan-ios, branch main.
- Brief: JR-Scan-Project-Brief.md. Milestones 0–1 source implemented. Scanning must wait for user-confirmed installability.
- Stable bundle ID fi.jzondu.jrscan; minimum iOS 18.0. Never change identity for updates.
- Build 3 SUCCEEDED: https://github.com/Jzondu/jr-scan-ios/actions/runs/41410289930
- Built source commit 15a3ef248d1e30eb7c2b5eb5a16cb21ac99baf27, version 0.1.0 (3).
- Xcode 16.4 (16F6), SDK 18.5, XcodeGen 2.44.1; runner macos15 20261028.0489.1.
- Artifact JRScan-unsigned-3: https://github.com/Jzondu/jr-scan-ios/actions/runs/41410289930/artifacts/13124857814
- Extracted local IPA: build/downloads/run-3/JRScan.ipa (ignored, preserved locally).
- IPA SHA-256 e988d09bbb16777d38394dc894c882ff47a29300b99af21b1688f86118ffebaf independently matched downloaded file. CI checked iphoneos/arm64 and ZIP integrity; Windows checked Payload/JRScan.app and nonempty executable.
- Earlier failures fixed in meaningful commits: SwiftUI.Scene ambiguity and lipo argument order.
- Physical installation, camera, capabilities, persistence/update tests are NOT verified. No scan/reconstruction code yet; do not imply these tests passed.

## Next step: one human installation batch

User must use AltStore Classic/AltServer locally (never Apple credentials in CI/chat). Download artifact, extract outer ZIP, transfer JRScan.ipa to phone Files, AltStore My Apps > +. Follow README and official Windows guide. Report exact iOS version, whether AltStore/JR Scan opens, both capability rows, camera permission, and persistence ID/count after force-close/relaunch. No response to earlier OS/AltStore questions yet. Refresh before free signing expiry; do not uninstall for updates.

After confirmation implement guided Object Capture -> durable inputs -> on-device PhotogrammetrySession .reduced -> preview -> actual triangle OBJ with transforms and meter/mm coordinates. Then remaining essentials from brief. Check actual Apple sample source license before reuse. No cloud runtime reconstruction, paid services, Apple credentials in CI, or scope expansion while device gate is pending.

## Access / build operations

Git transport authentication works through Windows Git Credential Manager. Portable CLI at .tools/gh/bin/gh.exe has no separate stored login, but saved Git credential successfully authorized API calls and workflow dispatch. Retrieve it only into a process-local GH_TOKEN without printing, logging or writing the secret. Do not expose credential-fill output. Workflow is manually triggered; no automatic build for documentation-only commits. Artifact retention seven days; local IPA preserved.

User wants autonomous meaningful commits, README maintenance, concise summaries and batched human-only work. No Mac available locally.
