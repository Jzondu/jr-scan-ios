# JR Scan

Native personal object scanner for iPhone 16 Pro. [Project specification](JR-Scan-Project-Brief.md).

## Current build and verified state

**Version 0.2.1 (9)**: [download JRScan-unsigned-9](https://github.com/Jzondu/jr-scan-ios/actions/runs/41418316114/artifacts/13127953700) · [successful CI run](https://github.com/Jzondu/jr-scan-ios/actions/runs/41418316114).

Extract the outer artifact ZIP to obtain **JRScan.ipa**. Do not select the artifact ZIP in AltStore or rename the ZIP to IPA. Keep the IPA compressed; its internal Payload folder is for the installer. Artifacts expire after seven days; retain a known-good IPA locally.

- Build 3 (0.1.0) installed and opened on the user's iPhone; user reports iOS **27.0**. An initial “wrong format” report was followed by confirmation that installation/launch worked; its exact cause was not established.
- Build 9 compiled and packaged successfully on the standard macos-15-intel runner (image macos15 20260824.0482.1, X64), Xcode 16.4 (16F6), iOS SDK 18.5, XcodeGen 2.44.1. Source commit `1667d713b939466a4d359a2da6dc109d6c20baf5`.
- Synthetic geometry checks passed on the macOS runner: nested transforms, nonuniform scale, reflected winding, inverse-transpose normals, triangle topology, invalid index/empty geometry rejection, 1000x meter/mm conversion, and USDZ import → OBJ export. Diagnostic domain/code/underlying-chain extraction also passed a check excluding arbitrary userInfo payloads. These are not sensor/reconstruction or iPhone conversion tests.
- Downloaded build 9 independently matches CI SHA-256: `0c84ac6d686a728b9f94952acd0d7501d9f1c4fae68fc2ce1b425f4a815b1290`. ZIP integrity, stable bundle ID, device platform, arm64 executable, iPhone-only family, version, camera purpose and bundled license were inspected.
- **Build 9 installation, actual capture/reconstruction, iPhone OBJ conversion, physical scale, sharing, backup and update persistence remain unverified.**

Stable identity: **`fi.jzondu.jrscan`**, minimum iOS **18.0**. Keep this identity and the same local signing account for updates. AltStore may rewrite the signed bundle identifier for the account; actual update persistence needs testing. The build SDK is recorded above; an older SDK does not itself establish incompatibility with a newer runtime. The install-check build launched on the user's reported iOS 27.0; the new workflow still needs physical verification there.

## Windows installation and updates

1. Set up **AltStore Classic**, not PAL, following the [official Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Use its specified Apple iTunes/iCloud components and troubleshooting exceptions. Run AltServer, connect/unlock the iPhone by USB, accept Trust and enable Wi-Fi sync.
2. Install AltStore through AltServer. Enter Apple credentials **only locally into AltServer**, never in GitHub or chat. Trust the developer profile if requested. Enable **Settings → Privacy & Security → Developer Mode**, including restart/confirmation.
3. Download and extract the GitHub artifact ZIP on Windows. Transfer **JRScan.ipa** to iPhone Files (for example using iCloud Drive). With AltServer reachable, choose **AltStore Classic → My Apps → + → JRScan.ipa**.
4. For updates, install in place using the same account and bundle identity. **Do not delete the installed app.** Export important data first; uninstalling can remove local files. Keep an external copy of a known-good IPA.
5. Refresh JR Scan and AltStore before free signing expires (normally seven days). Free accounts have active-app limits, and AltStore occupies a slot. Automatic refresh is best effort; keep AltServer reachable, with USB as a fallback.

If AltStore reports an invalid format, confirm the selected file is the extracted **JRScan.ipa**, not the outer artifact ZIP or a downloaded HTML page. If it still fails, report the exact error/domain/code, filename, and AltStore/AltServer versions; do not assume the OS or signing route is the cause.

## Scan and export

1. Open **New object scan**, allow Camera, and aim at a stationary matte textured object in even light. Start around 10–30 cm across for a forgiving first test.
2. Select **Detect object**, adjust the bounds, then **Start capture**. Move slowly around the object; follow Apple's camera view, coverage dial and quality feedback. Automatic capture is enabled; manual **Take image** is also available. When a pass completes, select **New pass at another height** as practical. Keep the object stationary; an object-flip workflow is not part of this first version.
3. Choose **Finish & save**. Wait for the framework to finish saving input before returning to the scan list. Cancellation keeps already-written inputs, though partial captures may not reconstruct.
4. Open the saved scan and choose **Reconstruct saved input**. This runs **on the iPhone**, using the supported iOS **Reduced** level, with actual framework progress. **Keep JR Scan in the foreground.** Backgrounding cancels processing and records interruption. A retry starts a new request from saved input/checkpoints; arbitrary mid-session resume is not promised. Each attempt writes a new USDZ without replacing earlier outputs.
5. Choose **Preview — rotate and zoom**. The original USDZ remains available for sharing even if OBJ conversion fails.
6. Select **Meters** or **Millimeters**, then **Export geometry OBJ…**. Use the share sheet's **Save to Files** and save all offered companion files. Model I/O imports the original, flattens hierarchy transforms into new triangle buffers, transforms normals, corrects reflected winding, and encodes OBJ. The exported file is checked for nonempty triangle geometry and valid vertex/normal indices before sharing. Unsupported topology/conversion produces an error, retaining the source; no point cloud or renamed USDZ is substituted.
7. The unit choice numerically scales coordinates: millimeters = meter coordinates × **1000**. Units appear in the filename and export note. OBJ has no universal unit declaration; configure Blender/MeshLab's importer accordingly. Metric reconstruction is not metrology-grade accuracy. Compare with a known physical measurement and record discrepancy.

Geometry OBJ is the current export; textured OBJ is deferred until geometry passes physical tests. Reflective, transparent, thin, moving or featureless subjects may reconstruct poorly.

## Reconstruction failure / retry without recapturing

A device screenshot reported `CoreOC.PhotogrammetrySession.Error`, code **6**, during reconstruction. This confirms a framework reconstruction failure; the numeric code alone does not establish its cause. The capture inputs remain local. Do not delete the app or scan to troubleshoot it.

Version 0.2.1 adds **Retry without object masking / checkpoints** to failed/interrupted/cancelled scans. It reads the existing saved images, disables object masking and supplies no checkpoint directory. It leaves the original capture images/checkpoints intact and creates a new output filename. Background geometry may be included; that warning stays visible on a successful result. This is an alternate diagnostic attempt, not a verified solution or a change to the default guided path. [An Apple engineer recommended an image-only check](https://developer.apple.com/forums/thread/827696) in a similar mask-related report; that report does not prove the same cause here.

For a failure, share diagnostic text **before recapturing**. New attempts record reconstruction mode, last framework stage, saved input count, whether capture finish was confirmed, available disk space, Swift error type/simple case, NSError domain/code and a bounded underlying error chain. The formatter selects text fields rather than dumping arbitrary `userInfo` payloads; a synthetic regression checks this. Older failures cannot acquire missing past details retroactively; one retry on the updated build records the richer report. Build 6 reached reconstruction on the phone but failed with the screenshot error above. Its actual failure stage and input count are still awaiting the user's log. Build 9 compiles and packages successfully; the fallback has not yet been verified on that saved scan.

## Local files, recovery and diagnostics

- Scan folders: **Files → On My iPhone → JR Scan → Scans → UUID**. Each stores an atomic `scan.json`, `Images`, `Checkpoints`, `Models`, `Exports` and a bounded plain-text event log. Names, IDs, timestamps and processing/export states are persistent.
- Force-quit/restart during capture or reconstruction marks an unfinished scan interrupted on next launch. Saved inputs remain; reconstruct from them if usable. Previous successful models stay available after a failed retry. Partial reconstruction output is never presented as a successful new model.
- **Save scan and capture inputs to Files…** copies the whole scan directory through the system document picker, including photographs and checkpoints. Choose an external destination. No iCloud entitlement is required for ordinary Files export. Do not edit internal files while a scan is processing. This version does not have a backup-import UI.
- **Share diagnostic text…** exports version, OS/device family, capability support, stage, warnings and errors. It excludes photo contents and account credentials. Do not send the full scan backup when only a diagnostic log is needed.
- **Delete scan…** requires confirmation and removes that scan's inputs/models/exports. Deletion is disabled during active work. Low-space checks require at least 1 GB free before starting capture, reconstruction or export; large scans may need more. Actual write/framework errors are also shown, and inputs are retained on processing/export failures.
- **Device and persistence checks** retains the original marker ID/count from build 3, so in-place update persistence can be checked directly.
- No user accounts, telemetry, API keys, mandatory network access or runtime reconstruction server. GitHub holds code/build artifacts, not scans. After installation, capture/reconstruction/export are designed to run offline; physical offline verification is pending.

## One batched device acceptance test for build 9

1. Update in place from build 3. Confirm version **0.2.1 (9)**; check that the old persistence marker ID survives and both capabilities say Supported. Allow Camera.
2. First recover the existing failed scan: open it and select **Retry without object masking / checkpoints**, keeping JR Scan open. No recapture is needed. If it fails, share diagnostic text and the exact error before further tests. If it succeeds, inspect the preview for background/missing geometry, then continue below. A later new scan can verify the complete guided path.
3. Export the same model in both meters and millimeters; save the offered files externally. Open in Blender/MeshLab on Windows. Verify a triangle mesh, expected chunks, and millimeter coordinate dimensions **1000x** the meter dimensions (account for importer unit settings). Compare a known physical dimension without assuming engineering accuracy.
4. Force-close/reopen; confirm the scan, model and export status remain. Confirm Files backup works. In a later session, test cancellation/background interruption, restart from input, the next in-place update, and AltStore refresh/data persistence.

## Reproducible cloud build

The manual workflow offers standard `macos-15` (default) and `macos-15-intel` runners. Use Intel if the ARM queue is delayed; both build an arm64 iPhone app. Open [Actions → Build unsigned iPhone IPA](https://github.com/Jzondu/jr-scan-ios/actions/workflows/build-ios.yml) → **Run workflow → main → Run workflow**. No Apple credentials, certificates, signing profiles, paid services or secrets are required. Only manual triggers are enabled to avoid duplicate compute. Standard public-repository runner use is free under current GitHub policy; avoid enabling paid overages if switching to a private repository.

The workflow runs synthetic conversion checks on macOS, then builds Release for **generic/platform=iOS**, with signing disabled. It verifies `iphoneos`, arm64 and bundle ID, packages `Payload/JRScan.app` into **JRScan.ipa**, validates ZIP integrity, and uploads IPA/build information plus build/test logs. Timeout: 25 minutes. Artifact retention: 7 days. A successful cloud build proves neither sensor access nor AltStore installation.

Configuration is source-controlled in `project.yml`. Pinned XcodeGen **2.44.1** is downloaded with SHA-256 verification and generates the project/shared scheme. The runner's installed stable default Xcode is used, avoiding a guessed hard-coded application path. SDK <18 and visibly beta/preview versions are rejected. Exact Xcode/SDK/runner/XcodeGen versions, source commit, build number and IPA checksum appear in `build-info.txt`. Hosted images can change; use those recorded versions to reproduce a particular output. No compiler is available locally on Windows.

On a Mac with a stable iOS 18+ SDK:

```sh
python3 tests/make_usdz_fixture.py
mkdir -p build/logs
xcrun --sdk macosx swiftc JRScan/OBJExporter.swift JRScan/ReconstructionFailure.swift tests/GeometryChecks.swift -o build/geometry-checks
build/geometry-checks build/geometry-fixture.usdz
bash scripts/build-ipa.sh
```

The Mac is only the **build/test machine**. Runtime reconstruction remains on the phone.

## Sample license and references

Capture/reconstruction sequencing and guidance were adapted with reference to Apple's **ScanningObjectsUsingObjectCapture.zip**, published asset `c13a7fb3aa69`, downloaded November 2, 2026 (SHA-256 `aeed6e762a328a4a2a4a1af5cb61e3b9847304bb28c772c4bc204acc171e5305`). Its actual copyright/permission notice is preserved verbatim in [Apple-ObjectCapture-LICENSE.txt](JRScan/Resources/Apple-ObjectCapture-LICENSE.txt), included in the app bundle and accessible through **Notices**. No blanket license is assigned to Apple frameworks or unrelated third-party code. XcodeGen is build-only, downloaded with its bundled license, and is not included in the app.

- [Apple guided capture sample](https://developer.apple.com/documentation/realitykit/scanning-objects-using-object-capture)
- [ObjectCaptureSession](https://developer.apple.com/documentation/realitykit/objectcapturesession)
- [iOS reconstruction detail levels](https://developer.apple.com/documentation/realitykit/photogrammetrysession/request/detail)
- [Model I/O](https://developer.apple.com/documentation/modelio)
- [GitHub runner software](https://github.com/actions/runner-images)
- [AltStore Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore errors](https://faq.altstore.io/altstore-classic/error-codes)
