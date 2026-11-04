# JR Scan — project requirements and Codex handoff

Prepared for Joonas • 29 October 2026 • Planning document; app not yet implemented or device-tested.

## Goal and constraints

Build a personal native iPhone 16 Pro app that uses photographs and LiDAR to reconstruct individual objects and export a usable Wavefront OBJ mesh. The user has Windows, no Mac, and limited time. Prefer a small reliable tool, local processing, and no mandatory subscription or per-scan payment.

Chosen route: Swift/SwiftUI source in GitHub → GitHub Actions hosted macOS build → unsigned device IPA → AltStore Classic/AltServer on Windows signs and installs → physical iPhone tests.

The cloud Mac compiles the app; reconstruction runs on the iPhone. Do not require a rented interactive Mac, paid Apple Developer membership, cloud reconstruction service, OpenAI API, backend, or App Store distribution for the first version.

## Decisions already made

| Item | Decision |
| --- | --- |
| Working app/repository name | JR Scan / jr-scan-ios |
| Target | iPhone 16 Pro; iOS 18+ initially; record actual phone OS before selecting build SDK |
| Implementation | Swift + SwiftUI, RealityKit Object Capture, Model I/O |
| Capture | ObjectCaptureSession and ObjectCaptureView; use Apple's guided workflow |
| Reconstruction | PhotogrammetrySession, supported iOS detail level `.reduced` |
| Initial export | Geometry OBJ; textured OBJ only after geometry is verified |
| Install | AltStore Classic, not AltStore PAL |
| Signing | Free Apple account used locally by AltServer; no Apple credentials in GitHub |
| Storage | Local scan folders; explicit Files/share export; user-controlled deletion |
| Appearance | Simple functional English UI; avoid visual polish until capture/export works |

Use Apple's source sample as a reference or base only after checking its actual license. Apple frameworks are proprietary, even when sample/application source is reusable. Retain required notices for all reused code. Do not assume Apple's sample has an MIT license or apply a blanket MIT license to third-party code.

## Must-have requirements

1. **Capability checks:** Check ObjectCaptureSession.isSupported and PhotogrammetrySession.isSupported; explain unsupported hardware/OS without crashing. Request camera access with a clear purpose string and handle refusal.
2. **Guided capture:** Detect object/bounds, show the framework's coverage and quality feedback, capture multiple passes, and allow finish/cancel. Preserve the framework-generated images and relevant reconstruction/checkpoint data. Avoid replacing guidance with a custom camera pipeline.
3. **Local reconstruction:** Show actual progress and errors. Use only supported iOS configuration; do not advertise desktop quality levels. Explain that the app must stay in the foreground during processing. Save durable input before reconstruction; record interrupted state and offer restart from saved input if supported. Do not promise arbitrary mid-session resume.
4. **Preview:** Rotate and zoom the resulting model. Show reconstruction and export status and distinguish incomplete scans from completed ones.
5. **Geometry OBJ export:** Export nonempty triangle geometry with correct transforms, valid indices, and normals where available. Prefer Model I/O; if conversion fails, report it, retain original output, and fix the conversion. Do not silently substitute a point cloud or rename a USDZ to OBJ.
6. **Explicit scale:** Keep internal coordinates in meters and provide an export choice of meters or millimeters, with numerical coordinate conversion. OBJ has no universal unit declaration: label the selected units and include them in the filename and a small export note. Do not present recovered metric scale as metrology-grade accuracy.
7. **Local scan list:** Stable scan IDs and names, timestamps, processing state, and open/share/delete. Confirm deletion. Reinstalling an update with the same app identity should preserve saved scans; verify this physically rather than assume it.
8. **Backup:** Share/save exported models to Files or AirDrop and allow export of capture inputs if practical. State clearly that uninstalling the app can remove its local data. Do not require iCloud entitlements for ordinary Files sharing.
9. **Diagnostics:** Export a small plain-text log containing app/build version, OS/device, processing stage, and errors. Do not include photographs or account credentials in logs.
10. **Offline operation:** Capture, reconstruction, preview, and export work without a network after installation. GitHub contains code/build outputs, not the user's scans.

## Explicitly deferred

- Custom LiDAR/photogrammetry fusion, custom reconstruction engines, and a separate room-scanning mode.
- Automatic editable CAD/STEP generation, engineering-tolerance guarantees, and automated reverse engineering.
- Advanced mesh repair, hole filling, decimation, cropping, and measurement tools.
- Textured OBJ/MTL/image packaging until geometry export passes; then make it an optional tested enhancement.
- Reference-dimension calibration, printer-specific workflows, branding polish, user accounts, analytics, and cloud sync.

## AI-owned implementation sequence

### Milestone 0 — repository and reproducible cloud build

