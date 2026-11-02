# JR Scan handoff — 2026-11-02

## Task and constraints

Implement JR-Scan-Project-Brief.md autonomously; newest user request: add crop and mesh cleanup. iPhone16Pro, reported iOS27.0, Windows/no Mac/limited time. Unsigned GitHub macOS builds, local AltStore Classic free signing. No paid services, Apple credentials in CI, cloud runtime reconstruction, or library/design questions. Preserve stable fi.jzondu.jrscan bundle ID, same signing account, original scan inputs/models, sample licenses, meaningful commits and README. Batch physical tests.

Workspace C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner. Public repository https://github.com/Jzondu/jr-scan-ios, main.

## Device history

Build3 install check launched. Build6 captured 25 images; reconstruction twice failed CoreOC.PhotogrammetrySession.Error6 (no proven numeric-code cause). Build9 v0.2.1 added saved-image retry without masks/checkpoint reuse and richer diagnostics. User replied “works” after the retry, then “works” following export/units/persistence checks. Treat these as user reports, not independent measurement evidence. No need to ask for a fresh capture for editor testing. Working reconstruction remains on iPhone; source/CI uses .reduced and folder input.

## Current implemented upgrade

- Native Crop & clean mesh editor on existing scans, interactive orbit/zoom plus 3D/front/top/side cameras and visible axis-aligned crop box, six min/max sliders with mm display.
- Preview changes clips intersecting triangles precisely against six planes, retriangulates, welds near-identical positions, removes duplicate/degenerate faces, filters disconnected components by area (all / below1%largest / largestonly), compacts vertices and recalculates normals. Original winding retained.
- Saved edits are separate validated meter OBJ revisions with notes under Edits/UUID. Original USDZ/capture images/checkpoints retained. Original preview/share remains available. Active saved edit is used by meters/mm OBJ export. Edited geometry has its own native preview. Restore original clears active edit reference but retains revision files in backup. New successful reconstruction clears active edit pointer, retaining old files.
- Editing is geometry-only. No cap/hole filling, smoothing, texture editing, arbitrary winding repair or watertight guarantee. Empty/invalid crop rejected. Pending settings cannot be saved until previewed.
- Optional manifest fields editedModelName/editSummary preserve decoding of older scans. File writes/validation precede atomic manifest publication.
- Model I/O reuse; SceneKit for native preview, no new third-party dependencies. Apple sample license retained in app/source.

## Latest verified build

Version **0.3.0 (10)**, source commit c111ccfcc14ed67b1986edafbfcf0ba169ae382a.
Successful run https://github.com/Jzondu/jr-scan-ios/actions/runs/41425218135
Artifact https://github.com/Jzondu/jr-scan-ios/actions/runs/41425218135/artifacts/13131157888 (JRScan-unsigned-10; extract outer ZIP to get JRScan.ipa).
Local IPA build/downloads/run-10/JRScan.ipa; logs build/downloads/run-10/logs.
SHA-256 15e5223018e6f3dad21d86777f7f8342bd69dbc328b7a4d3c002ad5d1cf51294 independently matches CI.
Standard macos-15-intel, X64, image macos15 20260824.0482.1, Xcode16.4(16F6), SDK18.5, XcodeGen2.44.1; minimum iOS18. Native device compilation/packaging succeeded.
Synthetic tests passed: precise crop area, crossing/multi-plane clipping, seam welding, cyclic duplicate/degenerate removal, fragment policies, normals, immutable source, empty crop rejection, edited OBJ write/reload, prior nested transforms/reflections/normal transforms/1000xunits/USDZ import and diagnostic payload safety.
Phone crop/cleanup UI and real edited-export/persistence tests NOT yet performed. Do not claim these passed.

## Next human test, one batch

Install build10 IN PLACE (same identity/account; do not uninstall). Existing scan > Crop & clean mesh > adjust box > Preview changes > Save edited geometry. Check edited preview and export OBJ to Windows. Force-close/reopen and confirm saved edit; check original USDZ and Restore original geometry. If failure, exact step/error plus diagnostics; do not request a new scan first. Retain known-working build9 IPA and external backups. Keep AltStore/JRScan refreshed before free signing expiry.

## Tools/build

Portable gh .tools/gh/bin/gh.exe. Windows Git Credential Manager's cached credential authorizes pushes/API/dispatch; retrieve into process-local GH_TOKEN without printing/logging/persisting secrets or raw credential-fill output. Manual workflow build-ios.yml runner choice macos-15(default) or macos-15-intel; Intel avoided ARM queue previously. Standard runners only, 25min timeout, 7day artifacts. Never use CI to reconstruct personal scans. No local Xcode. README now has editing instructions, limitations, build/test evidence and phone test. Documentation-only commits do not trigger builds.
