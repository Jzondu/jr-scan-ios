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