- Inspect any existing repository instructions; otherwise use this brief as the specification.
- Create a small project, shared scheme, source-controlled project configuration, README, and build/package scripts. XcodeGen is acceptable if its version is recorded and the user does not need it locally.
- Select an available standard GitHub macOS runner and an installed stable Xcode version matching the SDK requirement. Record exact versions in the build output; avoid a fragile unsupported hard-coded path.
- Add a manually triggered GitHub Actions workflow. Optional main-branch push trigger can follow; avoid duplicate/unbounded builds.
- Build Release for a physical device (`generic/platform=iOS`), with signing disabled. Never use a simulator build for the downloadable app.
- Package the built app as `Payload/JRScan.app` at the root of the IPA ZIP. Use a normal single app bundle, no unnecessary extensions, and one persistent unique bundle ID.
- Upload `JRScan.ipa`, build/version information, and useful logs as Actions artifacts. Set a sensible workflow timeout and short artifact retention, e.g. 7 days. The artifact ZIP contains an IPA; document the extraction step explicitly.
- Do not use signing certificates, Apple account passwords, paid distribution profiles, TestFlight, or Developer Program API keys.

### Milestone 1 — installability gate

- Initially ship only a launch screen, camera permission/capability checks, app/build version, and a small local data persistence check.
- Get one cloud build to compile before requesting a phone test.
- User installs through AltStore Classic and reports whether it opens and both capability checks pass.
- Do not build a polished scanning interface before this gate passes. A successful cloud build does not prove AltStore compatibility or sensor access.

### Milestone 2 — end-to-end scanning gate

- Adapt the minimal Apple capture/reconstruction workflow; use Apple's current sample documentation and verify its source license.
- Preserve reconstruction outputs and inputs in per-scan folders. Inspect API output formats; don't assume OBJ is a direct PhotogrammetrySession output on iOS.
- Add preview, geometry conversion/export, explicit export units, and minimal diagnostics.
- Compile and fix SDK/type/availability issues through cloud builds.
- Ask the user for one controlled scan test only after there is a downloadable build.

### Milestone 3 — make the tool dependable

- Add scan list, errors/cancellation/interruption handling, backups, and clear disk-space failure messages.
- Test model persistence after app restart and update; verify Files export on Windows in Blender or MeshLab.
- Add basic texturing only if requested after geometry is useful. Avoid scope expansion to fill time while a device test is pending.
- Tag a known-good version and write short install/update/refresh instructions using real artifact filenames.

## Human-only checklist

### Do once: accounts and repository

- [ ] Sign in to GitHub, or create a free account.
- [ ] Create `jr-scan-ios`, initialized with a README. Choose **public** if comfortable exposing the source: standard GitHub-hosted runner compute is currently free for public repositories. Personal use does not require a private repository. A private repository is also possible, but has usage allowances; avoid enabling paid overages.
- [ ] Open Codex Cloud on web/desktop, connect GitHub, and grant access to this repository. Create/publish its environment if requested by the interface. Do not spend time setting up Xcode inside a Linux environment; macOS Actions handles compilation.
- [ ] Add this file to the repository root and give Codex the kickoff prompt below.

### Do once: Windows and iPhone

- [ ] Follow the official Windows AltStore Classic guide: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows . Use its specified Apple components and troubleshooting instructions; don't substitute AltStore PAL.
- [ ] Install/run AltServer; connect the phone by USB; accept Trust prompts; enable Wi-Fi sync as instructed.
- [ ] Use AltServer's Install AltStore action and enter the Apple account credentials locally. Never put them into ChatGPT, Codex, source files, or GitHub secrets.
- [ ] On iPhone, trust the developer profile if requested and enable Developer Mode under Settings → Privacy & Security, including the restart/confirmation. Confirm AltStore opens.
- [ ] Tell Codex the iPhone's exact iOS version and whether AltStore opens. This is all the device information needed initially.

### When each test build is ready

- [ ] Open GitHub repository → Actions → the successful build → Artifacts. Download the build, extract the outer artifact ZIP on Windows, and transfer the `.ipa` to iPhone Files (e.g. iCloud Drive).
- [ ] With AltServer running, open AltStore Classic → My Apps → + and choose the IPA. Accept relevant installation/camera prompts. If names differ, use the current official AltStore instructions.
- [ ] First build: report whether the app opens and capability checks pass. Later build: scan one textured matte object, export OBJ, and check it on Windows. Send a log/error screenshot only when a step fails.
- [ ] Before an update, export important work. Keep the same bundle ID and signing account; verify scans survive an update. Do not delete the installed app as a routine fix.

### Ongoing

- [ ] Keep AltServer running when practical and let the phone connect to it. Check/refresh both AltStore and JR Scan before the seven-day expiry; automatic refresh is best-effort, not guaranteed. USB is a fallback if network discovery fails.
- [ ] Back up important scans externally. Keep a copy of the known-good IPA; GitHub artifact downloads expire separately from app signing.

## Device acceptance tests (short and repeatable)

