# JR Scan

Personal iPhone 16 Pro object scanner. Specification: [JR-Scan-Project-Brief.md](JR-Scan-Project-Brief.md).

## Current gate

Milestones 0–1 source is implemented: a native SwiftUI install check, camera permission handling, Object Capture/reconstruction capability checks, app/build/OS information, and a durable local marker. **Compilation and physical installation are unverified until recorded below.** There is no scanning UI yet. Milestones 2–3 start only after installation is confirmed. The cloud Mac builds the app; later reconstruction runs on the iPhone, offline.

Stable application identity: **`fi.jzondu.jrscan`**. Minimum OS: **iOS 18.0**. Do not change the bundle ID for updates. Use the same local signing account and install in place; preserve important files externally. AltStore may rewrite the signed identity for your account; update persistence still needs a physical test.

## Build without a Mac

1. Open [Actions → Build unsigned iPhone IPA](https://github.com/Jzondu/jr-scan-ios/actions/workflows/build-ios.yml).
2. Select **Run workflow → main → Run workflow**. No secrets or Apple credentials are needed. Only manual runs are enabled to avoid repeated compute usage.
3. After the run succeeds, download **JRScan-unsigned-N** under Artifacts. **Extract the outer GitHub artifact ZIP on Windows** to obtain **JRScan.ipa** and `build-info.txt`. Do not select the outer ZIP in AltStore. Downloads expire after seven days; keep a known-good IPA locally.
4. If a run fails, download **JRScan-build-logs-N** or inspect its build step. A successful cloud build does not establish installability or sensor access.

The standard `macos-15` runner uses its installed default stable Xcode; no unsupported hard-coded Xcode application path. The script rejects SDKs older than iOS 18 and records Xcode, SDK, runner image, XcodeGen version, commit, build number and IPA SHA-256. Runner defaults can change; use the recorded versions when reproducing a particular build. If the phone OS is newer than the build SDK, investigate with the exact OS/SDK pair before claiming compatibility.

Project configuration is source-controlled in `project.yml`; XcodeGen **2.44.1** is downloaded with SHA-256 verification. It creates `JRScan.xcodeproj` and a shared `JRScan` scheme. On a Mac with stable Xcode and iOS 18+ SDK, run `bash scripts/build-ipa.sh` from a fresh checkout. No local XcodeGen install is needed. CI builds Release for `generic/platform=iOS`, disables code signing, verifies the `iphoneos` platform and arm64 executable, packages exactly `Payload/JRScan.app`, and checks the ZIP. This is a device app, not a simulator executable. CI never reconstructs user scans.

GitHub standard public-repository runner use is free under current service policy; private repositories have allowances. Do not enable paid overages for this project. No paid runner, runtime backend or Apple membership is required by this workflow.

## Windows / iPhone installation (one batch)

1. Follow the [official AltStore Classic Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows), including its Apple iTunes/iCloud requirements and exceptions. Use **Classic**, not PAL. Run AltServer, connect/unlock the phone by USB, accept Trust, and enable Wi-Fi sync. Install AltStore using AltServer. Enter Apple credentials only locally into AltServer, never in GitHub or this chat.
2. Trust the developer profile if requested. Enable **Settings → Privacy & Security → Developer Mode**, including restart and confirmation. Confirm AltStore opens.
3. Transfer the extracted `JRScan.ipa` to iPhone Files (e.g. iCloud Drive). With AltServer reachable, open **AltStore Classic → My Apps → +**, select the IPA and complete installation.
4. Open JR Scan. Report exact iOS version, app/build version, whether both capability rows say Supported, and whether allowing Camera works. If permission is denied, the app provides Open Settings.
5. Note the persistence ID and launch count. Force-close/reopen; confirm the ID stays the same and count increases. Keep this ID for the later in-place update check. Send the actual error or screenshot only when something fails.

Refresh both JR Scan and AltStore before free signing expires (normally seven days). Free accounts have active-app limits; AltStore occupies a slot. Keep AltServer reachable; automatic refresh is best effort and USB is a fallback. **Do not uninstall as a routine update step**: uninstalling can remove local data. Back up future scans through Files/share before updates.

## Next gates

After the install check passes: guided ObjectCaptureSession/ObjectCaptureView capture → durable input → on-device PhotogrammetrySession `.reduced` reconstruction → preview → actual triangle OBJ conversion with transforms and explicit meters/mm coordinates. Then scan list, cancellation/interruption recovery, backups and exportable diagnostics. Only request a controlled scan test after that build compiles and is downloadable. No promise of arbitrary reconstruction resume or metrology accuracy.

## Verification record

- Windows source inspection only at initial implementation; no local Xcode/compiler is available.
- Cloud build: pending (see Actions for evidence).
- AltStore install, capabilities, camera, persistence and update tests: pending physical phone verification.

## Sources / licenses

No Apple sample source has been copied in this gate. Before adapting sample code in Milestone 2, inspect its actual license and preserve required notices. No blanket license is assigned to Apple frameworks or third-party code. XcodeGen is a build-only dependency downloaded with its bundled license; it is not included in the app.

- [Apple ObjectCaptureSession](https://developer.apple.com/documentation/realitykit/objectcapturesession)
- [Apple PhotogrammetrySession support](https://developer.apple.com/documentation/realitykit/photogrammetrysession/issupported)
- [GitHub runner software](https://github.com/actions/runner-images)
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [AltStore Windows setup](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
