# JR Scan handoff — 2026-11-04

## Task and constraints

Specification JR-Scan-Project-Brief.md; latest user request: implement a LiDAR scan. Previously requested crop/cleanup already implemented. iPhone16Pro, reported iOS27.0, Windows/no Mac/limited time. Unsigned GitHub macOS device builds, local AltStore Classic free signing. Stable fi.jzondu.jrscan bundle ID and same signing account for updates. No paid services, Apple credentials in CI, cloud runtime reconstruction, or library/design questions. Preserve original data/sample licenses, meaningful commits, README, batch physical tests.

Workspace C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner. Public repository https://github.com/Jzondu/jr-scan-ios, main.

## Device history

Build3 installed/launched. Build6 captured25images; two CoreOC.PhotogrammetrySession.Error6 failures (root cause unproven). Build9 added no-mask/no-checkpoint saved-image retry. User said “works” afterward, then “works” following export/units/persistence checks. Treat as user reports, no independent measurements. Build10 added crop/cleanup; no explicit physical crop report received. Do not conflate working photo flow with tested LiDAR.

## Latest feature: live LiDAR

New live LiDAR scan uses its own ARSession/ARSCNView, ARWorldTrackingConfiguration.sceneReconstruction=.mesh, plane flattening off, hardware/camera guards. Camera feed plus teal mesh wireframe, tracking feedback/counts. Captures ARKit's processed LiDAR surface mesh, not raw per-ray samples, photographs or texture. Separate Object Capture photo route retained unchanged.

ARMeshAnchor buffers are copied with stride/offset and 16/32-bit index validation. Updates replace patches by anchor UUID; removals update the set. Combining applies column-major anchor-to-world transforms, normal inverse transpose, reflection winding, global index offsets. Final geometry cleanup keeps all components by default and removes duplicate/degenerate faces/recalculates normals before validated meter OBJ publication. The saved mesh works with existing preview, crop/cleanup, meters/mm export and Files backup.

RawLiDAR binary plist patch revisions + atomic index checkpoint about every2seconds on a serial archive actor. New files written before index commit; obsolete committed revisions retired afterward. Finish flushes newest snapshot; Close keeps checkpoint inputs. Recover saved LiDAR mesh combines last committed patches locally, without photo reconstruction or resuming a tracking session. Force-quit may lose changes since last completed checkpoint. Interruption/background pauses tracking rather than silently mixing uncertain coordinate origins. Disk errors pause capture and stop automatic retry; explicit Finish retries. Limits250000triangles/512patches pause before oversized update. No watertight/fine-detail/metrology promise, no RGB textures.

Existing crop editor saves immutable meter OBJ edit revisions, preserves original model, supports restore, precise six-plane clipping and loose-component policies; no hole caps/smoothing/texture editing/arbitrary winding repair. New original publication clears active edit pointer but retains prior files. Manifest captureKind is optional for old photo records. LiDAR modelName is OBJ; photo modelName remains USDZ. UI preview/share correctly handles both.

## Latest verified build — 0.4.1 (18)

SUCCESSFUL run https://github.com/Jzondu/jr-scan-ios/actions/runs/41882505350
Artifact https://github.com/Jzondu/jr-scan-ios/actions/runs/41882505350/artifacts/13350486080 (JRScan-unsigned-18; extract outer ZIP for JRScan.ipa).
Compiled source fefd5b1ce88d36fbb95a014cfcdfc332c20b98c7 (native fix c8346f6). Documentation commits afterward do not change native code.
Local IPA build/downloads/run-18/JRScan.ipa; build-info.txt beside it; logs in build/downloads/run-18/logs.
SHA-256 a867f415aa37676ee13c215b8f0e773af85bfa153c92d8ad3c8f6b730213303b independently matches CI.
Standard macos-26-intel, X64, image macos26 20260824.0517.1; Xcode26.6(17F113), iOS SDK26.5, XcodeGen2.44.1; minimum iOS18. Native device compilation/package and all synthetic tests passed. Downloaded ZIP CRC, plist version0.4.1/build18, fi.jzondu.jrscan ID, iphoneos platform, arm64 Mach-O CPU, family[1], LiDAR camera-purpose string and original sample-license bytes independently checked.

geometry-tests.txt reports PASS for diagnostic field filtering; transforms/reflection/normals/topology/1000xunits; invalid OBJ rejection; USDZ import/export; crop/cleanup; new nonfinite-position regression/finite normals/last-valid patch retention/sanitized checkpoint+OBJ roundtrip; LiDAR buffers/indices/transforms/multi-anchor export/archive mutation/removal/recovery.

Latest user reply: “Works” after the build18 install/new15–30second LiDAR capture/Finish & save request. Record this as user-reported success of that flow, not independent sensor measurements or confirmation of every feature. Build18 is the current working baseline. No repeat of that basic test is needed unless a new change or failure warrants it. Build13 (0.4.0) was the previous compiled version; user's LiDAR test failed after4seconds with nonfinite vertex or normal, then user closed it. Savedimages0 is expected for LiDAR. Log cannot distinguish invalid positions from normals or prove the sensor's cause.

## Nonfinite LiDAR fix in build18

Old vectors() rejected any NaN/Infinity and ingest() paused the entire session for one bad update. New live path does not read ARKit normal buffers. sanitize() drops faces touching nonfinite positions and degenerates, compacts referenced vertices, derives finite normals and validates transforms. A wholly unusable update retains the previous valid patch. Per-anchor failures warn and continue other anchors. Warning counts appear in UI, sampled logs and save/close totals; fatal ARSession/storage errors still pause. Never zero-fill unknown positions or overwrite original scans.

## Remaining device validation

Basic build18 LiDAR capture/save has user-reported success. No new task or test request was made in response to that confirmation. Crop/cleanup on a real mesh, OBJ opening on Windows, persistence after relaunch and interrupted-checkpoint recovery have not been separately confirmed. Batch those checks when relevant to the next requested change; do not infer they all passed from “Works”. Preserve existing scans and install future updates in place with the same AltStore account. The old failed scan can Recover saved LiDAR mesh only if valid checkpoints exist; never-collected geometry cannot be recovered.

## Runner failure resolved by alternative pool

Runs14–16 queued/cancelled around Actions outage. Run17 failed with zero steps on macos-26: internal server error correlation2b4ec308-76b0-4d21-b98e-836bb0507f4b, hosted runner not acquired after multiple attempts. GitHub status API reported Actions partial_outage/incident h02n9572mx9y https://stspg.io/7pwv28hvkmz8, with mitigations applied. This was runner allocation failure, not app compilation failure. Run18 selected existing alternative macos-26-intel, acquired runner and completed successfully. No permission/account/signing/workflow-code changes required. No remaining queued run to monitor. README now links verified build18; earlier pending17/18 notices are obsolete.

## Tools/build

Portable gh .tools/gh/bin/gh.exe. Git Credential Manager cached credential authorizes pushes/API/dispatch; retrieve only to process-local GH_TOKEN without printing/logging/persisting secrets or raw credential-fill. Workflow manual build-ios.yml, timeout25min, artifacts7days, standard runners only. Default macos-26; choices include macos-26-intel (successful build18), macos-15 and macos-15-intel. CI runs generated fixtures only, never personal scan reconstruction. No local Xcode. Apple sample license remains bundled and in source. README includes current installation/build/scan/edit instructions and verification evidence. Documentation-only changes do not trigger builds. Keep same app identity fi.jzondu.jrscan; AltStore phone ID reported fi.jzondu.jrscan.6BZFTA29CU.
