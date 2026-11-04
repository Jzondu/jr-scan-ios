# JR Scan handoff — 2026-11-04

## Current request and constraints

User requested combined mode to increase resolution and useful tools, then specified objects/parts for 3D printing or modeling. Implemented version0.5.0. The original brief's deferrals have a dated scope addendum; user-requested part tools are authorized. Do not invent resolution or dimensional-accuracy evidence. iPhone16Pro, reported iOS27.0, Windows/no Mac/limited time. GitHub macOS only compiles; all scanning/reconstruction/editing runs on-device. No paid services, Apple credentials in CI or external uploads of scans. Stable fi.jzondu.jrscan (AltStore reported fi.jzondu.jrscan.6BZFTA29CU), same local signing account/in-place updates. Preserve originals and Apple sample license. Concise summaries; batch phone tests. No new features needed until user feedback/request.

Workspace C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner; public repo https://github.com/Jzondu/jr-scan-ios, main.

## Latest verified binary — 0.5.0 (20)

Successful run https://github.com/Jzondu/jr-scan-ios/actions/runs/41902892339
Artifact https://github.com/Jzondu/jr-scan-ios/actions/runs/41902892339/artifacts/13358752568 (JRScan-unsigned-20; extract outer ZIP for JRScan.ipa).
Compiled source06f6af928812307548940e745dbdc611e1ce3d83. First implementation812e285 compiled successfully as build19, then compatibility/UI refinements in06f6af9 passed build20. Later documentation-only commits require no additional binary build.
Local build/downloads/run-20/JRScan.ipa; build-info.txt and independent-verification.txt beside it, logs/geometry-tests.txt and logs/build.log.
SHA256 082ded6cb1a297d633242cc08db7d4d19d97db9d0357cc70ae29bccd916194d0 independently matches CI.
Standard macos-26-intel, X64, image macos26 20260824.0517.1, Xcode26.6(17F113), SDK26.5, XcodeGen2.44.1, minimumiOS18. ZIP CRC, plist ID/version/build/platform/family, arm64 Mach-O, camera purpose and original sample-license bytes verified. Compile log only AppIntents metadata warning; Actions reports Node20-action deprecation while executing under Node24, no failure.

Tests PASS: legacy photo/LiDAR manifest decoding and combined metadata roundtrip; calibration invalid-value rejection, uniform scaling, original preservation, rotation/normal/winding, Z-up bed placement; open/non-manifold/winding/normal-seam diagnostics; binary STL count/size/mm coordinates/normals, degenerate export rejection without publishing a file. Prior diagnostics filtering, transformed OBJ/USDZ,1000xunits,crop/cleanup,LiDAR buffer/index/transforms/archive/recovery and nonfinite-update regressions all passed.

No physical test of build20 yet. Last user “Works” was for build18 LiDAR capture/save, not these new tools.

## New features and implementation

CombinedCapture.swift uses Apple's existing ObjectCaptureSession photo+LiDAR pipeline, not a custom fusion engine or injection of ARMeshAnchors. ScanViews labels it Combined detail, guides middle/high/low passes, allows early finish with confirmation, and retains the device image limit (overcapture false). ScanRecord.swift now holds the Codable manifest; optional passesStarted/depthSummary/referenceScanID preserve older manifests. Pass count is STARTED, not a claim of completed coverage.

Before reconstruction CombinedCapture.audit serially samples up to12 saved images using async PhotogrammetrySample(contentsOf:) and checks depthDataMap. Reports readable/depth/unreadable counts honestly; depth absent is not fabricated. Original inputs retained. Only iOS .reduced used; no claim of more detail than existing Object Capture reconstruction. Expected photo detail benefit is relative to coarse live LiDAR and remains unmeasured. A LiDAR scan can start Capture finer detail, producing a separate linked scan; no automatic registration, fusion or coordinate mixing. Photo fallback without masking/checkpoints remains available. CoreOC.Error6 cause from earlier builds remains unproven.