| Test | Pass condition |
| --- | --- |
| Installation | Free-account AltStore installs the IPA and app launches on the real phone |
| Capability | Object capture and reconstruction checks report support |
| Capture/reconstruct | Matte textured object can be captured and reconstructed locally |
| Export | OBJ opens as a triangle mesh in Blender/MeshLab, without missing chunks caused by unapplied transforms |
| Units | The same model exported in mm has coordinate dimensions 1000× its meter export; physical scale is compared with a known measurement and discrepancy recorded |
| Persistence | Saved model is available after force-closing/relaunching and after an in-place app update |
| Interruptions | Cancellation/processing failure preserves inputs and displays an actionable state |
| Backup | User can save the model outside the app and reopen it on Windows |
| Refresh | App launches after an AltStore refresh; scan data remains present |

For a reference object, choose a static matte textured object roughly 10–30 cm across. This is a test suggestion, not a promised sensor resolution or supported size limit. Start with forgiving geometry before reflective mechanical parts. A visually convincing scan is not evidence of dimensional accuracy.

## Costs, limitations, and unresolved risks

- No intended runtime backend, per-scan fee, or Apple membership requirement on this route. Free signing currently requires a refresh every seven days; free accounts have app limits, and AltStore itself takes an app slot.
- GitHub public-repository standard runner compute is currently free; storage/retention and service policies still apply. Private repositories have included usage and possible charges if paid overages are enabled. Codex usage depends on the user's plan and limits; no unlimited free development promise is made.
- Apple's current iOS photogrammetry supports `.reduced` only. Higher desktop detail levels are outside this version. Thin, reflective, transparent, or featureless objects may reconstruct poorly. No scanner-style tolerance is promised.
- The unsigned device build → AltStore → Object Capture integration has not been verified for this project. Treat it as the first technical risk, not a guaranteed finished solution. If blocked, record the actual error and investigate a compatible fix before suggesting payment or changing the route.
- Physical sensor testing requires the user. Cloud CI cannot verify reconstruction quality or app behavior on the user's phone. Device tests should be batched to minimize interruptions.

## Copy/paste kickoff prompt for Codex

> Implement JR Scan using JR-Scan-Project-Brief.md as the specification. I have an iPhone 16 Pro, Windows, no Mac, and limited time. Use GitHub Actions macOS for unsigned device IPA builds and AltStore Classic for free-account signing/install. Do not require paid services or Apple credentials in CI. Work autonomously through repository setup, minimal native app, and a reproducible build workflow. Keep a stable unique bundle ID. First achieve Milestones 0–1 and produce a downloadable IPA if GitHub permissions permit; otherwise provide the exact minimal action I must take to commit/run the workflow. Do not claim compilation or device tests passed without evidence. After installation is confirmed, implement the Object Capture → on-device reconstruction → geometry OBJ export path and the remaining essentials. Preserve applicable sample licenses. Batch human-only tasks and test requests; keep summaries concise. Commit meaningful work and maintain README build/install instructions. Do not ask me to design screens or choose libraries when this brief already supplies a sensible default. The cloud build machine is not the runtime reconstruction server.

## Reference documentation

Checked 29 October 2026. Recheck APIs, platform requirements, and service limits during implementation.

- Apple sample and requirements: https://developer.apple.com/documentation/realitykit/scanning-objects-using-object-capture
- Capture/reconstruction workflow: https://developer.apple.com/videos/play/wwdc2023/10191/
- iOS detail restriction: https://developer.apple.com/documentation/realitykit/photogrammetrysession/request/detail
- Model I/O export support: https://developer.apple.com/documentation/modelio/mdlasset/canexportfileextension(_:)
- Photography constraints: https://developer.apple.com/documentation/realitykit/capturing-photographs-for-realitykit-object-capture
- GitHub macOS runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- GitHub usage and billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- AltStore Windows installation: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- AltServer and refresh: https://faq.altstore.io/altstore-classic/altserver
- AltStore Classic limits: https://developer.altstore.io/
- Codex Cloud setup: https://learn.chatgpt.com/docs/cloud

This brief is the handoff. No repository, Actions workflow, or app binary has been created by this planning task.

## Subsequent scope decisions — 4 November 2026

The planning status above is historical. JR Scan is implemented; the user reported working photo reconstruction and later working build 18 LiDAR capture/save. The user explicitly requested crop/cleanup, live LiDAR, then a combined mode and useful tools, clarifying that the primary use is objects and parts for 3D printing or modeling.

Version 0.5.0 exposes Apple's existing photo-plus-LiDAR Object Capture pipeline as Combined detail, with three-height guidance and saved depth-sample inspection. It retains the iOS Reduced level and on-device limits; it does not claim custom mesh fusion, automatic alignment of independent scans, or a measured resolution improvement. The user-requested tools now include dimensions, surface-point measurement, uniform reference-length calibration, 90-degree orientation, Z-up bed placement, edge diagnostics and millimeter STL export. These supersede the corresponding original deferrals. Automatic hole filling, CAD/STEP generation, engineering-tolerance guarantees and cloud reconstruction remain outside the current implementation. README and HANDOFF record current build evidence and remaining device tests.
