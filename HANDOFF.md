# JR Scan handoff — 2026-11-02

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

## Latest verified build

Version **0.4.0 (13)**; compiled source ed6f86fd57ff2c8ac009288ac9bc263a286a01a1.
SUCCESSFUL run https://github.com/Jzondu/jr-scan-ios/actions/runs/41439428600
Artifact https://github.com/Jzondu/jr-scan-ios/actions/runs/41439428600/artifacts/13137678171 (JRScan-unsigned-13; extract outer ZIP for JRScan.ipa).
Local IPA build/downloads/run-13/JRScan.ipa; logs build/downloads/run-13/logs.
SHA-256 290a546a76d475d8d0ed290f4bf2e11d45a922dc7dd659eb7d96ff29dc7c4e71 independently matches CI.
Standard macos-26, ARM64, image macos26 20261026.0455.2, Xcode26.6(17F113), iOS SDK26.5, XcodeGen2.44.1; minimum iOS18. Native device compilation/package passed.
All synthetic tests PASS: prior transforms/reflections/normals/1000xunits/USDZ/diagnostic filtering/crop/cleanup, plus LiDAR buffers,16/32bitindices, transforms, combinedOBJ, checkpointroundtrip, anchormutation/removal and recovery.
LiDAR sensor access/overlay/quality/recovery and real edited exports are NOT phone-tested. No known-good LiDAR tag. Runs11–12 superseded while standard macos15Intel/ARM queued; run13 on macos26 succeeded. Workflow default now macos26 (same runner actually tested in run13), alternatives26Intel/15/15Intel, standard only. No new binary build needed for documentation/default-choice-only changes.

## Next human test (batch)

Install build13 IN PLACE (same identity/account; do not uninstall). New live LiDAR scan: move slowly around nearby static surfaces for15–30seconds while mesh/counts appear, Finish & save, check original LiDAR preview, crop some surroundings, export OBJ to Windows. Force-close/reopen; ensure saved model persists. A second short capture with Close can test Recover saved LiDAR mesh. If any step fails, exact error/step plus diagnostic text; do not ask for a full photo recapture. Keep known-working previous IPA and external backups; refresh AltStore/JRScan before free signing expires.

## Tools/build

Portable gh .tools/gh/bin/gh.exe. Git Credential Manager cached credential authorizes pushes/API/dispatch; retrieve only to process-local GH_TOKEN without printing/logging/persisting secrets or raw credential-fill. Workflow manual build-ios.yml, timeout25min, artifacts7days, standard runners only. CI runs generated fixtures only, never personal scan reconstruction. No local Xcode. Apple sample license remains bundled and in source. README has live scan/edit/install/build instructions and test evidence. Documentation-only changes do not trigger builds.