PartGeometry.swift: axis-aligned dimensions from bounds, scaleFactor validates known mm vs measured meters (positive finite, factor0.001–1000); transform preserves source, rotates positions/normals about bounds center, positive uniform scaling, optional XY center/Zmin0. report matches exact positional seams and counts boundary/non-manifold/inconsistent-winding/degenerate geometry without modifying it. No self-intersection, hole repair, CAD conversion or printability certification. Binary STL writes mm coordinates, normals derived from winding, validates count/size/finite nondegenerate geometry before atomic file publication.

PartToolsView.swift: visible two surface points and distance, reference calibration using picked distance or selected axis extent,90degree rotations,Z-up front/top/side views,center/bed placement,report/reset/save. MeshSceneView optional tap handler uses only mesh hit tests and adds markers/line; disabled during transform/save, points cleared on transform. Decimal keyboard has Done/interactive dismissal. Geometry saves through existing immutable edit revisions and Restore original. ScanStore.exportSTL uses CURRENT SAVED geometry, exports companion report/units note and logs failures; existing OBJ meter/mm export still uses saved revision. STL may contain holes; invalid faces are rejected with cleanup suggestion.

Existing architecture: ScanStore persists atomic manifests and per-scan Images/Checkpoints/Models/Exports/Edits/RawLiDAR. Crop uses six-plane triangle clipping, welding, duplicate/degenerate removal, fragment policies, recomputed normals; no caps/smoothing. LiDAR ARSCNView uses sceneReconstruction.mesh, no plane flattening; anchor replacement/removal, local checkpoints every2seconds, finite-face filtering/normal regeneration, prior patch retention for bad updates. Actual ARSession/disk failure pauses. Limits250k triangles/512patches. Recover saved mesh combines committed patches, not a tracking-session resume. Finished geometry and edits preserve original data.

## One batched device/slicer check

Install build20 IN PLACE with same AltStore account, retain previous scans. Tools can be tried on an existing model immediately. For detail comparison, capture one known-size matte part with Combined detail at three heights (or finish at framework limit), save and reconstruct. Check reported sample depth presence without assuming every sample must have it. Crop background, pick a known feature, enter its caliper/ruler measurement, calibrate, orient/bed-place, save, export millimeter STL and inspect dimensions/orientation/open edges in Windows slicer. Reopen scan to verify persistence. If failure, exact step plus diagnostic text; do not request repeated full captures without need. Touch/quality/scale improvement/real STL are pending until user confirms.

## Device history and rollback baseline

Build3 launched. Build6 captured25images then CoreOC photogrammetry error6. Build9's saved-image no-mask/no-checkpoint retry got “works”, followed by another “works” after export/unit/persistence request (no measurements supplied). Build10 crop/cleanup compiled, not separately phone-confirmed. Build13 LiDAR failed after4seconds on nonfinite vertex or normal. Build18 filters bad faces and regenerates normals, retaining previous valid anchor patches. User reported “Works” after its new short capture/Finish&save request. This is user-reported success, not independent measurements.
Build18 IPA still at build/downloads/run-18/JRScan.ipa, sourcefefd5b1ce88d36fbb95a014cfcdfc332c20b98c7 (nativefixc8346f6). SHA256 a867f415aa37676ee13c215b8f0e773af85bfa153c92d8ad3c8f6b730213303b. Run41882505350 artifact13350486080. Keep as known working previous version. Old failed scans recover only if valid checkpoints exist.

## Tools/build

Portable .tools/gh/bin/gh.exe. Git Credential Manager cached credential authorizes pushes/API/dispatch; retrieve only into process-local GH_TOKEN, never print/log/persist token or raw credential-fill. Workflow manual build-ios.yml,25minute timeout,7day artifacts,standard runners only. Defaultmacos26; use macos-26-intel (successful18–20). Run17 failed hosted runner allocation with zero steps during Actions outage; resolved by alternative pool, not app code/signing changes. No run left to monitor. No local Xcode. Apple sample license remains unchanged in source/app. README includes feature use, limits, install/build evidence and exact test request. Reversible documentation fixes need no new compile.
