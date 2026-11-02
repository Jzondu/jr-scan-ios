# JR Scan restart handoff — 2026-11-02

Resume the existing user task using JR-Scan-Project-Brief.md as the specification.

## Verified state

- Workspace: C:/Users/joona/Documents/ChatGPT/IOS 3Dscanner
- GitHub: https://github.com/Jzondu/jr-scan-ios (public), branch main.
- Commit 3b0c170 implements Milestones 0–1 source: SwiftUI install-check app, project.yml, pinned/checksummed XcodeGen 2.44.1 build script, manual macos-15 unsigned device IPA Actions workflow, README.
- Stable bundle ID: fi.jzondu.jrscan. Minimum iOS 18.0. Keep identity fixed.
- At restart handoff, git ls-remote confirmed origin/main is 3b0c17050c8999bc54327d773e905ec106625c15. The earlier authentication/push blocker has therefore cleared for Git transport. GitHub CLI API authentication is not yet verified.
- No Xcode compilation, IPA artifact, installation, camera/sensor or persistence device test has been verified. Do not claim success without checking actual Actions evidence.
- Windows checks: git diff --check passed, build script has LF/no BOM, downloaded XcodeGen ZIP hash matched the script. No local Xcode available.

## Next actions

1. Inspect current GitHub Actions runs and CLI authentication; do not assume an earlier process survived the reboot.
2. Portable GitHub CLI is available at .tools/gh/bin/gh.exe (ignored, local only). Earlier gh auth status showed no login. If necessary user can run: .\.tools\gh\bin\gh.exe auth login --web --git-protocol https --scopes workflow
3. Once API access permits, dispatch .github/workflows/build-ios.yml on main, follow the run, fix real compiler/build errors, commit meaningful fixes, and produce the downloadable JRScan-unsigned-N artifact containing JRScan.ipa. If API dispatch is unavailable, exact manual route: repository Actions > Build unsigned iPhone IPA > Run workflow > main > Run workflow.
4. Batch human requests after a successful build: exact phone iOS version, AltStore Classic installed/opening, IPA launch, both capabilities Supported, camera permission, persistent marker ID stable and count incrementing after force-close/relaunch. iOS version and AltStore status were asked but no answer received before reboot request.
5. Only after installation confirmation implement guided Object Capture -> on-device .reduced reconstruction -> preview -> geometry OBJ export (meters/mm), then remaining essentials from brief. No cloud reconstruction server, Apple credentials in CI, paid signing/services, or premature polished scanning UI. Inspect/preserve sample licenses before reuse.

User constraints: iPhone 16 Pro, Windows, no Mac, limited time. Work autonomously, batch human-only tasks, concise summaries, meaningful commits and maintained README. User is restarting their computer and wants to resume this state.
