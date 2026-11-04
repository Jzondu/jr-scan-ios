# JR Scan

Native personal object scanner for iPhone 16 Pro. [Project specification](JR-Scan-Project-Brief.md).

## Current build and verified state

**Version 0.4.1 (18)**: [download JRScan-unsigned-18](https://github.com/Jzondu/jr-scan-ios/actions/runs/41882505350/artifacts/13350486080) · [successful CI run](https://github.com/Jzondu/jr-scan-ios/actions/runs/41882505350).

This build includes the fix for build 13's nonfinite LiDAR mesh update failure: retain usable geometry, regenerate normals, and keep capture running through unusable anchor updates. **Compilation and synthetic regressions passed; the fix still needs a phone capture test.**

Extract the outer artifact ZIP to obtain **JRScan.ipa**. Do not select the artifact ZIP in AltStore or rename the ZIP to IPA. Keep the IPA compressed; its internal Payload folder is for the installer. Artifacts expire after seven days; retain a known-good IPA locally.

- Build 18 compiled and packaged successfully on the standard **macos-26-intel** runner (image macos26 20260824.0517.1, X64), Xcode 26.6 (17F113), iOS SDK 26.5, XcodeGen 2.44.1. Source commit `fefd5b1ce88d36fbb95a014cfcdfc332c20b98c7`; the resulting iPhone executable is **arm64**.
- Synthetic checks passed for nonfinite-position filtering, finite normal regeneration, retaining the last valid patch, sanitized checkpoint/OBJ round trip, plus the existing transforms, winding, normals, unit conversion, USDZ import, diagnostics, crop/cleanup, LiDAR buffer decoding, multi-anchor assembly and recovery tests. These use generated data on the build Mac, not physical sensors.
- Downloaded build 18 independently matches CI SHA-256: `a867f415aa37676ee13c215b8f0e773af85bfa153c92d8ad3c8f6b730213303b`. ZIP integrity, stable bundle ID, device platform, arm64 executable, iPhone-only family, version, camera purpose and unchanged bundled license bytes were checked.
- Build 3 installed and opened on the user's reported iOS **27.0**. After build 9, the user reported “works” for reconstruction retry, then again following the export/units/persistence test request. Build 13's phone LiDAR test stopped on a nonfinite update. Successful real LiDAR capture/recovery, real-mesh crop/cleanup, edited export and update persistence remain unverified.

Build 17 failed before any build steps ran: GitHub reported an internal server error and could not allocate a hosted runner. GitHub also reported an [Actions incident](https://stspg.io/7pwv28hvkmz8). Build 18 succeeded using the workflow's existing alternative `macos-26-intel` choice; no paid service, Apple credentials or permission changes were needed. If retrying a runner allocation failure, select that runner in **Actions → Build unsigned iPhone IPA → Run workflow**. A runner allocation failure supplies no compiler result.

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

Version 0.2.1 adds **Retry without object masking / checkpoints** to failed/interrupted/cancelled scans. It reads the existing saved images, disables object masking and supplies no checkpoint directory. It leaves the original capture images/checkpoints intact and creates a new output filename. Background geometry may be included; that warning stays visible on a successful result. This is an optional fallback; it does not change the default guided path or establish the original failure cause. [An Apple engineer recommended an image-only check](https://developer.apple.com/forums/thread/827696) in a similar mask-related report; that report does not prove the same cause here.

For a failure, share diagnostic text **before recapturing**. New attempts record reconstruction mode, last framework stage, saved input count, whether capture finish was confirmed, available disk space, Swift error type/simple case, NSError domain/code and a bounded underlying error chain. The formatter selects text fields rather than dumping arbitrary `userInfo` payloads; a synthetic regression checks this. Older failures cannot acquire missing past details retroactively; one retry on the updated build records the richer report. Build 6 reached reconstruction on the phone but failed with the screenshot error above. The supplied diagnostic log confirmed 25 saved images and two failed reconstruction attempts, without the detailed processing stage. The user subsequently reported that the build 9 retry worked; the original root cause remains unproven.

## Live LiDAR surface scan (0.4.0)

Build 13 passed synthetic checks for padded buffer offsets/strides, 16/32-bit indices, truncated/invalid input rejection, anchor-to-world transforms, reflected normals/winding, combined multi-anchor OBJ, binary checkpoint round trip, replacement/removal of updated anchors and recovery. These tests use generated data on the build Mac. The subsequent phone test failed on a nonfinite mesh update; successful real LiDAR capture and quality remain unverified.

Select **New live LiDAR scan** for a separate ARKit `sceneReconstruction = .mesh` path. It directly records ARKit's LiDAR-derived scene mesh; it does not invoke Object Capture or photo reconstruction. Existing **New object scan** remains available for photo detail. ARKit returns a processed surface estimate, not raw per-ray sensor samples. Hardware support and Camera permission are checked.

1. Aim at nearby static surfaces and move slowly around them from several angles. The camera view overlays the current mesh in teal wireframe. Watch the tracking message and triangle/patch counts. LiDAR captures surroundings too; it is coarse for small-object detail and does not promise engineering accuracy.
2. Checkpoints save approximately every two seconds. **Finish & save mesh** stops capture, flushes current patches, applies every anchor's world transform and index offsets, removes duplicate/degenerate geometry, and saves a validated meter OBJ. It keeps all disconnected pieces by default; choose what to remove afterward in Crop & clean mesh.
3. Open the scan and **Preview original LiDAR mesh**. Use the existing **Crop & clean mesh**, geometry preview and **Export geometry OBJ…** meters/mm controls. **Share original LiDAR OBJ (meters)** shares the unedited meter geometry. This mode has no textured USDZ output or RGB texture capture.
4. **Close and keep saved mesh**, an interruption, or a force-quit can leave an unfinished scan. Open it and select **Recover saved LiDAR mesh** to combine its last committed patches. A force-quit can lose changes since the most recent completed checkpoint. Recovery does not restart the AR tracking session or merge separate captures. After a pause/interruption, finish the retained mesh or close and start a new scan; tracking is deliberately not auto-resumed across an uncertain coordinate origin.

Local `RawLiDAR/index.json` references binary property-list patches with vertices, normals, triangle indices and anchor-to-world transforms. Updated anchors replace old revisions; removed anchors are removed from the next committed snapshot. Changed patch files are written before the atomic index commit, and obsolete committed revisions are retired afterward. Final model publication follows validated OBJ writing. The scan backup includes the archive; it contains geometry, not photographs. Disk failures are reported and pause capture; previously committed checkpoints remain recoverable.

To bound memory and scan size, capture pauses at **250,000 triangles or 512 patches**, retaining accepted geometry and prompting you to finish. Plane detection/flattening is disabled. No automatic watertightness, fine-detail, exact-distance or full-room coverage guarantee is made. Capture, assembly, crop and export run locally; the build Mac only compiles and checks synthetic fixtures.

**One device test:** update in place, choose New live LiDAR scan, move slowly around a nearby static surface for about 15–30 seconds, then Finish & save. Confirm a nonempty aligned mesh in preview, crop some surroundings, export OBJ and open it on Windows. Force-close/reopen to check saved geometry; use a second short capture with Close to check Recover saved LiDAR mesh. If any step fails, send the exact error and scan diagnostic text; no full photo recapture is needed.

### Nonfinite mesh update recovery (0.4.1)

A build 13 device log reported `LiDAR returned a nonfinite vertex or normal` four seconds into capture, after which the user closed the scan. Support checks were true and free storage was about 32 GB. This exposed overly strict session-wide failure handling; the log does not distinguish invalid positions from invalid normals or prove why that update contained nonfinite data.

Live capture now derives normals from valid triangle geometry instead of consuming ARKit's normal buffer. Faces touching nonfinite positions and degenerate faces are discarded; unused positions are compacted. No unknown coordinate is replaced with zero. An entirely unusable or malformed update keeps the previous valid patch, while other anchors continue updating. Warnings and filtering counts are shown/logged separately from fatal session or disk failures. Final save/close records a warning summary. Saved geometry still passes validation before publication/export.

The regression fixture mixes valid triangles with NaN/Infinity positions and degenerate faces, checks finite generated normals, retains a prior valid patch on an all-bad update, and round-trips filtered geometry through checkpoints and OBJ. These checks passed in build 18; phone confirmation remains required. Existing build 13 checkpoints can still be recovered if they contain valid patches; geometry never collected before that failure cannot be recreated from an empty checkpoint.

## Crop and mesh cleanup (0.3.0)

Open an existing scan with a model and select **Crop & clean mesh**. No recapture or reconstruction is required.

1. Rotate with one finger, pinch to zoom, and use the **3D / Front / Top / Side** views. Adjust the X, Y and Z Min/Max sliders to position the outlined crop box around the geometry to keep. Values are shown in millimeters; stored coordinates remain meters. The box uses model axes; it does not rotate with the camera. Reset crop box restores the current source's full bounds.
2. Choose **Keep all pieces**, **Remove tiny pieces (<1% area)** (default), or **Keep largest piece only**. The threshold is relative to the largest connected piece's surface area, not its triangle count. Largest-only may remove intentional disconnected object parts or retain a large table; crop the background first and inspect the result.
3. Choose **Preview changes**. Faces crossing the crop boundary are clipped and triangulated. Cleanup welds nearly identical positions at a small scale-relative tolerance, removes duplicate/degenerate faces, compacts unused vertices and recalculates area-weighted normals. It retains the source face winding. Use **Show unedited source** to compare. Changing controls invalidates the prepared result; preview again before saving. An empty crop is rejected.
4. **Save edited geometry** writes a separate, validated meter OBJ and edit note. The scan then offers **Preview edited geometry** and **Export edited geometry OBJ…** with the existing meters/mm choice. The original textured USDZ and capture inputs remain untouched. **Restore original geometry…** switches editing/export back to the original; previous revision files remain in the scan backup. Reopening the editor starts from the current saved revision; Reset crop box does not restore geometry removed by an earlier saved revision.

Edits are geometry only. Cut edges can stay open: this version does **not** fill holes, cap cuts, smooth/shrink geometry, repair arbitrary face winding, or promise a watertight printable mesh. A new successful reconstruction switches the active model to that new output and clears the active edit reference; old model/edit files remain in the backup. Failed edits do not replace the previous saved revision.

Build 10's synthetic tests passed for clipping surface area (including crossing faces and multiple planes), seam welding, cyclic duplicate/degenerate removal, loose-piece policies, recalculated normals, source preservation, empty-crop rejection, and edited OBJ save/reload. Existing transform/units/USDZ/diagnostic checks also passed. The native editor compiled for device, but touch behavior and editing a real scan are awaiting phone testing.

**One phone test:** update in place, open an existing scan, crop away a little background, preview, save, and export edited OBJ to Windows. Force-close/reopen to check the edit remains. Preview the original USDZ and try Restore original geometry to confirm recovery. Report the first failing step and diagnostic text rather than recapturing.

## Local files, recovery and diagnostics

- Scan folders: **Files → On My iPhone → JR Scan → Scans → UUID**. Each stores an atomic `scan.json`, `Images`, `Checkpoints`, `Models`, `Exports` and a bounded plain-text event log. Names, IDs, timestamps and processing/export states are persistent.
- Force-quit/restart during capture or reconstruction marks an unfinished scan interrupted on next launch. Saved inputs remain; reconstruct from them if usable. Previous successful models stay available after a failed retry. Partial reconstruction output is never presented as a successful new model.
- **Save scan and capture inputs to Files…** copies the whole scan directory through the system document picker, including photographs and checkpoints. Choose an external destination. No iCloud entitlement is required for ordinary Files export. Do not edit internal files while a scan is processing. This version does not have a backup-import UI.
- **Share diagnostic text…** exports version, OS/device family, capability support, stage, warnings and errors. It excludes photo contents and account credentials. Do not send the full scan backup when only a diagnostic log is needed.
- **Delete scan…** requires confirmation and removes that scan's inputs/models/exports. Deletion is disabled during active work. Low-space checks require at least 1 GB free before starting capture, reconstruction or export; large scans may need more. Actual write/framework errors are also shown, and inputs are retained on processing/export failures.
- **Device and persistence checks** retains the original marker ID/count from build 3, so in-place update persistence can be checked directly.
- No user accounts, telemetry, API keys, mandatory network access or runtime reconstruction server. GitHub holds code/build artifacts, not scans. After installation, capture/reconstruction/export are designed to run offline; physical offline verification is pending.

## Additional scan acceptance checks

1. Update in place from build 3. Confirm version **0.4.0 (13)**; check that the old persistence marker ID survives and both capabilities say Supported. Allow Camera.
2. Use the working reconstruction route when testing a new capture. Keep JR Scan open and inspect the preview for background/missing geometry. If a step fails, share diagnostic text and the exact error before further tests. No new capture is required for the crop/cleanup check above.
3. Export the same model in both meters and millimeters; save the offered files externally. Open in Blender/MeshLab on Windows. Verify a triangle mesh, expected chunks, and millimeter coordinate dimensions **1000x** the meter dimensions (account for importer unit settings). Compare a known physical dimension without assuming engineering accuracy.
4. Force-close/reopen; confirm the scan, model and export status remain. Confirm Files backup works. In a later session, test cancellation/background interruption, restart from input, the next in-place update, and AltStore refresh/data persistence.

## Reproducible cloud build

The manual workflow defaults to the successfully tested standard `macos-26` runner. Alternatives are `macos-26-intel`, `macos-15` and `macos-15-intel` if a pool is queued; all build an arm64 iPhone app. No larger/paid runner is used. Open [Actions → Build unsigned iPhone IPA](https://github.com/Jzondu/jr-scan-ios/actions/workflows/build-ios.yml) → **Run workflow → main → Run workflow**. No Apple credentials, certificates, signing profiles, paid services or secrets are required. Only manual triggers are enabled to avoid duplicate compute. Standard public-repository runner use is free under current GitHub policy; avoid enabling paid overages if switching to a private repository.

The workflow runs synthetic conversion checks on macOS, then builds Release for **generic/platform=iOS**, with signing disabled. It verifies `iphoneos`, arm64 and bundle ID, packages `Payload/JRScan.app` into **JRScan.ipa**, validates ZIP integrity, and uploads IPA/build information plus build/test logs. Timeout: 25 minutes. Artifact retention: 7 days. A successful cloud build proves neither sensor access nor AltStore installation.

Configuration is source-controlled in `project.yml`. Pinned XcodeGen **2.44.1** is downloaded with SHA-256 verification and generates the project/shared scheme. The runner's installed stable default Xcode is used, avoiding a guessed hard-coded application path. SDK <18 and visibly beta/preview versions are rejected. Exact Xcode/SDK/runner/XcodeGen versions, source commit, build number and IPA checksum appear in `build-info.txt`. Hosted images can change; use those recorded versions to reproduce a particular output. No compiler is available locally on Windows.

On a Mac with a stable iOS 18+ SDK:

```sh
python3 tests/make_usdz_fixture.py
mkdir -p build/logs
xcrun --sdk macosx swiftc JRScan/OBJExporter.swift JRScan/ReconstructionFailure.swift JRScan/MeshEditing.swift JRScan/LidarMesh.swift tests/GeometryChecks.swift tests/MeshEditingChecks.swift tests/LidarMeshChecks.swift -o build/geometry-checks
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
