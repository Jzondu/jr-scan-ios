# JR Scan handoff — 2026-11-02

## Goal and constraints

Implement JR-Scan-Project-Brief.md autonomously. iPhone 16 Pro, Windows, no Mac, limited user time. Free local AltStore Classic signing, unsigned GitHub macOS CI builds. No Apple credentials in CI, paid services, cloud reconstruction runtime or library/design questions. Stable bundle ID fi.jzondu.jrscan; preserve same account/identity for updates. Batch physical tests and keep summaries concise.

## Current verified state

- Repository https://github.com/Jzondu/jr-scan-ios, main. Workspace C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner.
- User reports iOS 27.0. Build 3 installation initially reported “wrong format” but user then confirmed: “now it worked and opens.” Exact cause not established. Installability gate passed; capabilities, camera and persistence were not explicitly reported.
- Implemented guided ObjectCaptureSession/ObjectCaptureView with detection/bounds/feedback/coverage/multiple height passes, finish/cancel; durable per-scan inputs/checkpoints/manifests; on-device PhotogrammetrySession .reduced reconstruction with progress/errors/cancel/background interruption/restart; USDZ preview and sharing; Model I/O geometry OBJ export with transforms, winding, normals and meter/mm numerical scaling; export notes; local scan list/name/timestamps/delete confirmation; Files folder backup; plain-text diagnostics; device/persistence checks and sample notices.
- Apple sample actual LICENSE.txt checked and preserved verbatim in JRScan/Resources/Apple-ObjectCapture-LICENSE.txt, bundled and accessible in Notices. See README for source URL/hash/license. No blanket third-party license.
- Latest compiled source commit fb0c5c928247248ef120f98a7262df3df80da1f2, version 0.2.0 (6).
- SUCCESSFUL build 6: https://github.com/Jzondu/jr-scan-ios/actions/runs/41415198007
- IPA artifact: https://github.com/Jzondu/jr-scan-ios/actions/runs/41415198007/artifacts/13126618466 (JRScan-unsigned-6; extract outer ZIP).
- Local extracted IPA: build/downloads/run-6/JRScan.ipa. Logs in build/downloads/run-6/logs. Ignored from git, preserved locally.
- SHA-256 a372890da0a6976764a18b8f86aababfeb10b56e5c3f7f25d7d68fc6cbaf00cf independently matched CI.
- Xcode 16.4 (16F6), iOS SDK 18.5, minimum iOS 18, XcodeGen 2.44.1, runner macos15 20261028.0489.1.
- Synthetic macOS conversion tests PASS: nested transforms/nonuniform scale, reflected winding, inverse-transpose normals, nonempty triangle geometry, invalid-index rejection, 1000x units, actual USDZ import -> OBJ export using a deterministic aligned USDZ fixture. These are not physical sensor/reconstruction or iPhone conversion tests.
- Build 6 compiles/packages. Physical installation, actual capture/reconstruction/export, scale, backups and persistence remain unverified. No known-good scan build tag yet.
- Final source review fixed visible incomplete-stitching warnings, cancellation state and capture task cleanup. Do not broaden work while the physical scan gate is pending.

## Next user test (one batch)

Update in place to 0.2.0 (6), do not uninstall. Extract artifact ZIP, transfer JRScan.ipa to iPhone Files, install via AltStore Classic My Apps > + with AltServer reachable. Check old persistence marker survives if recorded, both capabilities Supported, allow Camera. Scan one matte textured object, finish/save, reconstruct while foreground, rotate/zoom preview, export same model in meters and mm, save all offered files externally, open in Blender/MeshLab on Windows, check geometry and 1000x coordinate dimensions. Force-close/reopen and confirm scan/model persistence. Save scan backup to Files if practical. If a step fails, obtain actual error and exported diagnostic text before requesting another complete scan.

Then fix observed failures and test interruption/cancellation/retry, next in-place update and refresh preservation. Tag known-good only after physical evidence. Textured OBJ deferred until geometry passes and user asks. README has build/install/scan/recovery instructions and evidence.

## Access / build

Portable CLI .tools/gh/bin/gh.exe has no separate stored login. Windows Git Credential Manager's cached credential authorized pushes, API and dispatch. Retrieve only into process-local GH_TOKEN without printing/logging/persisting it; never expose credential-fill output. Manual workflow build-ios.yml on main, 25-minute timeout, seven-day retention. macOS synthetic conversion tests do not make the cloud a runtime reconstruction server. No local Xcode.

## Latest investigation — reconstruction error 6

User supplied a screenshot with CoreOC.PhotogrammetrySession.Error error 6. This confirms build 6 reached reconstruction on device and failed, not a successful model/OBJ. Scan ID in screenshot is 0A1B2034-37E7-4915-BF64-F6A9404F9F2E. Requested Share diagnostic text asynchronously; no log received yet. Root cause is UNKNOWN; do not map numeric code 6 definitively to alignment/memory/masks. Apple engineer in https://developer.apple.com/forums/thread/827696 suggests an images-without-masks check for a similar case, not proof of this cause.

Implemented version 0.2.1: optional failed/interrupted/cancelled scan retry without masking AND checkpoint reuse, preserving original saved images/checkpoints/output history. Default guided mode unchanged. Shows warning about possible background geometry. Adds persisted reconstruction mode, last processing stage, typed/simple Swift error case, NSError domain/code/underlying chain, capture finish flag/input count/disk in diagnostics. New fields optional for old manifests. No arbitrary error userInfo dump. Tests verify selected diagnostic fields without payload leakage, alongside existing geometry checks.

Latest source: 1667d713b939466a4d359a2da6dc109d6c20baf5, version 0.2.1 (9).
SUCCESSFUL run: https://github.com/Jzondu/jr-scan-ios/actions/runs/41418316114
Artifact JRScan-unsigned-9: https://github.com/Jzondu/jr-scan-ios/actions/runs/41418316114/artifacts/13127953700
Local IPA build/downloads/run-9/JRScan.ipa, logs build/downloads/run-9/logs.
SHA-256 0c84ac6d686a728b9f94952acd0d7501d9f1c4fae68fc2ce1b425f4a815b1290 independently matched CI.
Runner standard macos-15-intel, X64, image macos15 20260824.0482.1; Xcode16.4 (16F6), SDK18.5, XcodeGen2.44.1.
Runs7–8 were superseded/cancelled while ARM capacity was queued. Workflow now has a choice of standard macos-15 (default) or macos-15-intel; records runner architecture. No paid runners. No runtime reconstruction on the build Mac.

Next: install build9 IN PLACE (same identity/account), open existing failed scan, Retry without object masking / checkpoints, foreground. Do NOT request a fresh capture first. If failure, obtain new diagnostic text and analyze actual stage/type/details. If success, inspect background geometry, preview/OBJ and scale, then remaining physical acceptance tests. No claim fallback is proven or error6 resolved. README updated to this recovery-first test. Earlier build6 artifact links in this handoff are historical.
